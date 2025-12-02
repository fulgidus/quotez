const std = @import("std");
const logger = @import("logger.zig");
const config = @import("config.zig");
const parser = @import("parsers/parser.zig");

/// Quote entity - immutable quote with content-based hash
pub const Quote = struct {
    content: []const u8,
    hash: [32]u8,
    source_path: ?[]const u8,

    /// Create a new quote from content
    pub fn init(allocator: std.mem.Allocator, content: []const u8, source_path: ?[]const u8) !Quote {
        // Normalize content: trim whitespace
        const normalized = std.mem.trim(u8, content, " \t\n\r");

        // Validate: must not be empty
        if (normalized.len == 0) {
            return error.EmptyQuote;
        }

        // Compute Blake3 hash for deduplication
        const Blake3 = std.crypto.hash.Blake3;
        var hash: [32]u8 = undefined;
        Blake3.hash(normalized, &hash, .{});

        // Store normalized content
        const owned_content = try allocator.dupe(u8, normalized);
        errdefer allocator.free(owned_content);

        const owned_path = if (source_path) |path|
            try allocator.dupe(u8, path)
        else
            null;

        return Quote{
            .content = owned_content,
            .hash = hash,
            .source_path = owned_path,
        };
    }

    /// Free quote memory
    pub fn deinit(self: Quote, allocator: std.mem.Allocator) void {
        allocator.free(self.content);
        if (self.source_path) |path| {
            allocator.free(path);
        }
    }
};

/// Metadata about the quote store
pub const StoreMetadata = struct {
    total_files_parsed: usize = 0,
    total_quotes_loaded: usize = 0,
    duplicates_removed: usize = 0,
    unique_quotes: usize = 0,
};

/// In-memory collection of quotes with deduplication
pub const QuoteStore = struct {
    quotes: std.ArrayList(Quote),
    allocator: std.mem.Allocator,
    last_rebuild: i64,
    metadata: StoreMetadata,
    log: logger.Logger,

    /// Initialize an empty quote store
    pub fn init(allocator: std.mem.Allocator) QuoteStore {
        return .{
            .quotes = std.ArrayList(Quote){},
            .allocator = allocator,
            .last_rebuild = std.time.timestamp(),
            .metadata = .{},
            .log = logger.Logger.init(),
        };
    }

    /// Free all quotes and metadata
    pub fn deinit(self: *QuoteStore) void {
        for (self.quotes.items) |quote| {
            quote.deinit(self.allocator);
        }
        self.quotes.deinit(self.allocator);
    }

    /// Build quote store from directories
    pub fn build(self: *QuoteStore, directories: []const []const u8) !void {
        // Clear existing quotes
        for (self.quotes.items) |quote| {
            quote.deinit(self.allocator);
        }
        self.quotes.clearRetainingCapacity();

        // Reset metadata
        self.metadata = .{};

        // Hash map for deduplication
        var seen = std.AutoHashMap([32]u8, void).init(self.allocator);
        defer seen.deinit();

        // Walk all directories
        for (directories) |dir| {
            self.walkDirectory(dir, &seen) catch |err| {
                self.log.warn("directory_scan_failed", .{ .directory = dir, .err = @errorName(err) });
                continue;
            };
        }

        // Update metadata
        self.metadata.unique_quotes = self.quotes.items.len;
        self.last_rebuild = std.time.timestamp();

        // Log results
        if (self.metadata.unique_quotes == 0) {
            self.log.warn("empty_quote_store", .{
                .directories = directories.len,
                .files_parsed = self.metadata.total_files_parsed,
            });
        } else {
            self.log.info("quote_store_built", .{
                .files = self.metadata.total_files_parsed,
                .quotes = self.metadata.total_quotes_loaded,
                .duplicates_removed = self.metadata.duplicates_removed,
                .unique = self.metadata.unique_quotes,
            });
        }
    }

    /// Walk a directory recursively and load quote files
    fn walkDirectory(self: *QuoteStore, dir_path: []const u8, seen: *std.AutoHashMap([32]u8, void)) !void {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
            self.log.warn("directory_open_failed", .{ .path = dir_path, .err = @errorName(err) });
            return err;
        };
        defer dir.close();

        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;

            // Build full path
            const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ dir_path, entry.path });
            defer self.allocator.free(full_path);

            // Try to parse file
            self.parseQuoteFile(full_path, seen) catch |err| {
                self.log.warn("file_parse_failed", .{ .path = full_path, .err = @errorName(err) });
                continue;
            };

            self.metadata.total_files_parsed += 1;
        }
    }

    /// Parse a single quote file using format-specific parsers
    fn parseQuoteFile(self: *QuoteStore, path: []const u8, seen: *std.AutoHashMap([32]u8, void)) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(content);

        // Parse using format-specific parser
        var parsed_quotes = parser.parse(self.allocator, path, content) catch |err| {
            self.log.warn("file_parse_failed", .{ .path = path, .err = @errorName(err) });
            return err;
        };
        defer {
            for (parsed_quotes.items) |quote_text| {
                self.allocator.free(quote_text);
            }
            parsed_quotes.deinit(self.allocator);
        }

        // Process each parsed quote
        for (parsed_quotes.items) |quote_text| {
            // Try to create quote (validates and hashes)
            const quote = Quote.init(self.allocator, quote_text, path) catch |err| {
                if (err != error.EmptyQuote) {
                    self.log.warn("quote_parse_failed", .{ .path = path, .err = @errorName(err) });
                }
                continue;
            };

            self.metadata.total_quotes_loaded += 1;

            // Check for duplicate
            if (seen.contains(quote.hash)) {
                self.metadata.duplicates_removed += 1;
                quote.deinit(self.allocator);
                continue;
            }

            // Add to store
            try seen.put(quote.hash, {});
            try self.quotes.append(self.allocator, quote);
        }
    }

    /// Check if store is empty
    pub fn isEmpty(self: *const QuoteStore) bool {
        return self.quotes.items.len == 0;
    }

    /// Get a quote by index (for selector usage)
    pub fn get(self: *const QuoteStore, index: usize) ?[]const u8 {
        if (index >= self.quotes.items.len) return null;
        return self.quotes.items[index].content;
    }

    /// Get total number of quotes
    pub fn count(self: *const QuoteStore) usize {
        return self.quotes.items.len;
    }
};

// Unit tests
test "quote normalization and hashing" {
    const allocator = std.testing.allocator;

    const q1 = try Quote.init(allocator, "  Hello World  \n", null);
    defer q1.deinit(allocator);

    const q2 = try Quote.init(allocator, "Hello World", null);
    defer q2.deinit(allocator);

    // Content should be normalized
    try std.testing.expectEqualStrings("Hello World", q1.content);
    try std.testing.expectEqualStrings("Hello World", q2.content);

    // Hashes should match
    try std.testing.expectEqualSlices(u8, &q1.hash, &q2.hash);
}

test "empty quote rejected" {
    const allocator = std.testing.allocator;
    const result = Quote.init(allocator, "   \n\t  ", null);
    try std.testing.expectError(error.EmptyQuote, result);
}

test "quote store deduplication" {
    const allocator = std.testing.allocator;

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    var seen = std.AutoHashMap([32]u8, void).init(allocator);
    defer seen.deinit();

    // Add quote 1
    const q1 = try Quote.init(allocator, "Quote A", null);
    try seen.put(q1.hash, {});
    try store.quotes.append(allocator, q1);
    store.metadata.total_quotes_loaded += 1;

    // Try to add duplicate
    const q2 = try Quote.init(allocator, "Quote A", null);
    if (seen.contains(q2.hash)) {
        store.metadata.duplicates_removed += 1;
        q2.deinit(allocator);
    } else {
        try seen.put(q2.hash, {});
        try store.quotes.append(allocator, q2);
        store.metadata.total_quotes_loaded += 1;
    }

    // Add different quote
    const q3 = try Quote.init(allocator, "Quote B", null);
    if (!seen.contains(q3.hash)) {
        try seen.put(q3.hash, {});
        try store.quotes.append(allocator, q3);
        store.metadata.total_quotes_loaded += 1;
    }

    try std.testing.expectEqual(@as(usize, 2), store.quotes.items.len);
    try std.testing.expectEqual(@as(usize, 3), store.metadata.total_quotes_loaded);
    try std.testing.expectEqual(@as(usize, 1), store.metadata.duplicates_removed);
}

test "quote store get and count" {
    const allocator = std.testing.allocator;

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    var seen = std.AutoHashMap([32]u8, void).init(allocator);
    defer seen.deinit();

    const q1 = try Quote.init(allocator, "First", null);
    try seen.put(q1.hash, {});
    try store.quotes.append(allocator, q1);

    const q2 = try Quote.init(allocator, "Second", null);
    try seen.put(q2.hash, {});
    try store.quotes.append(allocator, q2);

    try std.testing.expectEqual(@as(usize, 2), store.count());
    try std.testing.expectEqualStrings("First", store.get(0).?);
    try std.testing.expectEqualStrings("Second", store.get(1).?);
    try std.testing.expectEqual(@as(?[]const u8, null), store.get(2));
}

test "quote store isEmpty" {
    const allocator = std.testing.allocator;

    var store = QuoteStore.init(allocator);
    defer store.deinit();

    try std.testing.expect(store.isEmpty());

    var seen = std.AutoHashMap([32]u8, void).init(allocator);
    defer seen.deinit();

    const q = try Quote.init(allocator, "Test", null);
    try seen.put(q.hash, {});
    try store.quotes.append(allocator, q);

    try std.testing.expect(!store.isEmpty());
}
