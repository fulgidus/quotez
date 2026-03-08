const std = @import("std");
const testing = std.testing;

// Hot reload integration tests
// Tests: FileWatcher detects changes, QuoteStore rebuilds, Selector resets

const src = @import("src");

test "initial quote store build" {
    const allocator = testing.allocator;
    const quote_store_mod = src.quote_store_mod;

    var store = quote_store_mod.QuoteStore.init(allocator);
    defer store.deinit();

    // Build store with test fixtures
    const test_dirs = [_][]const u8{"tests/fixtures/quotes"};
    try store.build(&test_dirs);

    // Verify quotes were loaded from fixture files
    try testing.expect(store.count() > 0);
}

test "file watcher detects new file" {
    const allocator = testing.allocator;
    const watcher_mod = src.watcher_mod;

    // Create a temporary directory to watch
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Get absolute path of tmp dir
    var path_buf: [4096]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    // Initialize watcher with interval=1s
    const dirs = [_][]const u8{tmp_path};
    var watcher = try watcher_mod.FileWatcher.init(allocator, &dirs, 1);
    defer watcher.deinit();

    // Force mtime mismatch: set stored mtime to 0 so any real mtime != 0
    watcher.dir_mtimes.items[0] = 0;

    // Create a file in the watched directory (updates dir mtime)
    var file = try tmp.dir.createFile("quotes.txt", .{});
    try file.writeAll("The quick brown fox\nJumps over the lazy dog\n");
    file.close();

    // Force interval_seconds=0 so check() doesn't bail due to elapsed time
    watcher.interval_seconds = 0;

    // check() should return true: mtime changed from 0 to real mtime
    const changed = try watcher.check();
    try testing.expect(changed);
}

test "store rebuilds after file change" {
    const allocator = testing.allocator;
    const quote_store_mod = src.quote_store_mod;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [4096]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    // Write initial quote file
    var file1 = try tmp.dir.createFile("quotes1.txt", .{});
    try file1.writeAll("First quote\nSecond quote\n");
    file1.close();

    // Build store from temp dir
    var store = quote_store_mod.QuoteStore.init(allocator);
    defer store.deinit();

    const dirs = [_][]const u8{tmp_path};
    try store.build(&dirs);

    const initial_count = store.count();
    try testing.expect(initial_count > 0);

    // Add a second quote file with new quotes
    var file2 = try tmp.dir.createFile("quotes2.txt", .{});
    try file2.writeAll("Third quote\nFourth quote\n");
    file2.close();

    // Rebuild store — should pick up new file
    try store.build(&dirs);
    const new_count = store.count();

    // Count must have increased after rebuild
    try testing.expect(new_count > initial_count);
}

test "selector resets after store rebuild" {
    const allocator = testing.allocator;
    const quote_store_mod = src.quote_store_mod;
    const selector_mod = src.selector_mod;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [4096]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &path_buf);

    // Write initial quotes
    var file1 = try tmp.dir.createFile("quotes.txt", .{});
    try file1.writeAll("Alpha quote\nBeta quote\n");
    file1.close();

    var store = quote_store_mod.QuoteStore.init(allocator);
    defer store.deinit();

    const dirs = [_][]const u8{tmp_path};
    try store.build(&dirs);

    // Init selector and advance it
    var sel = try selector_mod.Selector.init(allocator, .sequential, store.count());
    defer sel.deinit();

    _ = sel.next(); // advance position

    // Add more quotes and rebuild store
    var file2 = try tmp.dir.createFile("more.txt", .{});
    try file2.writeAll("Gamma quote\nDelta quote\n");
    file2.close();

    try store.build(&dirs);

    // Reset selector with updated quote count
    try sel.reset(store.count());

    // Verify selector works correctly after reset
    const idx = sel.next();
    try testing.expect(idx != null);
    try testing.expect(idx.? < store.count());
}
