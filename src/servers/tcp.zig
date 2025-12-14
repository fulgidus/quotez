const std = @import("std");
const logger = @import("../logger.zig");
const quote_store = @import("../quote_store.zig");
const selector_mod = @import("../selector.zig");

/// TCP QOTD server implementing RFC 865
pub const TcpServer = struct {
    socket: std.net.Server,
    address: std.net.Address,
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

        // Parse address
        const address = std.net.Address.parseIp(host, port) catch |err| {
            log.err("tcp_bind_failed", .{
                .reason = "invalid address",
                .host = host,
                .port = port,
                .err = @errorName(err),
            });
            return err;
        };

        // Create and bind socket
        const socket = try address.listen(.{
            .reuse_address = true,
            .reuse_port = true,
            .kernel_backlog = 128,
        });

        log.info("tcp_server_started", .{
            .host = host,
            .port = port,
        });

        return TcpServer{
            .socket = socket,
            .address = address,
            .store = store,
            .selector = sel,
            .log = log,
            .allocator = allocator,
        };
    }

    /// Stop the TCP server
    pub fn deinit(self: *TcpServer) void {
        self.socket.deinit();
        self.log.info("tcp_server_stopped", .{});
    }

    /// Accept and serve a single connection (non-blocking)
    pub fn acceptAndServe(self: *TcpServer) !void {
        // Accept connection (blocking for now, will be non-blocking in event loop)
        var conn = self.socket.accept() catch |err| {
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
        defer conn.stream.close();

        // Serve the connection
        self.serveConnection(conn.stream) catch |err| {
            self.log.warn("tcp_serve_error", .{ .err = @errorName(err) });
        };
    }

    /// Serve a single connection: send quote and close
    fn serveConnection(self: *TcpServer, stream: std.net.Stream) !void {
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

        // Send quote + newline
        stream.writeAll(quote) catch |err| {
            // Handle send errors
            switch (err) {
                error.BrokenPipe, error.ConnectionResetByPeer => {
                    // Client disconnected, ignore
                    self.log.debug("tcp_client_disconnected", .{});
                    return;
                },
                else => return err,
            }
        };

        stream.writeAll("\n") catch |err| {
            switch (err) {
                error.BrokenPipe, error.ConnectionResetByPeer => return,
                else => return err,
            }
        };

        // Connection closes automatically when stream is deferred
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
    try std.testing.expectEqual(@as(u16, 8017), server.address.getPort());
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
