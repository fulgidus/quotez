const std = @import("std");
const config = @import("config.zig");

const SelectionMode = config.SelectionMode;

/// Selector state for each mode
const SelectorState = union(SelectionMode) {
    random: RandomState,
    sequential: SequentialState,
    random_no_repeat: RandomNoRepeatState,
    shuffle_cycle: ShuffleCycleState,
};

/// State for random mode (stateless, but needs RNG)
const RandomState = struct {
    rng: std.rand.DefaultPrng,
};

/// State for sequential mode
const SequentialState = struct {
    position: usize,
};

/// State for random-no-repeat mode
const RandomNoRepeatState = struct {
    exhausted: std.AutoHashMap(usize, void),
    rng: std.rand.DefaultPrng,
};

/// State for shuffle-cycle mode
const ShuffleCycleState = struct {
    order: []usize,
    position: usize,
    rng: std.rand.DefaultPrng,
    allocator: std.mem.Allocator,
};

/// Quote selector with pluggable selection algorithms
pub const Selector = struct {
    mode: SelectionMode,
    state: SelectorState,
    allocator: std.mem.Allocator,
    quote_count: usize,

    /// Initialize selector with given mode
    pub fn init(allocator: std.mem.Allocator, mode: SelectionMode, quote_count: usize) !Selector {
        // Seed RNG with timestamp
        const seed = @as(u64, @intCast(std.time.timestamp()));
        
        const state = switch (mode) {
            .random => SelectorState{
                .random = RandomState{
                    .rng = std.rand.DefaultPrng.init(seed),
                },
            },
            .sequential => SelectorState{
                .sequential = SequentialState{ .position = 0 },
            },
            .random_no_repeat => SelectorState{
                .random_no_repeat = RandomNoRepeatState{
                    .exhausted = std.AutoHashMap(usize, void).init(allocator),
                    .rng = std.rand.DefaultPrng.init(seed),
                },
            },
            .shuffle_cycle => blk: {
                var order = try allocator.alloc(usize, quote_count);
                errdefer allocator.free(order);
                
                // Initialize order array [0, 1, 2, ..., n-1]
                for (order, 0..) |*item, i| {
                    item.* = i;
                }
                
                // Shuffle using Fisher-Yates
                var rng = std.rand.DefaultPrng.init(seed);
                var i = quote_count;
                while (i > 1) {
                    i -= 1;
                    const j = rng.random().intRangeLessThan(usize, 0, i + 1);
                    std.mem.swap(usize, &order[i], &order[j]);
                }
                
                break :blk SelectorState{
                    .shuffle_cycle = ShuffleCycleState{
                        .order = order,
                        .position = 0,
                        .rng = rng,
                        .allocator = allocator,
                    },
                };
            },
        };

        return Selector{
            .mode = mode,
            .state = state,
            .allocator = allocator,
            .quote_count = quote_count,
        };
    }

    /// Free selector state
    pub fn deinit(self: *Selector) void {
        switch (self.state) {
            .random_no_repeat => |*state| {
                state.exhausted.deinit();
            },
            .shuffle_cycle => |*state| {
                state.allocator.free(state.order);
            },
            else => {},
        }
    }

    /// Get next quote index
    pub fn next(self: *Selector) ?usize {
        if (self.quote_count == 0) return null;

        return switch (self.state) {
            .random => |*state| self.selectRandom(state, self.quote_count),
            .sequential => |*state| self.selectSequential(state, self.quote_count),
            .random_no_repeat => |*state| self.selectRandomNoRepeat(state, self.quote_count),
            .shuffle_cycle => |*state| self.selectShuffleCycle(state, self.quote_count),
        };
    }

    /// Random selection (may repeat immediately)
    fn selectRandom(self: *Selector, state: *RandomState, quote_count: usize) usize {
        _ = self;
        return state.rng.random().intRangeLessThan(usize, 0, quote_count);
    }

    /// Sequential selection with wraparound
    fn selectSequential(self: *Selector, state: *SequentialState, quote_count: usize) usize {
        _ = self;
        const index = state.position;
        state.position = (state.position + 1) % quote_count;
        return index;
    }

    /// Random without repeats until all exhausted
    fn selectRandomNoRepeat(self: *Selector, state: *RandomNoRepeatState, quote_count: usize) usize {
        _ = self;
        
        // If all quotes exhausted, reset
        if (state.exhausted.count() >= quote_count) {
            state.exhausted.clearRetainingCapacity();
        }

        // Find non-exhausted index
        var attempts: usize = 0;
        const max_attempts = quote_count * 10;
        
        while (attempts < max_attempts) : (attempts += 1) {
            const index = state.rng.random().intRangeLessThan(usize, 0, quote_count);
            if (!state.exhausted.contains(index)) {
                state.exhausted.put(index, {}) catch {
                    // If allocation fails, just return the index anyway
                };
                return index;
            }
        }

        // Fallback: linear search for first non-exhausted
        var i: usize = 0;
        while (i < quote_count) : (i += 1) {
            if (!state.exhausted.contains(i)) {
                state.exhausted.put(i, {}) catch {};
                return i;
            }
        }

        // Should never reach here if logic is correct
        return 0;
    }

    /// Shuffle-cycle selection
    fn selectShuffleCycle(self: *Selector, state: *ShuffleCycleState, quote_count: usize) usize {
        _ = self;
        
        // Get current index from shuffled order
        const index = state.order[state.position];
        state.position += 1;

        // If cycle exhausted, reshuffle
        if (state.position >= quote_count) {
            // Fisher-Yates shuffle
            var i = quote_count;
            while (i > 1) {
                i -= 1;
                const j = state.rng.random().intRangeLessThan(usize, 0, i + 1);
                std.mem.swap(usize, &state.order[i], &state.order[j]);
            }
            state.position = 0;
        }

        return index;
    }

    /// Reset selector state (called after quote store rebuild)
    pub fn reset(self: *Selector, new_quote_count: usize) !void {
        self.quote_count = new_quote_count;
        
        switch (self.state) {
            .random => {
                // Random is stateless, nothing to reset
            },
            .sequential => |*state| {
                state.position = 0;
            },
            .random_no_repeat => |*state| {
                state.exhausted.clearRetainingCapacity();
            },
            .shuffle_cycle => |*state| {
                // Reallocate order array if size changed
                if (state.order.len != new_quote_count) {
                    state.allocator.free(state.order);
                    state.order = try state.allocator.alloc(usize, new_quote_count);
                }

                // Reinitialize and shuffle
                for (state.order, 0..) |*item, i| {
                    item.* = i;
                }

                var i = new_quote_count;
                while (i > 1) {
                    i -= 1;
                    const j = state.rng.random().intRangeLessThan(usize, 0, i + 1);
                    std.mem.swap(usize, &state.order[i], &state.order[j]);
                }

                state.position = 0;
            },
        }
    }
};

// Unit tests
test "sequential mode basic operation" {
    const allocator = std.testing.allocator;
    var selector = try Selector.init(allocator, .sequential, 3);
    defer selector.deinit();

    // Should return 0, 1, 2, 0, 1, 2, ...
    try std.testing.expectEqual(@as(usize, 0), selector.next().?);
    try std.testing.expectEqual(@as(usize, 1), selector.next().?);
    try std.testing.expectEqual(@as(usize, 2), selector.next().?);
    try std.testing.expectEqual(@as(usize, 0), selector.next().?); // Wraparound
    try std.testing.expectEqual(@as(usize, 1), selector.next().?);
}

test "sequential mode with single quote" {
    const allocator = std.testing.allocator;
    var selector = try Selector.init(allocator, .sequential, 1);
    defer selector.deinit();

    try std.testing.expectEqual(@as(usize, 0), selector.next().?);
    try std.testing.expectEqual(@as(usize, 0), selector.next().?);
    try std.testing.expectEqual(@as(usize, 0), selector.next().?);
}

test "random mode returns valid indices" {
    const allocator = std.testing.allocator;
    var selector = try Selector.init(allocator, .random, 10);
    defer selector.deinit();

    // Test 100 selections
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const index = selector.next().?;
        try std.testing.expect(index < 10);
    }
}

test "random-no-repeat exhaustion and reset" {
    const allocator = std.testing.allocator;
    var selector = try Selector.init(allocator, .random_no_repeat, 3);
    defer selector.deinit();

    var seen = std.AutoHashMap(usize, void).init(allocator);
    defer seen.deinit();

    // First cycle: should see all 3 quotes
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const index = selector.next().?;
        try seen.put(index, {});
    }
    try std.testing.expectEqual(@as(usize, 3), seen.count());

    // Next selection should start fresh cycle
    seen.clearRetainingCapacity();
    i = 0;
    while (i < 3) : (i += 1) {
        const index = selector.next().?;
        try seen.put(index, {});
    }
    try std.testing.expectEqual(@as(usize, 3), seen.count());
}

test "shuffle-cycle full cycle uniqueness" {
    const allocator = std.testing.allocator;
    var selector = try Selector.init(allocator, .shuffle_cycle, 5);
    defer selector.deinit();

    var seen = std.AutoHashMap(usize, void).init(allocator);
    defer seen.deinit();

    // One full cycle should contain all quotes exactly once
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const index = selector.next().?;
        try std.testing.expect(!seen.contains(index)); // Should not repeat
        try seen.put(index, {});
    }
    try std.testing.expectEqual(@as(usize, 5), seen.count());
}

test "shuffle-cycle reshuffle on exhaustion" {
    const allocator = std.testing.allocator;
    var selector = try Selector.init(allocator, .shuffle_cycle, 3);
    defer selector.deinit();

    // Complete first cycle
    _ = selector.next();
    _ = selector.next();
    _ = selector.next();

    // Next should start new shuffled cycle
    var seen = std.AutoHashMap(usize, void).init(allocator);
    defer seen.deinit();

    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const index = selector.next().?;
        try seen.put(index, {});
    }
    try std.testing.expectEqual(@as(usize, 3), seen.count());
}

test "selector reset" {
    const allocator = std.testing.allocator;
    var selector = try Selector.init(allocator, .sequential, 5);
    defer selector.deinit();

    // Advance position
    _ = selector.next();
    _ = selector.next();

    // Reset
    try selector.reset(5);

    // Should restart from 0
    try std.testing.expectEqual(@as(usize, 0), selector.next().?);
}

test "empty quote store handling" {
    const allocator = std.testing.allocator;
    var selector = try Selector.init(allocator, .random, 0);
    defer selector.deinit();

    try std.testing.expectEqual(@as(?usize, null), selector.next());
}
