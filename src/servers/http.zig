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
            // Auth required for all /api/ routes
            if (!self.checkAuth(request)) {
                try self.sendUnauthorized(client_fd);
                return;
            }
            // Route to API handlers
            if (std.mem.eql(u8, path, "/api/quotes")) {
                try self.handleQuotes(client_fd, method, request_body);
            } else if (std.mem.startsWith(u8, path, "/api/quotes/")) {
                const id_str = path["/api/quotes/".len..];
                const id = std.fmt.parseInt(usize, id_str, 10) catch {
                    try self.sendErrorResponse(client_fd, 400, "Bad Request", "Invalid quote ID");
                    return;
                };
                try self.handleQuoteById(client_fd, method, id, request_body);
            } else {
                try self.sendErrorResponse(client_fd, 404, "Not Found", "Not Found");
            }
        } else {
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

    /// Handle /api/quotes endpoint — GET list, POST create
    fn handleQuotes(self: *HttpServer, client_fd: std.posix.socket_t, method: []const u8, body: []const u8) !void {
        if (std.mem.eql(u8, method, "GET")) {
            var json_buf: std.ArrayList(u8) = .{};
            defer json_buf.deinit(self.allocator);

            try json_buf.appendSlice(self.allocator, "{\"quotes\":[");
            const count = self.store.count();
            var i: usize = 0;
            while (i < count) : (i += 1) {
                if (i > 0) try json_buf.append(self.allocator, ',');
                const text = self.store.get(i) orelse continue;

                try json_buf.appendSlice(self.allocator, "{\"id\":");
                var id_buf: [32]u8 = undefined;
                const id_str = try std.fmt.bufPrint(&id_buf, "{d}", .{i});
                try json_buf.appendSlice(self.allocator, id_str);
                try json_buf.appendSlice(self.allocator, ",\"text\":\"");
                try appendJsonEscaped(&json_buf, self.allocator, text);
                try json_buf.appendSlice(self.allocator, "\"}");
            }
            var count_buf: [32]u8 = undefined;
            const count_str = try std.fmt.bufPrint(&count_buf, "],\"count\":{d}}}", .{count});
            try json_buf.appendSlice(self.allocator, count_str);

            try self.sendJsonResponse(client_fd, 200, "OK", json_buf.items);
        } else if (std.mem.eql(u8, method, "POST")) {
            const text = extractTextField(body) catch {
                try self.sendErrorResponse(client_fd, 400, "Bad Request", "Invalid JSON body");
                return;
            };
            if (text.len == 0) {
                try self.sendErrorResponse(client_fd, 400, "Bad Request", "Quote text cannot be empty");
                return;
            }

            const count = self.store.count();
            var i: usize = 0;
            while (i < count) : (i += 1) {
                if (std.mem.eql(u8, self.store.get(i) orelse "", text)) {
                    try self.sendErrorResponse(client_fd, 409, "Conflict", "Duplicate quote");
                    return;
                }
            }

            self.store.add(text) catch {
                try self.sendErrorResponse(client_fd, 500, "Internal Server Error", "Failed to add quote");
                return;
            };

            const new_id = self.store.count() - 1;
            var json_buf: std.ArrayList(u8) = .{};
            defer json_buf.deinit(self.allocator);
            var id_buf: [32]u8 = undefined;
            const id_prefix = try std.fmt.bufPrint(&id_buf, "{{\"id\":{d},\"text\":\"", .{new_id});
            try json_buf.appendSlice(self.allocator, id_prefix);
            try appendJsonEscaped(&json_buf, self.allocator, text);
            try json_buf.appendSlice(self.allocator, "\"}");
            try self.sendJsonResponse(client_fd, 201, "Created", json_buf.items);
        } else {
            try self.sendErrorResponse(client_fd, 405, "Method Not Allowed", "Method Not Allowed");
        }
    }

    /// Handle /api/quotes/:id endpoint — GET by id, PUT update, DELETE remove
    fn handleQuoteById(self: *HttpServer, client_fd: std.posix.socket_t, method: []const u8, id: usize, body: []const u8) !void {
        if (std.mem.eql(u8, method, "GET")) {
            const text = self.store.get(id) orelse {
                try self.sendErrorResponse(client_fd, 404, "Not Found", "Quote not found");
                return;
            };

            var json_buf: std.ArrayList(u8) = .{};
            defer json_buf.deinit(self.allocator);
            var id_buf: [32]u8 = undefined;
            const id_prefix = try std.fmt.bufPrint(&id_buf, "{{\"id\":{d},\"text\":\"", .{id});
            try json_buf.appendSlice(self.allocator, id_prefix);
            try appendJsonEscaped(&json_buf, self.allocator, text);
            try json_buf.appendSlice(self.allocator, "\"}");
            try self.sendJsonResponse(client_fd, 200, "OK", json_buf.items);
        } else if (std.mem.eql(u8, method, "PUT")) {
            if (self.store.get(id) == null) {
                try self.sendErrorResponse(client_fd, 404, "Not Found", "Quote not found");
                return;
            }

            const text = extractTextField(body) catch {
                try self.sendErrorResponse(client_fd, 400, "Bad Request", "Invalid JSON body");
                return;
            };
            if (text.len == 0) {
                try self.sendErrorResponse(client_fd, 400, "Bad Request", "Quote text cannot be empty");
                return;
            }

            self.store.removeQuote(id) catch {
                try self.sendErrorResponse(client_fd, 500, "Internal Server Error", "Failed to update quote");
                return;
            };
            self.store.add(text) catch {
                try self.sendErrorResponse(client_fd, 500, "Internal Server Error", "Failed to add updated quote");
                return;
            };

            const new_id = self.store.count() - 1;
            var json_buf: std.ArrayList(u8) = .{};
            defer json_buf.deinit(self.allocator);
            var id_buf: [32]u8 = undefined;
            const id_prefix = try std.fmt.bufPrint(&id_buf, "{{\"id\":{d},\"text\":\"", .{new_id});
            try json_buf.appendSlice(self.allocator, id_prefix);
            try appendJsonEscaped(&json_buf, self.allocator, text);
            try json_buf.appendSlice(self.allocator, "\"}");
            try self.sendJsonResponse(client_fd, 200, "OK", json_buf.items);
        } else if (std.mem.eql(u8, method, "DELETE")) {
            if (self.store.get(id) == null) {
                try self.sendErrorResponse(client_fd, 404, "Not Found", "Quote not found");
                return;
            }

            self.store.removeQuote(id) catch {
                try self.sendErrorResponse(client_fd, 500, "Internal Server Error", "Failed to delete quote");
                return;
            };
            try self.sendJsonResponse(client_fd, 200, "OK", "{\"status\":\"ok\"}");
        } else {
            try self.sendErrorResponse(client_fd, 405, "Method Not Allowed", "Method Not Allowed");
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

/// Extract "text" field from JSON body like {"text":"..."}
/// Returns the text value (not allocated — points into body slice)
fn extractTextField(body: []const u8) ![]const u8 {
    const key = "\"text\":\"";
    const start_pos = std.mem.indexOf(u8, body, key) orelse return error.MissingTextField;
    const value_start = start_pos + key.len;

    var i = value_start;
    while (i < body.len) {
        if (body[i] == '\\') {
            i += 2;
            continue;
        }
        if (body[i] == '"') break;
        i += 1;
    }
    if (i >= body.len) return error.MalformedJson;

    const text = body[value_start..i];
    return std.mem.trim(u8, text, " \t\n\r");
}

/// Append a string to an ArrayList with JSON escaping
fn appendJsonEscaped(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            else => try buf.append(allocator, c),
        }
    }
}

fn testSendHttpRequestOnce(server: *HttpServer, port: u16, request: []const u8, response_buf: []u8) ![]const u8 {
    const client_fd = try posix_net.socket(
        std.posix.AF.INET,
        std.posix.SOCK.STREAM,
        std.posix.IPPROTO.TCP,
    );
    defer posix_net.close(client_fd);

    const parsed_bytes = try net.parseIpv4("127.0.0.1");
    const addr = std.posix.sockaddr.in{
        .family = std.posix.AF.INET,
        .port = std.mem.nativeToBig(u16, port),
        .addr = parsed_bytes,
    };

    try posix_net.connect(client_fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.in));
    _ = try posix_net.send(client_fd, request, 0);
    try server.acceptAndServe();
    const n = try posix_net.recv(client_fd, response_buf, 0);
    return response_buf[0..n];
}

fn testResponseBody(response: []const u8) []const u8 {
    const sep = std.mem.indexOf(u8, response, "\r\n\r\n") orelse return "";
    return response[sep + 4 ..];
}

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

test "extractTextField parses valid body" {
    const body = "{\"text\":\"Hello world\"}";
    const text = try extractTextField(body);
    try std.testing.expectEqualStrings("Hello world", text);
}

test "extractTextField handles escaped quotes" {
    const body = "{\"text\":\"Hello \\\"quoted\\\" world\"}";
    const text = try extractTextField(body);
    try std.testing.expectEqualStrings("Hello \\\"quoted\\\" world", text);
}

test "extractTextField rejects malformed bodies" {
    try std.testing.expectError(error.MissingTextField, extractTextField("{\"message\":\"x\"}"));
    try std.testing.expectError(error.MalformedJson, extractTextField("{\"text\":\"unterminated}"));
}

test "appendJsonEscaped escapes special characters" {
    const allocator = std.testing.allocator;
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);

    try appendJsonEscaped(&buf, allocator, "a\"b\\c\nd\re\tf");
    try std.testing.expectEqualStrings("a\\\"b\\\\c\\nd\\re\\tf", buf.items);
}

test "api quotes CRUD endpoint behavior" {
    const allocator = std.testing.allocator;
    const auth_header = "Authorization: Basic YWRtaW46cXVvdGV6\r\n";

    var store = quote_store.QuoteStore.init(allocator);
    defer store.deinit();
    try store.add("Initial quote");

    var server = HttpServer.init(allocator, "127.0.0.1", 18081, &store, "admin", "quotez") catch |err| {
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer server.deinit();

    var response_storage: [8192]u8 = undefined;

    // Unauthorized request
    const no_auth_req =
        "GET /api/quotes HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        "\r\n";
    const no_auth_resp = try testSendHttpRequestOnce(&server, 18081, no_auth_req, &response_storage);
    try std.testing.expect(std.mem.indexOf(u8, no_auth_resp, "401 Unauthorized") != null);

    // GET /api/quotes
    const get_all_req =
        "GET /api/quotes HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        auth_header ++
        "\r\n";
    const get_all_resp = try testSendHttpRequestOnce(&server, 18081, get_all_req, &response_storage);
    try std.testing.expect(std.mem.indexOf(u8, get_all_resp, "200 OK") != null);
    const get_all_body = testResponseBody(get_all_resp);
    try std.testing.expect(std.mem.indexOf(u8, get_all_body, "\"count\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_all_body, "\"id\":0") != null);

    // POST empty text -> 400
    const post_empty_req =
        "POST /api/quotes HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        auth_header ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 14\r\n" ++
        "\r\n" ++
        "{\"text\":\"\"}";
    const post_empty_resp = try testSendHttpRequestOnce(&server, 18081, post_empty_req, &response_storage);
    try std.testing.expect(std.mem.indexOf(u8, post_empty_resp, "400 Bad Request") != null);

    // POST duplicate -> 409
    const post_dup_req =
        "POST /api/quotes HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        auth_header ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 24\r\n" ++
        "\r\n" ++
        "{\"text\":\"Initial quote\"}";
    const post_dup_resp = try testSendHttpRequestOnce(&server, 18081, post_dup_req, &response_storage);
    try std.testing.expect(std.mem.indexOf(u8, post_dup_resp, "409 Conflict") != null);

    // POST create -> 201
    const post_create_req =
        "POST /api/quotes HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        auth_header ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 26\r\n" ++
        "\r\n" ++
        "{\"text\":\"Created via API\"}";
    const post_create_resp = try testSendHttpRequestOnce(&server, 18081, post_create_req, &response_storage);
    try std.testing.expect(std.mem.indexOf(u8, post_create_resp, "201 Created") != null);
    try std.testing.expect(std.mem.indexOf(u8, testResponseBody(post_create_resp), "\"id\":1") != null);

    // GET /api/quotes/1 -> 200
    const get_one_req =
        "GET /api/quotes/1 HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        auth_header ++
        "\r\n";
    const get_one_resp = try testSendHttpRequestOnce(&server, 18081, get_one_req, &response_storage);
    try std.testing.expect(std.mem.indexOf(u8, get_one_resp, "200 OK") != null);
    try std.testing.expect(std.mem.indexOf(u8, testResponseBody(get_one_resp), "Created via API") != null);

    // PUT /api/quotes/1 -> 200
    const put_req =
        "PUT /api/quotes/1 HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        auth_header ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 23\r\n" ++
        "\r\n" ++
        "{\"text\":\"Updated quote\"}";
    const put_resp = try testSendHttpRequestOnce(&server, 18081, put_req, &response_storage);
    try std.testing.expect(std.mem.indexOf(u8, put_resp, "200 OK") != null);
    try std.testing.expect(std.mem.indexOf(u8, testResponseBody(put_resp), "Updated quote") != null);

    // DELETE /api/quotes/1 -> 200
    const delete_req =
        "DELETE /api/quotes/1 HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        auth_header ++
        "\r\n";
    const delete_resp = try testSendHttpRequestOnce(&server, 18081, delete_req, &response_storage);
    try std.testing.expect(std.mem.indexOf(u8, delete_resp, "200 OK") != null);
    try std.testing.expect(std.mem.indexOf(u8, testResponseBody(delete_resp), "\"status\":\"ok\"") != null);

    // GET deleted id -> 404
    const get_deleted_req =
        "GET /api/quotes/1 HTTP/1.1\r\n" ++
        "Host: localhost\r\n" ++
        auth_header ++
        "\r\n";
    const get_deleted_resp = try testSendHttpRequestOnce(&server, 18081, get_deleted_req, &response_storage);
    try std.testing.expect(std.mem.indexOf(u8, get_deleted_resp, "404 Not Found") != null);
}
