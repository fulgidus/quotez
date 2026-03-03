const std = @import("std");
const logger = @import("../logger.zig");
const quote_store = @import("../quote_store.zig");

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

/// HTTP health endpoint server
pub const HttpServer = struct {
    socket: std.posix.socket_t,
    address: std.posix.sockaddr.in,
    store: *quote_store.QuoteStore,
    log: logger.Logger,
    allocator: std.mem.Allocator,

    /// Initialize and bind HTTP server
    pub fn init(
        allocator: std.mem.Allocator,
        host: []const u8,
        port: u16,
        store: *quote_store.QuoteStore,
    ) !HttpServer {
        var log = logger.Logger.init();

        // Parse host string into IPv4 bytes
        const parsed_bytes = parseIp4(host) catch |err| {
            log.err("http_bind_failed", .{
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

        log.info("http_server_started", .{
            .host = host,
            .port = port,
        });

        return HttpServer{
            .socket = socket,
            .address = addr,
            .store = store,
            .log = log,
            .allocator = allocator,
        };
    }

    /// Stop the HTTP server
    pub fn deinit(self: *HttpServer) void {
        std.posix.close(self.socket);
        self.log.info("http_server_stopped", .{});
    }

    /// Accept and serve a single connection (non-blocking)
    pub fn acceptAndServe(self: *HttpServer) !void {
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
                error.ConnectionAborted => {
                    self.log.warn("http_accept_error", .{ .err = @errorName(err) });
                    return;
                },
                else => return err,
            }
        };
        defer std.posix.close(client_fd);

        // Read HTTP request
        var buf: [4096]u8 = undefined;
        const n = std.posix.recv(client_fd, &buf, 0) catch |err| {
            switch (err) {
                error.ConnectionResetByPeer => {
                    self.log.debug("http_client_disconnected", .{});
                    return;
                },
                else => {
                    self.log.warn("http_recv_error", .{ .err = @errorName(err) });
                    return;
                },
            }
        };

        if (n == 0) {
            // Client closed connection
            return;
        }

        const request = buf[0..n];

        // Parse HTTP request: extract method and path
        var lines = std.mem.splitScalar(u8, request, '\n');
        const first_line = lines.next() orelse {
            self.sendResponse(client_fd, 400, "Bad Request", "text/plain", "Bad Request") catch {};
            return;
        };

        // Parse "GET /health HTTP/1.1"
        var parts = std.mem.splitScalar(u8, first_line, ' ');
        const method = parts.next() orelse {
            self.sendResponse(client_fd, 400, "Bad Request", "text/plain", "Bad Request") catch {};
            return;
        };
        const path_raw = parts.next() orelse {
            self.sendResponse(client_fd, 400, "Bad Request", "text/plain", "Bad Request") catch {};
            return;
        };

        // Trim trailing \r from path if present
        const path = std.mem.trimRight(u8, path_raw, "\r");

        // Log health check at debug level (not info - too noisy from K8s probes)
        self.log.debug("health_check", .{ .method = method, .path = path });

        // Route to handlers
        if (!std.mem.eql(u8, method, "GET")) {
            self.sendResponse(client_fd, 405, "Method Not Allowed", "text/plain", "Method Not Allowed") catch {};
            return;
        }

        if (std.mem.eql(u8, path, "/health")) {
            try self.handleHealth(client_fd);
        } else if (std.mem.eql(u8, path, "/ready")) {
            try self.handleReady(client_fd);
        } else {
            try self.sendResponse(client_fd, 404, "Not Found", "text/plain", "Not Found");
        }
    }

    /// Handle /health endpoint
    fn handleHealth(self: *HttpServer, client_fd: std.posix.socket_t) !void {
        const body = "{\"status\":\"ok\"}";
        try self.sendResponse(client_fd, 200, "OK", "application/json", body);
    }

    /// Handle /ready endpoint
    fn handleReady(self: *HttpServer, client_fd: std.posix.socket_t) !void {
        const quote_count = self.store.count();

        if (quote_count == 0) {
            // Not ready: no quotes loaded
            const body = "{\"status\":\"not_ready\",\"quotes\":0}";
            try self.sendResponse(client_fd, 503, "Service Unavailable", "application/json", body);
        } else {
            // Ready: quotes available
            var body_buf: [256]u8 = undefined;
            const body = try std.fmt.bufPrint(&body_buf, "{{\"status\":\"ready\",\"quotes\":{d}}}", .{quote_count});
            try self.sendResponse(client_fd, 200, "OK", "application/json", body);
        }
    }

    /// Send HTTP/1.1 response
    fn sendResponse(
        self: *HttpServer,
        client_fd: std.posix.socket_t,
        status_code: u16,
        status_text: []const u8,
        content_type: []const u8,
        body: []const u8,
    ) !void {
        // Build response
        var response_buf: [4096]u8 = undefined;
        const response = try std.fmt.bufPrint(
            &response_buf,
            "HTTP/1.1 {d} {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ status_code, status_text, content_type, body.len, body },
        );

        // Send response
        _ = std.posix.send(client_fd, response, 0) catch |err| {
            switch (err) {
                error.BrokenPipe, error.ConnectionResetByPeer => {
                    // Client disconnected, ignore
                    self.log.debug("http_client_disconnected", .{});
                    return;
                },
                else => {
                    self.log.warn("http_send_error", .{ .err = @errorName(err) });
                    return;
                },
            }
        };
    }
};

// Tests
test "http server initialization" {
    const allocator = std.testing.allocator;

    var store = quote_store.QuoteStore.init(allocator);
    defer store.deinit();

    // Try to bind to a high port (non-privileged)
    var server = HttpServer.init(allocator, "127.0.0.1", 18080, &store) catch |err| {
        // May fail if port is in use, which is okay for testing
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer server.deinit();

    // Server should be initialized
    try std.testing.expectEqual(@as(u16, 18080), std.mem.bigToNative(u16, server.address.port));
}
