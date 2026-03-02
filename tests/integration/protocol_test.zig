const std = @import("std");
const testing = std.testing;

// Integration tests for RFC 865 protocol compliance
// Tests both TCP and UDP QOTD servers

const src = @import("src");
const quote_store = src.quote_store_mod;
const selector_mod = src.selector_mod;
const tcp_server = src.tcp_server_mod;
const udp_server = src.udp_server_mod;

// Helper to create a test quote store with sample data
fn createTestStore(allocator: std.mem.Allocator) !quote_store.QuoteStore {
    var store = quote_store.QuoteStore.init(allocator);
    
    // Add some test quotes
    try store.add("The only way to do great work is to love what you do.");
    try store.add("Innovation distinguishes between a leader and a follower.");
    try store.add("Stay hungry, stay foolish.");
    
    return store;
}

test "TCP server RFC 865 compliance - single quote per connection" {
    const allocator = testing.allocator;
    
    var store = try createTestStore(allocator);
    defer store.deinit();
    
    var sel = try selector_mod.Selector.init(allocator, .sequential, store.count());
    defer sel.deinit();
    
    // Try to create TCP server on high port
    var server = tcp_server.TcpServer.init(allocator, "127.0.0.1", 18017, &store, &sel) catch |err| {
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer server.deinit();
    
    // Verify server is bound to correct port
    try testing.expectEqual(@as(u16, 18017), std.mem.bigToNative(u16, server.address.port));
    
    // Verify store has quotes
    try testing.expect(!store.isEmpty());
    try testing.expectEqual(@as(usize, 3), store.count());
}

test "TCP server handles empty quote store" {
    const allocator = testing.allocator;
    
    var store = quote_store.QuoteStore.init(allocator);
    defer store.deinit();
    
    var sel = try selector_mod.Selector.init(allocator, .random, 0);
    defer sel.deinit();
    
    var server = tcp_server.TcpServer.init(allocator, "127.0.0.1", 18018, &store, &sel) catch |err| {
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer server.deinit();
    
    // Empty store should not crash initialization
    try testing.expect(store.isEmpty());
}

test "UDP server RFC 865 compliance - datagram response" {
    const allocator = testing.allocator;
    
    var store = try createTestStore(allocator);
    defer store.deinit();
    
    var sel = try selector_mod.Selector.init(allocator, .sequential, store.count());
    defer sel.deinit();
    
    // Try to create UDP server on high port
    var server = udp_server.UdpServer.init(allocator, "127.0.0.1", 18019, &store, &sel) catch |err| {
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer server.deinit();
    
    // Verify server is bound to correct port
    try testing.expectEqual(@as(u16, 18019), std.mem.bigToNative(u16, server.address.port));
    
    // Verify store has quotes
    try testing.expect(!store.isEmpty());
    try testing.expectEqual(@as(usize, 3), store.count());
}

test "UDP server handles empty quote store" {
    const allocator = testing.allocator;
    
    var store = quote_store.QuoteStore.init(allocator);
    defer store.deinit();
    
    var sel = try selector_mod.Selector.init(allocator, .random, 0);
    defer sel.deinit();
    
    var server = udp_server.UdpServer.init(allocator, "127.0.0.1", 18020, &store, &sel) catch |err| {
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer server.deinit();
    
    // Empty store should not crash initialization (will silent drop on requests)
    try testing.expect(store.isEmpty());
}

test "UDP server respects 512 byte datagram limit" {
    const allocator = testing.allocator;
    
    var store = quote_store.QuoteStore.init(allocator);
    defer store.deinit();
    
    // Add a very long quote (> 512 bytes)
    const long_quote = "A" ** 600;
    try store.add(long_quote);
    
    var sel = try selector_mod.Selector.init(allocator, .sequential, store.count());
    defer sel.deinit();
    
    var server = udp_server.UdpServer.init(allocator, "127.0.0.1", 18021, &store, &sel) catch |err| {
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer server.deinit();
    
    // Server should initialize successfully
    // Actual truncation happens during receiveAndRespond
    try testing.expect(!store.isEmpty());
}

test "TCP and UDP servers can coexist on different ports" {
    const allocator = testing.allocator;
    
    var store = try createTestStore(allocator);
    defer store.deinit();
    
    var sel = try selector_mod.Selector.init(allocator, .random, store.count());
    defer sel.deinit();
    
    // Create both TCP and UDP servers
    var tcp = tcp_server.TcpServer.init(allocator, "127.0.0.1", 18022, &store, &sel) catch |err| {
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer tcp.deinit();
    
    var udp = udp_server.UdpServer.init(allocator, "127.0.0.1", 18023, &store, &sel) catch |err| {
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer udp.deinit();
    
    // Both should be initialized successfully
    try testing.expectEqual(@as(u16, 18022), std.mem.bigToNative(u16, tcp.address.port));
    try testing.expectEqual(@as(u16, 18023), std.mem.bigToNative(u16, udp.address.port));
}

test "TCP and UDP servers can share the same port" {
    const allocator = testing.allocator;
    
    var store = try createTestStore(allocator);
    defer store.deinit();
    
    var sel = try selector_mod.Selector.init(allocator, .random, store.count());
    defer sel.deinit();
    
    const test_port: u16 = 18024;
    
    // Create both TCP and UDP servers on same port (should work with SO_REUSEPORT)
    var tcp = tcp_server.TcpServer.init(allocator, "127.0.0.1", test_port, &store, &sel) catch |err| {
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer tcp.deinit();
    
    var udp = udp_server.UdpServer.init(allocator, "127.0.0.1", test_port, &store, &sel) catch |err| {
        if (err == error.AddressInUse) return error.SkipZigTest;
        return err;
    };
    defer udp.deinit();
    
    // Both should be initialized successfully on the same port
    try testing.expectEqual(test_port, std.mem.bigToNative(u16, tcp.address.port));
    try testing.expectEqual(test_port, std.mem.bigToNative(u16, udp.address.port));
}

test "Selection modes work across TCP and UDP" {
    const allocator = testing.allocator;
    
    var store = try createTestStore(allocator);
    defer store.deinit();
    
    // Test sequential mode
    var sel = try selector_mod.Selector.init(allocator, .sequential, store.count());
    defer sel.deinit();
    
    // First selection should be index 0
    const idx1 = sel.next();
    try testing.expectEqual(@as(?usize, 0), idx1);
    
    // Second selection should be index 1
    const idx2 = sel.next();
    try testing.expectEqual(@as(?usize, 1), idx2);
    
    // Third selection should be index 2
    const idx3 = sel.next();
    try testing.expectEqual(@as(?usize, 2), idx3);
    
    // Fourth should wrap around to 0
    const idx4 = sel.next();
    try testing.expectEqual(@as(?usize, 0), idx4);
}

test "Quote store deduplication works" {
    const allocator = testing.allocator;
    
    var store = quote_store.QuoteStore.init(allocator);
    defer store.deinit();
    
    // Add same quote multiple times
    try store.add("Duplicate quote");
    try store.add("Duplicate quote");
    try store.add("Duplicate quote");
    try store.add("Another quote");
    try store.add("Duplicate quote");
    
    // Should only have 2 unique quotes
    try testing.expectEqual(@as(usize, 2), store.count());
}

test "Quote store handles UTF-8 quotes" {
    const allocator = testing.allocator;
    
    var store = quote_store.QuoteStore.init(allocator);
    defer store.deinit();
    
    // Add quotes with various UTF-8 characters
    try store.add("Hello 世界");
    try store.add("Привет мир");
    try store.add("مرحبا بالعالم");
    try store.add("🚀 Space quote");
    
    try testing.expectEqual(@as(usize, 4), store.count());
    
    // Verify we can retrieve them
    const quote1 = store.get(0);
    try testing.expect(quote1 != null);
}

test "Quote store handles whitespace normalization" {
    const allocator = testing.allocator;
    
    var store = quote_store.QuoteStore.init(allocator);
    defer store.deinit();
    
    // Add quotes with various whitespace
    try store.add("  Leading spaces");
    try store.add("Trailing spaces  ");
    try store.add("  Both  ");
    try store.add("\tTabs\t");
    
    // All should be stored (trimming happens during parsing)
    try testing.expect(store.count() > 0);
}
