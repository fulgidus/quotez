const std = @import("std");
const logger = @import("../logger.zig");
const quote_store = @import("../quote_store.zig");
const selector_mod = @import("../selector.zig");

/// Parse an IPv4 string like "127.0.0.1" or "0.0.0.0" into a big-endian u32
fn parseIp4(host: []const u8) !u32 {
    if (std.mem.eql(u8, host, "0.0.0.0")) return 0;
    if (std.mem.eql(u8, host, "127.0.0.1")) return std.mem.nativeToBig(u32, 0x7F000001);

    var parts = std.mem.splitScalar(u8, host, '.');
    var result: u32 = 0;
    var count: usize = 0;
    while (parts.next()) |part| {
        if (count >= 4) return error.InvalidIp;
        const val = try std.fmt.parseInt(u8, part, 10);
        result = (result << 8) | val;
        count += 1;
    }
    if (count != 4) return error.InvalidIp;
    return std.mem.nativeToBig(u32, result);
}

/// TCP QOTD server implementing RFC 865
pub const TcpServer = struct {
    socket: std.posix.socket_t,
    address: std.posix.sockaddr.in,
    store: *quote_store.QuoteStore,
    selector: *selector_mod.Selector,
    log: logger.Logger,
    allocator: std.mem.Allocator,

    /// Initialize and bind TCP server
    pub fn init(
        allocator: std.mem.Allocator,
        host: []const u8,
        port: u16,
        store: *quote_store.QuoteStore,
        sel: *selector_mod.Selector,
    ) !TcpServer {
        var log = logger.Logger.init();

        // Parse host string into IPv4 bytes
        const parsed_bytes = parseIp4(host) catch |err| {
            log.err("tcp_bind_failed", .{
                .reason = "invalid address",
                .host = host,
                .port = port,
                .err = @errorName(err),
            });
            return err;
        };

        const addr = std.posix.sockaddr.in{
            .family = std.posix.AF.INET,
            .port = std.mem.nativeToBig(u16, port),
            .addr = parsed_bytes,
        };

        // Create socket
        const socket = try std.posix.socket(
            std.posix.AF.INET,
            std.posix.SOCK.STREAM,
            std.posix.IPPROTO.TCP,
        );
        errdefer std.posix.close(socket);

        // Set socket options
        try std.posix.setsockopt(
            socket,
            std.posix.SOL.SOCKET,
            std.posix.SO.REUSEADDR,
            &std.mem.toBytes(@as(c_int, 1)),
        );

        // Bind socket
        try std.posix.bind(socket, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.in));

        // Listen
        try std.posix.listen(socket, 128);

        // Set non-blocking mode for event loop
        const flags = try std.posix.fcntl(socket, std.posix.F.GETFL, 0);
        const nonblock_flag = @as(usize, @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true })));
        _ = try std.posix.fcntl(socket, std.posix.F.SETFL, flags | nonblock_flag);

        log.info("tcp_server_started", .{
            .host = host,
            .port = port,
        });

        return TcpServer{
            .socket = socket,
            .address = addr,
            .store = store,
            .selector = sel,
            .log = log,
            .allocator = allocator,
        };
    }

    /// Stop the TCP server
    pub fn deinit(self: *TcpServer) void {
        std.posix.close(self.socket);
        self.log.info("tcp_server_stopped", .{});
    }

    /// Accept and serve a single connection (non-blocking)
    pub fn acceptAndServe(self: *TcpServer) !void {
        var client_addr: std.posix.sockaddr.storage = undefined;
        var client_addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.storage);
        
        // Accept connection
        const client_fd = std.posix.accept(
            self.socket,
            @ptrCast(&client_addr),
            &client_addr_len,
            0,
        ) catch |err| {
            // Non-fatal errors that we can recover from
            switch (err) {
                error.WouldBlock => return, // No connection available
                error.ConnectionAborted, error.ConnectionResetByPeer => {
                    self.log.warn("tcp_accept_error", .{ .err = @errorName(err) });
                    return;
                },
                else => return err,
            }
        };
        defer std.posix.close(client_fd);

        // Check if quote store is empty
        if (self.store.isEmpty()) {
            // Close immediately without sending (per contract)
            self.log.debug("tcp_request_empty_store", .{});
            return;
        }

        // Select next quote
        const quote_index = try self.selector.next();
        const quote = self.store.get(quote_index) orelse {
            // Quote index out of bounds (shouldn't happen)
            self.log.warn("tcp_invalid_quote_index", .{ .index = quote_index });
            return;
        };

        // Send quote
        _ = std.posix.send(client_fd, quote, 0) catch |err| {
            // Handle send errors
            switch (err) {
                error.BrokenPipe, error.ConnectionResetByPeer => {
                    // Client disconnected, ignore
                    self.log.debug("tcp_client_disconnected", .{});
                    return;
                },
                else => {
                    self.log.warn("tcp_serve_error", .{ .err = @errorName(err) });
                    return;
                },
            }
        };

        // Send newline
        _ = std.posix.send(client_fd, "\n", 0) catch |err| {
            switch (err) {
                error.BrokenPipe, error.ConnectionResetByPeer => return,
                else => {
                    self.log.warn("tcp_serve_error", .{ .err = @errorName(err) });
                    return;
                },
            }
        };

        // Connection closes automatically when client_fd is deferred
        self.log.debug("tcp_request_served", .{ .quote_length = quote.len });
    }

    /// Run server loop (blocking, serves connections until stopped)
    pub fn run(self: *TcpServer) !void {
        self.log.info("tcp_server_listening", .{
            .address = self.address,
        });

        while (true) {
            try self.acceptAndServe();
        }
    }
};

// Tests
test "tcp server initialization" {
    const allocator = std.testing.allocator;

    var store = quote_store.QuoteStore.init(allocator);
    defer store.deinit();

    var sel = try selector_mod.Selector.init(allocator, .random, 0);
    defer sel.deinit();

    // Try to bind to a high port (non-privileged)
    var server = TcpServer.init(allocator, "127.0.0.1", 8017, &store, &sel) catch |err| {
        // May fail if port is in use, which is okay for testing
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer server.deinit();

    // Server should be initialized
    try std.testing.expectEqual(@as(u16, 8017), std.mem.bigToNative(u16, server.address.port));
}

test "tcp serve connection with empty store" {
    const allocator = std.testing.allocator;

    var store = quote_store.QuoteStore.init(allocator);
    defer store.deinit();

    var sel = try selector_mod.Selector.init(allocator, .random, 0);
    defer sel.deinit();

    var server = TcpServer.init(allocator, "127.0.0.1", 8018, &store, &sel) catch |err| {
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer server.deinit();

    // Empty store should not crash
    try std.testing.expect(store.isEmpty());
}
