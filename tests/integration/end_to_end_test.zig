const std = @import("std");
const posix = std.posix;
const net = std.net;
const fs = std.fs;

// Import from the main src module
const src = @import("src");

// Access re-exported modules
const config = src.modules.Config;
const quote_store = src.modules.QuoteStoreModule;
const selector = src.modules.SelectorModule;
const tcp_server = src.modules.TcpServerModule;
const udp_server = src.modules.UdpServerModule;

const QuoteStore = quote_store.QuoteStore;
const Selector = selector.Selector;
const TcpServer = tcp_server.TcpServer;
const UdpServer = udp_server.UdpServer;
const SelectionMode = config.SelectionMode;

// ============================================================================
// End-to-End Lifecycle Tests
// ============================================================================

/// Test helper: connect via TCP and receive quote
fn tcpRequest(port: u16) ![]const u8 {
    const client_addr = try net.Address.parseIp("127.0.0.1", port);
    const client_socket = try posix.socket(
        client_addr.any.family,
        posix.SOCK.STREAM,
        posix.IPPROTO.TCP,
    );
    defer posix.close(client_socket);

    // Set timeout
    const timeout = posix.timeval{ .sec = 2, .usec = 0 };
    try posix.setsockopt(client_socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&timeout));

    try posix.connect(client_socket, &client_addr.any, client_addr.getOsSockLen());

    var buf: [4096]u8 = undefined;
    const recv_len = try posix.recv(client_socket, &buf, 0);
    return buf[0..recv_len];
}

/// Test helper: send UDP request and receive quote
fn udpRequest(port: u16, buf: []u8) ![]const u8 {
    const server_addr = try net.Address.parseIp("127.0.0.1", port);
    const client_socket = try posix.socket(
        server_addr.any.family,
        posix.SOCK.DGRAM,
        posix.IPPROTO.UDP,
    );
    defer posix.close(client_socket);

    // Set timeout
    const timeout = posix.timeval{ .sec = 2, .usec = 0 };
    try posix.setsockopt(client_socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&timeout));

    // Send empty datagram
    _ = try posix.sendto(client_socket, "", 0, &server_addr.any, server_addr.getOsSockLen());

    // Receive response
    var src_addr: posix.sockaddr = undefined;
    var src_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);
    const recv_len = try posix.recvfrom(client_socket, buf, 0, &src_addr, &src_addr_len);
    return buf[0..recv_len];
}

test "E2E: Full service lifecycle - startup, serve, reload, shutdown" {
    const allocator = std.testing.allocator;
    const tcp_port: u16 = 20017;
    const udp_port: u16 = 20018;

    // =========================================================================
    // Phase 1: Startup - Initialize quote store from test fixture files
    // =========================================================================

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    // Build from test fixtures directory (sample.txt has 5 quotes)
    const test_dirs = [_][]const u8{"tests/fixtures/quotes"};
    try store.build(&test_dirs);

    const initial_count = store.count();
    try std.testing.expect(initial_count >= 5); // At least 5 quotes from sample.txt

    // Initialize selector
    var sel = try Selector.init(allocator, SelectionMode.sequential, store.count());
    defer sel.deinit();

    // =========================================================================
    // Phase 2: Start servers - TCP and UDP
    // =========================================================================

    var tcp = try TcpServer.init(allocator, "127.0.0.1", tcp_port, &store, &sel);
    defer tcp.deinit();
    try tcp.listen();
    try std.testing.expect(tcp.running);

    var udp = try UdpServer.init(allocator, "127.0.0.1", udp_port, &store, &sel);
    defer udp.deinit();
    try udp.listen();
    try std.testing.expect(udp.running);

    // =========================================================================
    // Phase 3: Serve - Verify TCP and UDP responses
    // =========================================================================

    // Serve TCP request
    {
        const client_addr = try net.Address.parseIp("127.0.0.1", tcp_port);
        const client_socket = try posix.socket(
            client_addr.any.family,
            posix.SOCK.STREAM,
            posix.IPPROTO.TCP,
        );
        defer posix.close(client_socket);

        const timeout = posix.timeval{ .sec = 2, .usec = 0 };
        try posix.setsockopt(client_socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&timeout));

        try posix.connect(client_socket, &client_addr.any, client_addr.getOsSockLen());

        // Server accepts and sends
        _ = try tcp.acceptOne();

        var buf: [4096]u8 = undefined;
        const recv_len = try posix.recv(client_socket, &buf, 0);

        // Verify we received a quote (should be from sample.txt)
        try std.testing.expect(recv_len > 0);
        const response = buf[0..recv_len];
        // Quote text should be non-empty and contain some alphabetic chars
        try std.testing.expect(response.len > 5);
    }

    // Serve UDP request
    {
        const server_addr = try net.Address.parseIp("127.0.0.1", udp_port);
        const client_socket = try posix.socket(
            server_addr.any.family,
            posix.SOCK.DGRAM,
            posix.IPPROTO.UDP,
        );
        defer posix.close(client_socket);

        const timeout = posix.timeval{ .sec = 2, .usec = 0 };
        try posix.setsockopt(client_socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&timeout));

        // Send empty datagram
        _ = try posix.sendto(client_socket, "", 0, &server_addr.any, server_addr.getOsSockLen());

        // Server handles
        _ = try udp.handleOne();

        var buf: [4096]u8 = undefined;
        var src_addr: posix.sockaddr = undefined;
        var src_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);
        const recv_len = try posix.recvfrom(client_socket, &buf, 0, &src_addr, &src_addr_len);

        // Verify we received a quote
        try std.testing.expect(recv_len > 0);
        const response = buf[0..recv_len];
        try std.testing.expect(response.len > 5);
    }

    // =========================================================================
    // Phase 4: Reload - Rebuild quote store (simulates hot reload)
    // =========================================================================

    // Add a quote programmatically to simulate reload
    try store.addQuote("New quote added during reload - Test");
    try std.testing.expectEqual(initial_count + 1, store.count());

    // Reset selector for new count
    try sel.reset(store.count());

    // Verify new quote is accessible via TCP
    {
        // Connect and get all quotes until we find the new one (sequential mode)
        var found_new_quote = false;
        var attempts: usize = 0;
        const max_attempts = store.count() + 2;

        while (attempts < max_attempts and !found_new_quote) {
            const client_addr = try net.Address.parseIp("127.0.0.1", tcp_port);
            const client_socket = try posix.socket(
                client_addr.any.family,
                posix.SOCK.STREAM,
                posix.IPPROTO.TCP,
            );
            defer posix.close(client_socket);

            const timeout = posix.timeval{ .sec = 2, .usec = 0 };
            try posix.setsockopt(client_socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&timeout));

            try posix.connect(client_socket, &client_addr.any, client_addr.getOsSockLen());
            _ = try tcp.acceptOne();

            var buf: [4096]u8 = undefined;
            const recv_len = posix.recv(client_socket, &buf, 0) catch 0;
            if (recv_len > 0) {
                const response = buf[0..recv_len];
                if (std.mem.indexOf(u8, response, "New quote added during reload") != null) {
                    found_new_quote = true;
                }
            }
            attempts += 1;
        }

        try std.testing.expect(found_new_quote);
    }

    // =========================================================================
    // Phase 5: Shutdown - Verify clean stop
    // =========================================================================

    // Servers are deinitialized in defer, verify they can be stopped
    try std.testing.expect(tcp.running);
    try std.testing.expect(udp.running);

    // Explicit stop (tests the stop functionality)
    tcp.stop();
    try std.testing.expect(!tcp.running);

    udp.stop();
    try std.testing.expect(!udp.running);
}

test "E2E: Quote deduplication via build" {
    const allocator = std.testing.allocator;

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    // Build from test fixtures - sample.txt and sample.json share one quote
    // "The best time to plant a tree was 20 years ago. The second best time is now."
    const test_dirs = [_][]const u8{"tests/fixtures/quotes"};
    try store.build(&test_dirs);

    // The metadata should show at least 1 duplicate removed
    try std.testing.expect(store.metadata.duplicates_removed >= 1);

    // Verify unique count is less than total loaded
    try std.testing.expect(store.metadata.unique_quotes < store.metadata.total_quotes_loaded);
}

test "E2E: Multiple selection modes" {
    const allocator = std.testing.allocator;

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    try store.addQuote("Quote One");
    try store.addQuote("Quote Two");
    try store.addQuote("Quote Three");

    // Test sequential mode
    {
        var sel = try Selector.init(allocator, SelectionMode.sequential, store.count());
        defer sel.deinit();

        const idx1 = sel.next(store.count());
        const idx2 = sel.next(store.count());
        const idx3 = sel.next(store.count());
        const idx4 = sel.next(store.count()); // Should wrap

        try std.testing.expectEqual(@as(?usize, 0), idx1);
        try std.testing.expectEqual(@as(?usize, 1), idx2);
        try std.testing.expectEqual(@as(?usize, 2), idx3);
        try std.testing.expectEqual(@as(?usize, 0), idx4); // Wrapped
    }

    // Test random mode
    {
        var sel = try Selector.init(allocator, SelectionMode.random, store.count());
        defer sel.deinit();

        // Just verify indices are in bounds
        var i: usize = 0;
        while (i < 10) : (i += 1) {
            const idx = sel.next(store.count());
            try std.testing.expect(idx != null);
            try std.testing.expect(idx.? < store.count());
        }
    }
}

test "E2E: Quote format variations" {
    const allocator = std.testing.allocator;

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    // Short quote
    try store.addQuote("Short.");

    // Long quote (near 512 char limit)
    const long_quote = "A" ** 400 ++ " - Author";
    try store.addQuote(long_quote);

    // Quote with special characters
    try store.addQuote("Quote with \"quotes\" and 'apostrophes' - Author");

    // Quote with unicode
    try store.addQuote("Unicode: 日本語 émojis 🎉 - Author");

    try std.testing.expectEqual(@as(usize, 4), store.count());

    // Verify quotes can be retrieved
    const q0 = store.get(0);
    try std.testing.expect(q0 != null);
    try std.testing.expect(std.mem.eql(u8, q0.?, "Short."));

    const q3 = store.get(3);
    try std.testing.expect(q3 != null);
    try std.testing.expect(std.mem.indexOf(u8, q3.?, "日本語") != null);
}

test "E2E: Concurrent TCP and UDP serving" {
    const allocator = std.testing.allocator;
    const tcp_port: u16 = 20020;
    const udp_port: u16 = 20021;

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    try store.addQuote("Concurrent test quote - Author");

    var sel = try Selector.init(allocator, SelectionMode.random, store.count());
    defer sel.deinit();

    var tcp = try TcpServer.init(allocator, "127.0.0.1", tcp_port, &store, &sel);
    defer tcp.deinit();
    try tcp.listen();

    var udp = try UdpServer.init(allocator, "127.0.0.1", udp_port, &store, &sel);
    defer udp.deinit();
    try udp.listen();

    // Create TCP client
    const tcp_addr = try net.Address.parseIp("127.0.0.1", tcp_port);
    const tcp_socket = try posix.socket(
        tcp_addr.any.family,
        posix.SOCK.STREAM,
        posix.IPPROTO.TCP,
    );
    defer posix.close(tcp_socket);

    const timeout = posix.timeval{ .sec = 2, .usec = 0 };
    try posix.setsockopt(tcp_socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&timeout));
    try posix.connect(tcp_socket, &tcp_addr.any, tcp_addr.getOsSockLen());

    // Create UDP client
    const udp_addr = try net.Address.parseIp("127.0.0.1", udp_port);
    const udp_socket = try posix.socket(
        udp_addr.any.family,
        posix.SOCK.DGRAM,
        posix.IPPROTO.UDP,
    );
    defer posix.close(udp_socket);
    try posix.setsockopt(udp_socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&timeout));

    // Send UDP request (before TCP is handled)
    _ = try posix.sendto(udp_socket, "", 0, &udp_addr.any, udp_addr.getOsSockLen());

    // Handle TCP
    _ = try tcp.acceptOne();

    // Handle UDP
    _ = try udp.handleOne();

    // Receive both responses
    var tcp_buf: [4096]u8 = undefined;
    const tcp_len = try posix.recv(tcp_socket, &tcp_buf, 0);
    try std.testing.expect(tcp_len > 0);
    try std.testing.expect(std.mem.indexOf(u8, tcp_buf[0..tcp_len], "Concurrent test quote") != null);

    var udp_buf: [4096]u8 = undefined;
    var src_addr: posix.sockaddr = undefined;
    var src_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);
    const udp_len = try posix.recvfrom(udp_socket, &udp_buf, 0, &src_addr, &src_addr_len);
    try std.testing.expect(udp_len > 0);
    try std.testing.expect(std.mem.indexOf(u8, udp_buf[0..udp_len], "Concurrent test quote") != null);
}
