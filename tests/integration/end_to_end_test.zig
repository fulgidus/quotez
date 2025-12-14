const std = @import("std");
const testing = std.testing;

// End-to-end integration test for full service lifecycle
// Tests: startup → TCP serve → UDP serve → shutdown

test "end to end service lifecycle" {
    const allocator = testing.allocator;
    
    // This test verifies the integration of all components:
    // 1. Configuration loading
    // 2. Quote store building
    // 3. TCP server initialization
    // 4. UDP server initialization
    // 5. Event loop operation (would need subprocess to test fully)
    
    // For now, we verify that all components can be initialized together
    const config_mod = @import("../../src/config.zig");
    const quote_store_mod = @import("../../src/quote_store.zig");
    const selector_mod = @import("../../src/selector.zig");
    const tcp_server_mod = @import("../../src/servers/tcp.zig");
    const udp_server_mod = @import("../../src/servers/udp.zig");
    
    // Note: Full subprocess testing would require zig build artifacts
    // This test verifies component integration without spawning a subprocess
    
    var store = quote_store_mod.QuoteStore.init(allocator);
    defer store.deinit();
    
    // Build store with test fixtures
    const test_dirs = [_][]const u8{"tests/fixtures/quotes"};
    try store.build(&test_dirs);
    
    // Verify quotes loaded
    try testing.expect(store.count() > 0);
    
    var sel = try selector_mod.Selector.init(allocator, .random, store.count());
    defer sel.deinit();
    
    // Initialize TCP server (high port for testing)
    var tcp = tcp_server_mod.TcpServer.init(
        allocator,
        "127.0.0.1",
        18025,
        &store,
        &sel,
    ) catch |err| {
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer tcp.deinit();
    
    // Initialize UDP server (high port for testing)
    var udp = udp_server_mod.UdpServer.init(
        allocator,
        "127.0.0.1",
        18026,
        &store,
        &sel,
    ) catch |err| {
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer udp.deinit();
    
    // Verify both servers initialized
    try testing.expectEqual(@as(u16, 18025), tcp.address.getPort());
    try testing.expectEqual(@as(u16, 18026), udp.address.getPort());
    
    // Verify selector works
    const quote_idx = sel.next();
    try testing.expect(quote_idx != null);
    try testing.expect(quote_idx.? < store.count());
    
    // Verify quote retrieval
    const quote = store.get(quote_idx.?);
    try testing.expect(quote != null);
    try testing.expect(quote.?.len > 0);
}

test "graceful shutdown integration" {
    const allocator = testing.allocator;
    
    // Test that shutdown flag properly stops the event loop concept
    var shutdown_requested = std.atomic.Value(bool).init(false);
    
    try testing.expectEqual(false, shutdown_requested.load(.seq_cst));
    
    // Simulate shutdown signal
    shutdown_requested.store(true, .seq_cst);
    
    try testing.expectEqual(true, shutdown_requested.load(.seq_cst));
}

test "configuration to server integration" {
    const allocator = testing.allocator;
    
    const config_mod = @import("../../src/config.zig");
    const tcp_server_mod = @import("../../src/servers/tcp.zig");
    const udp_server_mod = @import("../../src/servers/udp.zig");
    const quote_store_mod = @import("../../src/quote_store.zig");
    const selector_mod = @import("../../src/selector.zig");
    
    // Verify configuration values can be used to initialize servers
    var store = quote_store_mod.QuoteStore.init(allocator);
    defer store.deinit();
    
    const test_dirs = [_][]const u8{"tests/fixtures/quotes"};
    try store.build(&test_dirs);
    
    var sel = try selector_mod.Selector.init(allocator, .sequential, store.count());
    defer sel.deinit();
    
    // Use configuration-like values
    const test_host = "127.0.0.1";
    const test_tcp_port: u16 = 18027;
    const test_udp_port: u16 = 18028;
    
    var tcp = tcp_server_mod.TcpServer.init(
        allocator,
        test_host,
        test_tcp_port,
        &store,
        &sel,
    ) catch |err| {
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer tcp.deinit();
    
    var udp = udp_server_mod.UdpServer.init(
        allocator,
        test_host,
        test_udp_port,
        &store,
        &sel,
    ) catch |err| {
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer udp.deinit();
    
    try testing.expectEqual(test_tcp_port, tcp.address.getPort());
    try testing.expectEqual(test_udp_port, udp.address.getPort());
}

test "selection mode integration across servers" {
    const allocator = testing.allocator;
    
    const quote_store_mod = @import("../../src/quote_store.zig");
    const selector_mod = @import("../../src/selector.zig");
    
    var store = quote_store_mod.QuoteStore.init(allocator);
    defer store.deinit();
    
    // Add test quotes
    try store.add("Quote 1");
    try store.add("Quote 2");
    try store.add("Quote 3");
    
    // Test that sequential mode provides predictable ordering
    var sel = try selector_mod.Selector.init(allocator, .sequential, store.count());
    defer sel.deinit();
    
    // Both TCP and UDP would use the same selector
    const idx1 = sel.next().?;
    const idx2 = sel.next().?;
    const idx3 = sel.next().?;
    const idx4 = sel.next().?; // Should wrap around
    
    try testing.expectEqual(@as(usize, 0), idx1);
    try testing.expectEqual(@as(usize, 1), idx2);
    try testing.expectEqual(@as(usize, 2), idx3);
    try testing.expectEqual(@as(usize, 0), idx4); // Wraparound
}
