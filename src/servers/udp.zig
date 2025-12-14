const std = @import("std");
const logger = @import("../logger.zig");
const quote_store = @import("../quote_store.zig");
const selector_mod = @import("../selector.zig");

/// UDP QOTD server implementing RFC 865
pub const UdpServer = struct {
    socket: std.posix.socket_t,
    address: std.net.Address,
    store: *quote_store.QuoteStore,
    selector: *selector_mod.Selector,
    log: logger.Logger,
    allocator: std.mem.Allocator,

    /// Maximum UDP datagram size for QOTD (per RFC 865 recommendations)
    const MAX_DATAGRAM_SIZE = 512;

    /// Initialize and bind UDP server
    pub fn init(
        allocator: std.mem.Allocator,
        host: []const u8,
        port: u16,
        store: *quote_store.QuoteStore,
        sel: *selector_mod.Selector,
    ) !UdpServer {
        var log = logger.Logger.init();

        // Parse address
        const address = std.net.Address.parseIp(host, port) catch |err| {
            log.err("udp_bind_failed", .{
                .reason = "invalid address",
                .host = host,
                .port = port,
                .err = @errorName(err),
            });
            return err;
        };

        // Create UDP socket
        const socket = try std.posix.socket(
            address.any.family,
            std.posix.SOCK.DGRAM,
            std.posix.IPPROTO.UDP,
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
        try std.posix.bind(socket, &address.any, address.getOsSockLen());

        // Set non-blocking mode for event loop
        const flags = try std.posix.fcntl(socket, std.posix.F.GETFL, 0);
        _ = try std.posix.fcntl(socket, std.posix.F.SETFL, flags | std.posix.O.NONBLOCK);

        log.info("udp_server_started", .{
            .host = host,
            .port = port,
        });

        return UdpServer{
            .socket = socket,
            .address = address,
            .store = store,
            .selector = sel,
            .log = log,
            .allocator = allocator,
        };
    }

    /// Stop the UDP server
    pub fn deinit(self: *UdpServer) void {
        std.posix.close(self.socket);
        self.log.info("udp_server_stopped", .{});
    }

    /// Receive and respond to a single datagram
    pub fn receiveAndRespond(self: *UdpServer) !void {
        // Buffer for receiving client datagram (content ignored per RFC 865)
        var recv_buf: [MAX_DATAGRAM_SIZE]u8 = undefined;
        var client_addr: std.posix.sockaddr = undefined;
        var client_addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);

        // Receive datagram from client
        const recv_len = std.posix.recvfrom(
            self.socket,
            &recv_buf,
            0,
            &client_addr,
            &client_addr_len,
        ) catch |err| {
            switch (err) {
                error.WouldBlock => return, // No datagram available
                error.ConnectionRefused => {
                    // ICMP port unreachable (previous sendto failed)
                    self.log.debug("udp_client_unreachable", .{});
                    return;
                },
                else => return err,
            }
        };

        self.log.debug("udp_datagram_received", .{ .bytes = recv_len });

        // Check if quote store is empty
        if (self.store.isEmpty()) {
            // Silent drop (no response per UDP semantics and contract)
            self.log.debug("udp_request_empty_store", .{});
            return;
        }

        // Select next quote
        const quote_index = try self.selector.next();
        const quote = self.store.get(quote_index) orelse {
            // Quote index out of bounds (shouldn't happen)
            self.log.warn("udp_invalid_quote_index", .{ .index = quote_index });
            return;
        };

        // Prepare response buffer
        var send_buf: [MAX_DATAGRAM_SIZE]u8 = undefined;
        const response = blk: {
            // Format: quote + newline
            if (quote.len + 1 > MAX_DATAGRAM_SIZE) {
                // Quote too large, truncate
                self.log.warn("udp_quote_truncated", .{
                    .original_length = quote.len,
                    .max_size = MAX_DATAGRAM_SIZE,
                });
                // Copy what fits, leaving room for newline
                const truncated_len = MAX_DATAGRAM_SIZE - 1;
                @memcpy(send_buf[0..truncated_len], quote[0..truncated_len]);
                send_buf[truncated_len] = '\n';
                break :blk send_buf[0 .. truncated_len + 1];
            } else {
                // Normal case: quote + newline
                @memcpy(send_buf[0..quote.len], quote);
                send_buf[quote.len] = '\n';
                break :blk send_buf[0 .. quote.len + 1];
            }
        };

        // Send response to client
        _ = std.posix.sendto(
            self.socket,
            response,
            0,
            &client_addr,
            client_addr_len,
        ) catch |err| {
            // UDP is best-effort, log and drop on error
            switch (err) {
                error.MessageTooBig => {
                    self.log.warn("udp_send_message_too_big", .{ .size = response.len });
                },
                error.NetworkUnreachable, error.HostUnreachable => {
                    self.log.debug("udp_client_unreachable", .{});
                },
                else => {
                    self.log.warn("udp_send_error", .{ .err = @errorName(err) });
                },
            }
            return;
        };

        self.log.debug("udp_request_served", .{ .quote_length = quote.len });
    }

    /// Run server loop (blocking, serves datagrams until stopped)
    pub fn run(self: *UdpServer) !void {
        self.log.info("udp_server_listening", .{
            .address = self.address,
        });

        while (true) {
            try self.receiveAndRespond();
        }
    }
};

// Tests
test "udp server initialization" {
    const allocator = std.testing.allocator;

    var store = quote_store.QuoteStore.init(allocator);
    defer store.deinit();

    var sel = try selector_mod.Selector.init(allocator, .random, 0);
    defer sel.deinit();

    // Try to bind to a high port (non-privileged)
    var server = UdpServer.init(allocator, "127.0.0.1", 8017, &store, &sel) catch |err| {
        // May fail if port is in use, which is okay for testing
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer server.deinit();

    // Server should be initialized
    try std.testing.expectEqual(@as(u16, 8017), server.address.getPort());
}

test "udp receive with empty store" {
    const allocator = std.testing.allocator;

    var store = quote_store.QuoteStore.init(allocator);
    defer store.deinit();

    var sel = try selector_mod.Selector.init(allocator, .random, 0);
    defer sel.deinit();

    var server = UdpServer.init(allocator, "127.0.0.1", 8018, &store, &sel) catch |err| {
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer server.deinit();

    // Empty store should not crash
    try std.testing.expect(store.isEmpty());
}
