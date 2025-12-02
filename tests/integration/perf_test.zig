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
const SelectionMode = config.SelectionMode;

// ============================================================================
// Performance Tests
// ============================================================================

test "PERF: TCP response time < 10ms" {
    const allocator = std.testing.allocator;
    const port: u16 = 21017;

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    try store.addQuote("Performance test quote for TCP timing verification");

    var sel = try Selector.init(allocator, SelectionMode.random, store.count());
    defer sel.deinit();

    var server = try TcpServer.init(allocator, "127.0.0.1", port, &store, &sel);
    defer server.deinit();
    try server.listen();

    // Measure response time over multiple requests
    const num_requests = 100;
    var total_ns: i128 = 0;
    var max_ns: i128 = 0;

    for (0..num_requests) |_| {
        const start = std.time.nanoTimestamp();

        // Connect, receive, close
        const client_addr = try net.Address.parseIp("127.0.0.1", port);
        const client_socket = try posix.socket(
            client_addr.any.family,
            posix.SOCK.STREAM,
            posix.IPPROTO.TCP,
        );
        defer posix.close(client_socket);

        const timeout = posix.timeval{ .sec = 1, .usec = 0 };
        try posix.setsockopt(client_socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&timeout));

        try posix.connect(client_socket, &client_addr.any, client_addr.getOsSockLen());

        // Server handles
        _ = try server.acceptOne();

        // Receive
        var buf: [4096]u8 = undefined;
        _ = try posix.recv(client_socket, &buf, 0);

        const elapsed = std.time.nanoTimestamp() - start;
        total_ns += elapsed;
        if (elapsed > max_ns) max_ns = elapsed;
    }

    const avg_ms: f64 = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(num_requests)) / 1_000_000.0;
    const max_ms: f64 = @as(f64, @floatFromInt(max_ns)) / 1_000_000.0;

    // Log results
    std.debug.print("\n[PERF] TCP: avg={d:.2}ms max={d:.2}ms over {d} requests\n", .{ avg_ms, max_ms, num_requests });

    // Verify < 10ms average
    try std.testing.expect(avg_ms < 10.0);
}

test "PERF: UDP response time < 10ms" {
    const allocator = std.testing.allocator;
    const port: u16 = 21018;

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    try store.addQuote("Performance test quote for UDP timing verification");

    var sel = try Selector.init(allocator, SelectionMode.random, store.count());
    defer sel.deinit();

    var server = try UdpServer.init(allocator, "127.0.0.1", port, &store, &sel);
    defer server.deinit();
    try server.listen();

    // Create client socket
    const server_addr = try net.Address.parseIp("127.0.0.1", port);
    const client_socket = try posix.socket(
        server_addr.any.family,
        posix.SOCK.DGRAM,
        posix.IPPROTO.UDP,
    );
    defer posix.close(client_socket);

    const timeout = posix.timeval{ .sec = 1, .usec = 0 };
    try posix.setsockopt(client_socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&timeout));

    // Measure response time over multiple requests
    const num_requests = 100;
    var total_ns: i128 = 0;
    var max_ns: i128 = 0;

    for (0..num_requests) |_| {
        const start = std.time.nanoTimestamp();

        // Send request
        _ = try posix.sendto(client_socket, "", 0, &server_addr.any, server_addr.getOsSockLen());

        // Server handles
        _ = try server.handleOne();

        // Receive response
        var buf: [4096]u8 = undefined;
        var src_addr: posix.sockaddr = undefined;
        var src_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);
        _ = try posix.recvfrom(client_socket, &buf, 0, &src_addr, &src_addr_len);

        const elapsed = std.time.nanoTimestamp() - start;
        total_ns += elapsed;
        if (elapsed > max_ns) max_ns = elapsed;
    }

    const avg_ms: f64 = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(num_requests)) / 1_000_000.0;
    const max_ms: f64 = @as(f64, @floatFromInt(max_ns)) / 1_000_000.0;

    // Log results
    std.debug.print("\n[PERF] UDP: avg={d:.2}ms max={d:.2}ms over {d} requests\n", .{ avg_ms, max_ms, num_requests });

    // Verify < 10ms average
    try std.testing.expect(avg_ms < 10.0);
}

test "PERF: 10k quotes load in < 5s" {
    const allocator = std.testing.allocator;

    const start = std.time.nanoTimestamp();

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    // Generate 10,000 unique quotes
    const num_quotes = 10_000;
    for (0..num_quotes) |i| {
        var buf: [128]u8 = undefined;
        const quote = try std.fmt.bufPrint(&buf, "Generated quote number {d} for performance testing - Author", .{i});
        try store.addQuote(quote);
    }

    const elapsed_ns = std.time.nanoTimestamp() - start;
    const elapsed_ms: f64 = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
    const elapsed_s: f64 = elapsed_ms / 1000.0;

    std.debug.print("\n[PERF] Loaded {d} quotes in {d:.2}s ({d:.0}ms)\n", .{ num_quotes, elapsed_s, elapsed_ms });

    // Verify count
    try std.testing.expectEqual(@as(usize, num_quotes), store.count());

    // Verify < 5 seconds
    try std.testing.expect(elapsed_s < 5.0);
}

test "PERF: Quote selection performance with 10k quotes" {
    const allocator = std.testing.allocator;

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    // Load 10k quotes
    for (0..10_000) |i| {
        var buf: [128]u8 = undefined;
        const quote = try std.fmt.bufPrint(&buf, "Performance quote {d}", .{i});
        try store.addQuote(quote);
    }

    // Test selection performance
    var sel = try Selector.init(allocator, SelectionMode.random, store.count());
    defer sel.deinit();

    const num_selections = 10_000;
    const start = std.time.nanoTimestamp();

    for (0..num_selections) |_| {
        const idx = sel.next(store.count());
        const quote = store.get(idx.?);
        _ = quote; // Just access it
    }

    const elapsed_ns = std.time.nanoTimestamp() - start;
    const elapsed_ms: f64 = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
    const per_selection_us: f64 = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(num_selections)) / 1000.0;

    std.debug.print("\n[PERF] {d} selections in {d:.2}ms ({d:.2}μs/selection)\n", .{ num_selections, elapsed_ms, per_selection_us });

    // Should be very fast - sub-millisecond per selection
    try std.testing.expect(per_selection_us < 100.0);
}
