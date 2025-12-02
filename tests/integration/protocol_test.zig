const std = @import("std");
const posix = std.posix;
const net = std.net;

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

// ============================================================================
// TCP Integration Tests
// ============================================================================

test "TCP RFC 865 compliance - receive quote and connection closes" {
    const allocator = std.testing.allocator;

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    // Add a test quote directly
    try store.addQuote("Test quote for RFC 865 compliance");

    var sel = try Selector.init(allocator, config.SelectionMode.sequential, store.count());
    defer sel.deinit();

    var server = try TcpServer.init(
        allocator,
        "127.0.0.1",
        18017,
        &store,
        &sel,
    );
    defer server.deinit();

    try server.listen();
    try std.testing.expect(server.running);

    // Connect as client
    const client_addr = try net.Address.parseIp("127.0.0.1", 18017);
    const client_socket = try posix.socket(
        client_addr.any.family,
        posix.SOCK.STREAM,
        posix.IPPROTO.TCP,
    );
    defer posix.close(client_socket);

    try posix.connect(client_socket, &client_addr.any, client_addr.getOsSockLen());

    // Server should accept and send quote
    _ = try server.acceptOne();

    // Client receives data
    var buf: [1024]u8 = undefined;
    const recv_len = try posix.recv(client_socket, &buf, 0);

    try std.testing.expect(recv_len > 0);
    const received = buf[0..recv_len];
    try std.testing.expect(std.mem.indexOf(u8, received, "Test quote for RFC 865 compliance") != null);
}

test "TCP - empty quote store closes immediately" {
    const allocator = std.testing.allocator;

    var store = QuoteStore.init(allocator);
    defer store.deinit();
    // Don't add any quotes - store is empty

    var sel = try Selector.init(allocator, config.SelectionMode.random, 0);
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

    // Connect as client
    const client_addr = try net.Address.parseIp("127.0.0.1", 18018);
    const client_socket = try posix.socket(
        client_addr.any.family,
        posix.SOCK.STREAM,
        posix.IPPROTO.TCP,
    );
    defer posix.close(client_socket);

    try posix.connect(client_socket, &client_addr.any, client_addr.getOsSockLen());

    // Server should accept but send nothing (empty store)
    _ = try server.acceptOne();

    // Client should receive no data (or just close)
    var buf: [1024]u8 = undefined;
    const recv_len = posix.recv(client_socket, &buf, 0) catch 0;
    try std.testing.expectEqual(@as(usize, 0), recv_len);
}

test "TCP - multiple sequential connections get quotes in order" {
    const allocator = std.testing.allocator;

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    try store.addQuote("Quote 1");
    try store.addQuote("Quote 2");
    try store.addQuote("Quote 3");

    var sel = try Selector.init(allocator, config.SelectionMode.sequential, store.count());
    defer sel.deinit();

    var server = try TcpServer.init(
        allocator,
        "127.0.0.1",
        18019,
        &store,
        &sel,
    );
    defer server.deinit();

    try server.listen();

    // Connect multiple times and verify sequential order
    const expected_quotes = [_][]const u8{ "Quote 1", "Quote 2", "Quote 3" };

    for (expected_quotes) |expected| {
        const client_addr = try net.Address.parseIp("127.0.0.1", 18019);
        const client_socket = try posix.socket(
            client_addr.any.family,
            posix.SOCK.STREAM,
            posix.IPPROTO.TCP,
        );
        defer posix.close(client_socket);

        try posix.connect(client_socket, &client_addr.any, client_addr.getOsSockLen());
        _ = try server.acceptOne();

        var buf: [1024]u8 = undefined;
        const recv_len = try posix.recv(client_socket, &buf, 0);
        const received = buf[0..recv_len];

        try std.testing.expect(std.mem.indexOf(u8, received, expected) != null);
    }
}

// ============================================================================
// UDP Integration Tests
// ============================================================================

test "UDP RFC 865 compliance - respond to datagram" {
    const allocator = std.testing.allocator;

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    try store.addQuote("UDP test quote");

    var sel = try Selector.init(allocator, config.SelectionMode.sequential, store.count());
    defer sel.deinit();

    var server = try UdpServer.init(
        allocator,
        "127.0.0.1",
        19017,
        &store,
        &sel,
    );
    defer server.deinit();

    try server.listen();
    try std.testing.expect(server.running);

    // Create UDP client
    const server_addr = try net.Address.parseIp("127.0.0.1", 19017);
    const client_socket = try posix.socket(
        server_addr.any.family,
        posix.SOCK.DGRAM,
        posix.IPPROTO.UDP,
    );
    defer posix.close(client_socket);

    // Send empty datagram (per RFC 865, content is ignored)
    _ = try posix.sendto(client_socket, "", 0, &server_addr.any, server_addr.getOsSockLen());

    // Server handles the datagram
    _ = try server.handleOne();

    // Receive response (with timeout)
    var buf: [1024]u8 = undefined;
    var src_addr: posix.sockaddr = undefined;
    var src_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);

    // Set receive timeout
    const timeout = posix.timeval{ .sec = 1, .usec = 0 };
    try posix.setsockopt(client_socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&timeout));

    const recv_len = try posix.recvfrom(client_socket, &buf, 0, &src_addr, &src_addr_len);

    try std.testing.expect(recv_len > 0);
    const received = buf[0..recv_len];
    try std.testing.expect(std.mem.indexOf(u8, received, "UDP test quote") != null);
}

test "UDP - empty quote store sends no response" {
    const allocator = std.testing.allocator;

    var store = QuoteStore.init(allocator);
    defer store.deinit();
    // Empty store - no quotes

    var sel = try Selector.init(allocator, config.SelectionMode.random, 0);
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

    // Create UDP client
    const server_addr = try net.Address.parseIp("127.0.0.1", 19018);
    const client_socket = try posix.socket(
        server_addr.any.family,
        posix.SOCK.DGRAM,
        posix.IPPROTO.UDP,
    );
    defer posix.close(client_socket);

    // Send datagram
    _ = try posix.sendto(client_socket, "", 0, &server_addr.any, server_addr.getOsSockLen());

    // Server handles (should not send response for empty store)
    _ = try server.handleOne();

    // Set short receive timeout
    const timeout = posix.timeval{ .sec = 0, .usec = 100000 }; // 100ms
    try posix.setsockopt(client_socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&timeout));

    // Should timeout with no response
    var buf: [1024]u8 = undefined;
    var src_addr: posix.sockaddr = undefined;
    var src_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);

    const result = posix.recvfrom(client_socket, &buf, 0, &src_addr, &src_addr_len);

    // Should get WouldBlock (timeout) error since no response was sent
    try std.testing.expectError(error.WouldBlock, result);
}

test "UDP - multiple requests get different quotes in sequential mode" {
    const allocator = std.testing.allocator;

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    try store.addQuote("UDP Quote A");
    try store.addQuote("UDP Quote B");

    var sel = try Selector.init(allocator, config.SelectionMode.sequential, store.count());
    defer sel.deinit();

    var server = try UdpServer.init(
        allocator,
        "127.0.0.1",
        19019,
        &store,
        &sel,
    );
    defer server.deinit();

    try server.listen();

    // Create UDP client
    const server_addr = try net.Address.parseIp("127.0.0.1", 19019);
    const client_socket = try posix.socket(
        server_addr.any.family,
        posix.SOCK.DGRAM,
        posix.IPPROTO.UDP,
    );
    defer posix.close(client_socket);

    // Set receive timeout
    const timeout = posix.timeval{ .sec = 1, .usec = 0 };
    try posix.setsockopt(client_socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&timeout));

    // First request - should get Quote A
    _ = try posix.sendto(client_socket, "", 0, &server_addr.any, server_addr.getOsSockLen());
    _ = try server.handleOne();

    var buf: [1024]u8 = undefined;
    var src_addr: posix.sockaddr = undefined;
    var src_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);

    var recv_len = try posix.recvfrom(client_socket, &buf, 0, &src_addr, &src_addr_len);
    try std.testing.expect(std.mem.indexOf(u8, buf[0..recv_len], "UDP Quote A") != null);

    // Second request - should get Quote B
    _ = try posix.sendto(client_socket, "", 0, &server_addr.any, server_addr.getOsSockLen());
    _ = try server.handleOne();

    recv_len = try posix.recvfrom(client_socket, &buf, 0, &src_addr, &src_addr_len);
    try std.testing.expect(std.mem.indexOf(u8, buf[0..recv_len], "UDP Quote B") != null);
}
