const std = @import("std");
const testing = std.testing;

// Integration tests for selection modes
const selector_mod = @import("../../src/selector.zig");
const config = @import("../../src/config.zig");

test "random mode edge case - large quote count" {
    const allocator = testing.allocator;
    const large_count: usize = 10000;
    
    var selector = try selector_mod.Selector.init(allocator, .random, large_count);
    defer selector.deinit();
    
    // Should always return valid indices
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const index = selector.next().?;
        try testing.expect(index < large_count);
    }
}

test "random mode edge case - single quote repetition" {
    const allocator = testing.allocator;
    
    var selector = try selector_mod.Selector.init(allocator, .random, 1);
    defer selector.deinit();
    
    // With single quote, should always return 0
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try testing.expectEqual(@as(usize, 0), selector.next().?);
    }
}

test "sequential mode edge case - immediate wraparound after init" {
    const allocator = testing.allocator;
    
    var selector = try selector_mod.Selector.init(allocator, .sequential, 2);
    defer selector.deinit();
    
    try testing.expectEqual(@as(usize, 0), selector.next().?);
    try testing.expectEqual(@as(usize, 1), selector.next().?);
    try testing.expectEqual(@as(usize, 0), selector.next().?); // Wraparound
    try testing.expectEqual(@as(usize, 1), selector.next().?);
}

test "sequential mode edge case - reset mid-cycle" {
    const allocator = testing.allocator;
    
    var selector = try selector_mod.Selector.init(allocator, .sequential, 5);
    defer selector.deinit();
    
    // Advance to position 3
    _ = selector.next();
    _ = selector.next();
    _ = selector.next();
    try testing.expectEqual(@as(usize, 3), selector.next().?);
    
    // Reset - should go back to 0
    try selector.reset(5);
    try testing.expectEqual(@as(usize, 0), selector.next().?);
}

test "sequential mode edge case - size change on reset" {
    const allocator = testing.allocator;
    
    var selector = try selector_mod.Selector.init(allocator, .sequential, 5);
    defer selector.deinit();
    
    // Advance
    _ = selector.next();
    _ = selector.next();
    
    // Reset with different size
    try selector.reset(3);
    
    // Should work with new size
    try testing.expectEqual(@as(usize, 0), selector.next().?);
    try testing.expectEqual(@as(usize, 1), selector.next().?);
    try testing.expectEqual(@as(usize, 2), selector.next().?);
    try testing.expectEqual(@as(usize, 0), selector.next().?); // Wraparound at 3
}

test "random-no-repeat mode edge case - exhaustion boundary" {
    const allocator = testing.allocator;
    
    var selector = try selector_mod.Selector.init(allocator, .random_no_repeat, 3);
    defer selector.deinit();
    
    var seen = std.AutoHashMap(usize, void).init(allocator);
    defer seen.deinit();
    
    // First 3 should be unique
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const index = selector.next().?;
        try testing.expect(!seen.contains(index));
        try seen.put(index, {});
    }
    try testing.expectEqual(@as(usize, 3), seen.count());
    
    // 4th should reset and start new cycle
    const fourth = selector.next().?;
    try testing.expect(fourth < 3);
}

test "random-no-repeat mode edge case - single quote behavior" {
    const allocator = testing.allocator;
    
    var selector = try selector_mod.Selector.init(allocator, .random_no_repeat, 1);
    defer selector.deinit();
    
    // With single quote, should always return 0 (exhaustion doesn't prevent this)
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try testing.expectEqual(@as(usize, 0), selector.next().?);
    }
}

test "random-no-repeat mode edge case - reset clears exhaustion" {
    const allocator = testing.allocator;
    
    var selector = try selector_mod.Selector.init(allocator, .random_no_repeat, 3);
    defer selector.deinit();
    
    // Exhaust all quotes
    _ = selector.next();
    _ = selector.next();
    _ = selector.next();
    
    // Reset
    try selector.reset(3);
    
    // Next 3 should all be unique again
    var seen = std.AutoHashMap(usize, void).init(allocator);
    defer seen.deinit();
    
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const index = selector.next().?;
        try seen.put(index, {});
    }
    try testing.expectEqual(@as(usize, 3), seen.count());
}

test "shuffle-cycle mode edge case - cycle boundary" {
    const allocator = testing.allocator;
    
    var selector = try selector_mod.Selector.init(allocator, .shuffle_cycle, 4);
    defer selector.deinit();
    
    var first_cycle = std.AutoHashMap(usize, void).init(allocator);
    defer first_cycle.deinit();
    
    // Complete first cycle
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        const index = selector.next().?;
        try first_cycle.put(index, {});
    }
    try testing.expectEqual(@as(usize, 4), first_cycle.count());
    
    // Next cycle should also contain all 4 (but potentially different order)
    var second_cycle = std.AutoHashMap(usize, void).init(allocator);
    defer second_cycle.deinit();
    
    i = 0;
    while (i < 4) : (i += 1) {
        const index = selector.next().?;
        try second_cycle.put(index, {});
    }
    try testing.expectEqual(@as(usize, 4), second_cycle.count());
}

test "shuffle-cycle mode edge case - single quote behavior" {
    const allocator = testing.allocator;
    
    var selector = try selector_mod.Selector.init(allocator, .shuffle_cycle, 1);
    defer selector.deinit();
    
    // With single quote, should always return 0
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try testing.expectEqual(@as(usize, 0), selector.next().?);
    }
}

test "shuffle-cycle mode edge case - reset mid-cycle" {
    const allocator = testing.allocator;
    
    var selector = try selector_mod.Selector.init(allocator, .shuffle_cycle, 5);
    defer selector.deinit();
    
    // Advance 2 positions
    _ = selector.next();
    _ = selector.next();
    
    // Reset - should reshuffle and start from position 0
    try selector.reset(5);
    
    // Should get a full cycle of 5 unique quotes
    var seen = std.AutoHashMap(usize, void).init(allocator);
    defer seen.deinit();
    
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const index = selector.next().?;
        try testing.expect(!seen.contains(index));
        try seen.put(index, {});
    }
    try testing.expectEqual(@as(usize, 5), seen.count());
}

test "shuffle-cycle mode edge case - size increase on reset" {
    const allocator = testing.allocator;
    
    var selector = try selector_mod.Selector.init(allocator, .shuffle_cycle, 3);
    defer selector.deinit();
    
    // Complete one cycle
    _ = selector.next();
    _ = selector.next();
    _ = selector.next();
    
    // Reset with larger size
    try selector.reset(5);
    
    // Should work with new size - all 5 should be unique
    var seen = std.AutoHashMap(usize, void).init(allocator);
    defer seen.deinit();
    
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const index = selector.next().?;
        try testing.expect(!seen.contains(index));
        try seen.put(index, {});
    }
    try testing.expectEqual(@as(usize, 5), seen.count());
}

test "shuffle-cycle mode edge case - size decrease on reset" {
    const allocator = testing.allocator;
    
    var selector = try selector_mod.Selector.init(allocator, .shuffle_cycle, 10);
    defer selector.deinit();
    
    // Advance a few
    _ = selector.next();
    _ = selector.next();
    
    // Reset with smaller size
    try selector.reset(3);
    
    // Should work with new size
    var seen = std.AutoHashMap(usize, void).init(allocator);
    defer seen.deinit();
    
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const index = selector.next().?;
        try testing.expect(index < 3); // Must be within new bounds
        try seen.put(index, {});
    }
    try testing.expectEqual(@as(usize, 3), seen.count());
}

test "all modes handle empty quote store" {
    const allocator = testing.allocator;
    
    const modes = [_]config.SelectionMode{ .random, .sequential, .random_no_repeat, .shuffle_cycle };
    
    for (modes) |mode| {
        var selector = try selector_mod.Selector.init(allocator, mode, 0);
        defer selector.deinit();
        
        // Empty store should return null
        try testing.expectEqual(@as(?usize, null), selector.next());
    }
}

test "all modes can be reset to zero quotes" {
    const allocator = testing.allocator;
    
    const modes = [_]config.SelectionMode{ .random, .sequential, .random_no_repeat, .shuffle_cycle };
    
    for (modes) |mode| {
        var selector = try selector_mod.Selector.init(allocator, mode, 5);
        defer selector.deinit();
        
        // Advance
        _ = selector.next();
        
        // Reset to zero
        try selector.reset(0);
        
        // Should return null
        try testing.expectEqual(@as(?usize, null), selector.next());
    }
}

test "all modes handle transition from zero to non-zero quotes" {
    const allocator = testing.allocator;
    
    const modes = [_]config.SelectionMode{ .random, .sequential, .random_no_repeat, .shuffle_cycle };
    
    for (modes) |mode| {
        var selector = try selector_mod.Selector.init(allocator, mode, 0);
        defer selector.deinit();
        
        // Initially empty
        try testing.expectEqual(@as(?usize, null), selector.next());
        
        // Reset with quotes
        try selector.reset(3);
        
        // Should now return valid indices
        const index = selector.next().?;
        try testing.expect(index < 3);
    }
}
