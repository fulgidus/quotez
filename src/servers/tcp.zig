const std = @import("std");
const logger = @import("../logger.zig");
const quote_store = @import("../quote_store.zig");
const selector = @import("../selector.zig");

const Logger = logger.Logger;
const QuoteStore = quote_store.QuoteStore;
const Selector = selector.Selector;

/// TCP QOTD Server implementing RFC 865
/// Accepts connections, sends one quote, then closes
pub const TcpServer = struct {
    address: std.net.Address,
    listener: std.posix.socket_t,
    quote_store: *QuoteStore,
    selector: *Selector,
    log: Logger,
    allocator: std.mem.Allocator,
    running: bool,

    /// Initialize TCP server
    pub fn init(
        allocator: std.mem.Allocator,
        host: []const u8,
        port: u16,
        quote_store_ptr: *QuoteStore,
        selector_ptr: *Selector,
    ) !TcpServer {
        const log = Logger.init();

        // Parse address
        const address = try std.net.Address.parseIp(host, port);

        // Create TCP socket (non-blocking for poll-based event loop)
        const socket = try std.posix.socket(
            address.any.family,
            std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC | std.posix.SOCK.NONBLOCK,
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

        return TcpServer{
            .address = address,
            .listener = socket,
            .quote_store = quote_store_ptr,
            .selector = selector_ptr,
            .log = log,
            .allocator = allocator,
            .running = false,
        };
    }

    /// Bind and start listening
    pub fn listen(self: *TcpServer) !void {
        try std.posix.bind(self.listener, &self.address.any, self.address.getOsSockLen());
        try std.posix.listen(self.listener, 128);
        self.running = true;

        self.log.info("tcp_server_listening", .{
            .port = self.address.getPort(),
        });
    }

    /// Accept and handle one connection
    /// Returns true if connection was handled, false on error
    pub fn acceptOne(self: *TcpServer) !bool {
        if (!self.running) return false;

        // Accept connection
        var client_addr: std.posix.sockaddr = undefined;
        var addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);

        const client_socket = std.posix.accept(self.listener, &client_addr, &addr_len, std.posix.SOCK.NONBLOCK) catch |err| {
            switch (err) {
                error.WouldBlock => return false,
                error.ConnectionAborted => return false,
                else => {
                    self.log.warn("tcp_accept_error", .{ .err = @errorName(err) });
                    return err;
                },
            }
        };
        defer std.posix.close(client_socket);

        // Handle the connection
        self.handleConnection(client_socket) catch |err| {
            self.log.warn("tcp_connection_error", .{ .err = @errorName(err) });
            return false;
        };

        return true;
    }

    /// Handle a single connection: send quote and close
    fn handleConnection(self: *TcpServer, client_socket: std.posix.socket_t) !void {
        // Check if quote store is empty
        if (self.quote_store.isEmpty()) {
            // RFC 865: Close immediately if no quote available
            self.log.warn("tcp_empty_store", .{});
            return;
        }

        // Get next quote via selector
        const index = self.selector.next(self.quote_store.count()) orelse {
            self.log.warn("tcp_selector_failed", .{});
            return;
        };

        const quote_text = self.quote_store.get(index) orelse {
            self.log.warn("tcp_quote_not_found", .{ .index = index });
            return;
        };

        // Send quote with newline terminator (RFC 865)
        _ = std.posix.send(client_socket, quote_text, 0) catch |err| {
            self.log.warn("tcp_send_error", .{ .err = @errorName(err) });
            return;
        };
        _ = std.posix.send(client_socket, "\n", 0) catch {};

        // Connection automatically closes on return (defer above)
    }

    /// Stop the server
    pub fn stop(self: *TcpServer) void {
        if (self.running) {
            self.running = false;
            std.posix.close(self.listener);
            self.log.info("tcp_server_stopped", .{});
        }
    }

    /// Get the underlying socket for poll()
    pub fn getSocket(self: *TcpServer) std.posix.socket_t {
        return self.listener;
    }

    /// Cleanup
    pub fn deinit(self: *TcpServer) void {
        self.stop();
    }
};

// Unit tests
test "tcp server init" {
    const allocator = std.testing.allocator;

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    var sel = try Selector.init(allocator, .random, 0);
    defer sel.deinit();

    var server = try TcpServer.init(
        allocator,
        "127.0.0.1",
        18017, // Non-privileged port for testing
        &store,
        &sel,
    );
    defer server.deinit();

    try std.testing.expect(!server.running);
}

test "tcp server listen" {
    const allocator = std.testing.allocator;

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    var sel = try Selector.init(allocator, .random, 0);
    defer sel.deinit();

    var server = try TcpServer.init(
        allocator,
        "127.0.0.1",
        18018,
        &store,
        &sel,
    );
    defer server.deinit();

    try server.listen();
    try std.testing.expect(server.running);

    server.stop();
    try std.testing.expect(!server.running);
}
