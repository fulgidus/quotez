const std = @import("std");
const logger = @import("../logger.zig");
const quote_store = @import("../quote_store.zig");
const selector = @import("../selector.zig");

const Logger = logger.Logger;
const QuoteStore = quote_store.QuoteStore;
const Selector = selector.Selector;

/// UDP QOTD Server implementing RFC 865
/// Receives datagrams and responds with quotes
pub const UdpServer = struct {
    socket: std.posix.socket_t,
    address: std.net.Address,
    quote_store: *QuoteStore,
    selector: *Selector,
    log: Logger,
    allocator: std.mem.Allocator,
    running: bool,

    /// Initialize UDP server
    pub fn init(
        allocator: std.mem.Allocator,
        host: []const u8,
        port: u16,
        quote_store_ptr: *QuoteStore,
        selector_ptr: *Selector,
    ) !UdpServer {
        const log = Logger.init();

        // Parse address
        const address = try std.net.Address.parseIp(host, port);

        // Create UDP socket (non-blocking for poll-based event loop)
        const socket = try std.posix.socket(
            address.any.family,
            std.posix.SOCK.DGRAM | std.posix.SOCK.CLOEXEC | std.posix.SOCK.NONBLOCK,
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

        return UdpServer{
            .socket = socket,
            .address = address,
            .quote_store = quote_store_ptr,
            .selector = selector_ptr,
            .log = log,
            .allocator = allocator,
            .running = false,
        };
    }

    /// Bind socket and start listening
    pub fn listen(self: *UdpServer) !void {
        try std.posix.bind(self.socket, &self.address.any, self.address.getOsSockLen());
        self.running = true;

        self.log.info("udp_server_listening", .{
            .port = self.address.getPort(),
        });
    }

    /// Receive and respond to one datagram
    /// Returns true if datagram was handled, false on error or would block
    pub fn handleOne(self: *UdpServer) !bool {
        if (!self.running) return false;

        var recv_buf: [512]u8 = undefined;
        var src_addr: std.posix.sockaddr = undefined;
        var src_addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);

        // Receive datagram (non-blocking)
        const recv_len = std.posix.recvfrom(
            self.socket,
            &recv_buf,
            0,
            &src_addr,
            &src_addr_len,
        ) catch |err| {
            switch (err) {
                error.WouldBlock => return false,
                else => {
                    self.log.warn("udp_recv_error", .{ .err = @errorName(err) });
                    return err;
                },
            }
        };

        _ = recv_len; // Content is ignored per RFC 865

        // Check if quote store is empty
        if (self.quote_store.isEmpty()) {
            // RFC 865: Silent drop if no quote available (no response sent)
            self.log.warn("udp_empty_store", .{});
            return true;
        }

        // Get next quote via selector
        const index = self.selector.next(self.quote_store.count()) orelse {
            self.log.warn("udp_selector_failed", .{});
            return true;
        };

        const quote_text = self.quote_store.get(index) orelse {
            self.log.warn("udp_quote_not_found", .{ .index = index });
            return true;
        };

        // Prepare response (quote + newline)
        var response_buf: [1024]u8 = undefined;
        const response = if (quote_text.len < response_buf.len - 1) blk: {
            @memcpy(response_buf[0..quote_text.len], quote_text);
            response_buf[quote_text.len] = '\n';
            break :blk response_buf[0 .. quote_text.len + 1];
        } else blk: {
            // Quote too long, truncate to fit in UDP packet
            const max_len = response_buf.len - 1;
            @memcpy(response_buf[0..max_len], quote_text[0..max_len]);
            response_buf[max_len] = '\n';
            self.log.warn("udp_quote_truncated", .{ .original_len = quote_text.len, .max_len = max_len });
            break :blk response_buf[0..response_buf.len];
        };

        // Send response
        _ = std.posix.sendto(
            self.socket,
            response,
            0,
            &src_addr,
            src_addr_len,
        ) catch |err| {
            self.log.warn("udp_send_error", .{ .err = @errorName(err) });
            return false;
        };

        return true;
    }

    /// Stop the server
    pub fn stop(self: *UdpServer) void {
        if (self.running) {
            self.running = false;
            std.posix.close(self.socket);
            self.log.info("udp_server_stopped", .{});
        }
    }

    /// Cleanup
    pub fn deinit(self: *UdpServer) void {
        self.stop();
    }

    /// Get socket file descriptor for poll()
    pub fn getSocket(self: *const UdpServer) std.posix.socket_t {
        return self.socket;
    }
};

// Unit tests
test "udp server init" {
    const allocator = std.testing.allocator;

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    var sel = try Selector.init(allocator, .random, 0);
    defer sel.deinit();

    var server = try UdpServer.init(
        allocator,
        "127.0.0.1",
        19017, // Non-privileged port for testing
        &store,
        &sel,
    );
    defer server.deinit();

    try std.testing.expect(!server.running);
}

test "udp server listen" {
    const allocator = std.testing.allocator;

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    var sel = try Selector.init(allocator, .random, 0);
    defer sel.deinit();

    var server = try UdpServer.init(
        allocator,
        "127.0.0.1",
        19018,
        &store,
        &sel,
    );
    defer server.deinit();

    try server.listen();
    try std.testing.expect(server.running);

    server.stop();
    try std.testing.expect(!server.running);
}
