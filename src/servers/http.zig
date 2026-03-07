const std = @import("std");
const logger = @import("../logger.zig");
const quote_store = @import("../quote_store.zig");
const posix_net = @import("../compat/posix_net.zig");
const net = @import("../net.zig");

/// HTTP health endpoint server
pub const HttpServer = struct {
    socket: std.posix.socket_t,
    address: std.posix.sockaddr.in,
    store: *quote_store.QuoteStore,
    log: logger.Logger,
    allocator: std.mem.Allocator,
    auth_username: []const u8,
    auth_password: []const u8,

    /// Initialize and bind HTTP server
    pub fn init(
        allocator: std.mem.Allocator,
        host: []const u8,
        port: u16,
        store: *quote_store.QuoteStore,
        auth_username: []const u8,
        auth_password: []const u8,
    ) !HttpServer {
        var log = logger.Logger.init();

        // Parse host string into IPv4 bytes
        const parsed_bytes = net.parseIpv4(host) catch |err| {
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
        const socket = try posix_net.socket(
            std.posix.AF.INET,
            std.posix.SOCK.STREAM,
            std.posix.IPPROTO.TCP,
        );
        errdefer posix_net.close(socket);

        // Set socket options
        try posix_net.setsockopt(
            socket,
            std.posix.SOL.SOCKET,
            std.posix.SO.REUSEADDR,
            std.mem.asBytes(&@as(c_int, 1)),
        );

        // Bind socket
        try posix_net.bind(socket, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.in));

        // Listen
        try posix_net.listen(socket, 128);

        // Set non-blocking mode for event loop
        const flags = try posix_net.fcntl(socket, std.posix.F.GETFL, 0);
        const nonblock_flag = @as(usize, @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true })));
        _ = try posix_net.fcntl(socket, std.posix.F.SETFL, flags | nonblock_flag);

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
            .auth_username = auth_username,
            .auth_password = auth_password,
        };
    }

    /// Stop the HTTP server
    pub fn deinit(self: *HttpServer) void {
        posix_net.close(self.socket);
        self.log.info("http_server_stopped", .{});
    }

    /// Accept and serve a single connection (non-blocking)
    pub fn acceptAndServe(self: *HttpServer) !void {
        var client_addr: std.posix.sockaddr.storage = undefined;
        var client_addr_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.storage);

        // Accept connection
        const client_fd = posix_net.accept(
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
        defer posix_net.close(client_fd);

        // Read HTTP request (up to 64KB)
        var buf: [65536]u8 = undefined;
        const n = posix_net.recv(client_fd, &buf, 0) catch |err| {
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

        // Reject bodies larger than 64KB
        if (HttpServer.parseContentLength(request)) |content_length| {
            if (content_length > 65536) {
                try self.sendErrorResponse(client_fd, 413, "Content Too Large", "Request body too large");
                return;
            }
        }

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

        // Extract body (available for route handlers that need it)
        const body_info = HttpServer.findBody(request);
        const request_body = body_info.body;

        // Log request at debug level (not info - too noisy from K8s probes)
        self.log.debug("http_request", .{ .method = method, .path = path });

        // Route to handlers — method checking is done per handler
        if (std.mem.eql(u8, path, "/health")) {
            try self.handleHealth(client_fd, method);
        } else if (std.mem.eql(u8, path, "/ready")) {
            try self.handleReady(client_fd, method);
        } else if (std.mem.startsWith(u8, path, "/api/")) {
            _ = request_body; // available for future API route handlers
            // Auth required for all /api/ routes
            if (!self.checkAuth(request)) {
                try self.sendUnauthorized(client_fd);
                return;
            }
            // No API routes implemented yet — auth passed, return 404
            try self.sendErrorResponse(client_fd, 404, "Not Found", "Not Found");
        } else {
            _ = request_body; // available for future route handlers
            try self.sendErrorResponse(client_fd, 404, "Not Found", "Not Found");
        }
    }

    /// Handle /health endpoint — GET only
    fn handleHealth(self: *HttpServer, client_fd: std.posix.socket_t, method: []const u8) !void {
        if (!std.mem.eql(u8, method, "GET")) {
            try self.sendErrorResponse(client_fd, 405, "Method Not Allowed", "Method Not Allowed");
            return;
        }
        const body = "{\"status\":\"ok\"}";
        try self.sendResponse(client_fd, 200, "OK", "application/json", body);
    }

    /// Handle /ready endpoint — GET only
    fn handleReady(self: *HttpServer, client_fd: std.posix.socket_t, method: []const u8) !void {
        if (!std.mem.eql(u8, method, "GET")) {
            try self.sendErrorResponse(client_fd, 405, "Method Not Allowed", "Method Not Allowed");
            return;
        }

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

    /// Send a JSON response with the given status and body
    fn sendJsonResponse(
        self: *HttpServer,
        client_fd: std.posix.socket_t,
        status_code: u16,
        status_text: []const u8,
        body: []const u8,
    ) !void {
        try self.sendResponse(client_fd, status_code, status_text, "application/json", body);
    }

    /// Send a JSON error response: {"error":"<msg>","code":<status>}
    fn sendErrorResponse(
        self: *HttpServer,
        client_fd: std.posix.socket_t,
        status_code: u16,
        status_text: []const u8,
        error_message: []const u8,
    ) !void {
        var body_buf: [512]u8 = undefined;
        const body = try std.fmt.bufPrint(
            &body_buf,
            "{{\"error\":\"{s}\",\"code\":{d}}}",
            .{ error_message, status_code },
        );
        try self.sendResponse(client_fd, status_code, status_text, "application/json", body);
    }

    /// Find the body portion of an HTTP request (after \r\n\r\n separator)
    fn findBody(request: []const u8) struct { headers_end: usize, body: []const u8 } {
        if (std.mem.indexOf(u8, request, "\r\n\r\n")) |pos| {
            return .{ .headers_end = pos + 4, .body = request[pos + 4 ..] };
        }
        return .{ .headers_end = request.len, .body = "" };
    }

    /// Parse the Content-Length header value from the headers portion of a request.
    /// Returns null if the header is absent or the value is not a valid integer.
    fn parseContentLength(request: []const u8) ?usize {
        // Only scan the headers section (before \r\n\r\n)
        const headers_end = if (std.mem.indexOf(u8, request, "\r\n\r\n")) |pos| pos else request.len;
        const headers = request[0..headers_end];

        // Try standard title-case form first (most common)
        const needle = "Content-Length: ";
        if (std.mem.indexOf(u8, headers, needle)) |idx| {
            const value_start = idx + needle.len;
            var value_end = value_start;
            while (value_end < headers.len and headers[value_end] != '\r' and headers[value_end] != '\n') {
                value_end += 1;
            }
            return std.fmt.parseInt(usize, headers[value_start..value_end], 10) catch null;
        }

        // Fallback: lowercase form (some clients send this)
        const needle_lower = "content-length: ";
        if (std.mem.indexOf(u8, headers, needle_lower)) |idx| {
            const value_start = idx + needle_lower.len;
            var value_end = value_start;
            while (value_end < headers.len and headers[value_end] != '\r' and headers[value_end] != '\n') {
                value_end += 1;
            }
            return std.fmt.parseInt(usize, headers[value_start..value_end], 10) catch null;
        }

        return null;
    }

    /// Check Basic Auth credentials from raw request bytes.
    /// Returns true if credentials match self.auth_username / self.auth_password.
    fn checkAuth(self: *HttpServer, request: []const u8) bool {
        const auth_prefix = "Authorization: Basic ";
        const auth_pos = std.mem.indexOf(u8, request, auth_prefix) orelse return false;
        const token_start = auth_pos + auth_prefix.len;

        // Find end of token (at \r or \n)
        var token_end = token_start;
        while (token_end < request.len and
            request[token_end] != '\r' and
            request[token_end] != '\n')
        {
            token_end += 1;
        }
        if (token_end == token_start) return false;
        const encoded = request[token_start..token_end];

        // Decode base64
        var decoded_buf: [256]u8 = undefined;
        const dec = std.base64.standard.Decoder;
        const decoded_len = dec.calcSizeForSlice(encoded) catch return false;
        if (decoded_len > decoded_buf.len) return false;
        dec.decode(decoded_buf[0..decoded_len], encoded) catch return false;
        const decoded = decoded_buf[0..decoded_len];

        // Split on ':' to get username:password
        const colon_pos = std.mem.indexOfScalar(u8, decoded, ':') orelse return false;
        const username = decoded[0..colon_pos];
        const password = decoded[colon_pos + 1 ..];

        // Constant-time-ish comparison (both must match)
        return std.mem.eql(u8, username, self.auth_username) and
            std.mem.eql(u8, password, self.auth_password);
    }

    /// Send 401 Unauthorized with WWW-Authenticate challenge
    fn sendUnauthorized(self: *HttpServer, client_fd: std.posix.socket_t) !void {
        self.log.debug("http_auth_failed", .{ .status = 401 });
        const body = "{\"error\":\"Unauthorized\",\"code\":401}";
        var response_buf: [512]u8 = undefined;
        const response = try std.fmt.bufPrint(
            &response_buf,
            "HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\nWWW-Authenticate: Basic realm=\"quotez\"\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ body.len, body },
        );
        _ = posix_net.send(client_fd, response, 0) catch {};
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
        _ = posix_net.send(client_fd, response, 0) catch |err| {
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
    var server = HttpServer.init(allocator, "127.0.0.1", 18080, &store, "admin", "quotez") catch |err| {
        // May fail if port is in use, which is okay for testing
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer server.deinit();

    // Server should be initialized
    try std.testing.expectEqual(@as(u16, 18080), std.mem.bigToNative(u16, server.address.port));
}

test "parseContentLength with valid header" {
    const request = "POST /quotes HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: 42\r\n\r\n{\"text\":\"hello\"}";
    const result = HttpServer.parseContentLength(request);
    try std.testing.expectEqual(@as(?usize, 42), result);
}

test "parseContentLength with missing header" {
    const request = "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n";
    const result = HttpServer.parseContentLength(request);
    try std.testing.expectEqual(@as(?usize, null), result);
}

test "parseContentLength with lowercase header" {
    const request = "POST /quotes HTTP/1.1\r\nHost: localhost\r\ncontent-length: 100\r\n\r\nbody";
    const result = HttpServer.parseContentLength(request);
    try std.testing.expectEqual(@as(?usize, 100), result);
}

test "findBody with body present" {
    const request = "POST /q HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello";
    const result = HttpServer.findBody(request);
    try std.testing.expectEqualStrings("hello", result.body);
    try std.testing.expectEqual(@as(usize, 39), result.headers_end);
}

test "findBody without body" {
    const request = "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n";
    const result = HttpServer.findBody(request);
    try std.testing.expectEqualStrings("", result.body);
}

test "findBody with no CRLF separator" {
    const request = "GET /health HTTP/1.1";
    const result = HttpServer.findBody(request);
    try std.testing.expectEqualStrings("", result.body);
    try std.testing.expectEqual(request.len, result.headers_end);
}

test "sendErrorResponse json format" {
    // Test that the JSON body format string produces valid JSON
    var body_buf: [512]u8 = undefined;
    const body = try std.fmt.bufPrint(
        &body_buf,
        "{{\"error\":\"{s}\",\"code\":{d}}}",
        .{ "Not Found", 404 },
    );
    try std.testing.expectEqualStrings("{\"error\":\"Not Found\",\"code\":404}", body);
}

test "sendErrorResponse json format 413" {
    var body_buf: [512]u8 = undefined;
    const body = try std.fmt.bufPrint(
        &body_buf,
        "{{\"error\":\"{s}\",\"code\":{d}}}",
        .{ "Request body too large", 413 },
    );
    try std.testing.expectEqualStrings("{\"error\":\"Request body too large\",\"code\":413}", body);
}

test "checkAuth with valid credentials" {
    const allocator = std.testing.allocator;
    var store = quote_store.QuoteStore.init(allocator);
    defer store.deinit();

    // Construct server directly without binding a socket (auth doesn't use socket)
    var server = HttpServer{
        .socket = -1,
        .address = std.mem.zeroes(std.posix.sockaddr.in),
        .store = &store,
        .log = logger.Logger.init(),
        .allocator = allocator,
        .auth_username = "admin",
        .auth_password = "quotez",
    };

    // "admin:quotez" base64-encoded is "YWRtaW46cXVvdGV6"
    const request = "GET /api/quotes HTTP/1.1\r\nHost: localhost\r\nAuthorization: Basic YWRtaW46cXVvdGV6\r\n\r\n";
    try std.testing.expect(server.checkAuth(request));
}

test "checkAuth with invalid credentials" {
    const allocator = std.testing.allocator;
    var store = quote_store.QuoteStore.init(allocator);
    defer store.deinit();

    var server = HttpServer{
        .socket = -1,
        .address = std.mem.zeroes(std.posix.sockaddr.in),
        .store = &store,
        .log = logger.Logger.init(),
        .allocator = allocator,
        .auth_username = "admin",
        .auth_password = "quotez",
    };

    // "wrong:wrong" base64-encoded is "d3Jvbmc6d3Jvbmc="
    const request = "GET /api/quotes HTTP/1.1\r\nHost: localhost\r\nAuthorization: Basic d3Jvbmc6d3Jvbmc=\r\n\r\n";
    try std.testing.expect(!server.checkAuth(request));
}

test "checkAuth with missing Authorization header" {
    const allocator = std.testing.allocator;
    var store = quote_store.QuoteStore.init(allocator);
    defer store.deinit();

    var server = HttpServer{
        .socket = -1,
        .address = std.mem.zeroes(std.posix.sockaddr.in),
        .store = &store,
        .log = logger.Logger.init(),
        .allocator = allocator,
        .auth_username = "admin",
        .auth_password = "quotez",
    };

    const request = "GET /api/quotes HTTP/1.1\r\nHost: localhost\r\n\r\n";
    try std.testing.expect(!server.checkAuth(request));
}
