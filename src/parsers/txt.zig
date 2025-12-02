const std = @import("std");

/// Parse quotes from plaintext file
/// Format: One quote per line, whitespace trimmed
/// Empty lines are ignored
pub fn parse(allocator: std.mem.Allocator, content: []const u8, path: []const u8) !std.ArrayList([]const u8) {
    _ = path; // unused but required by interface

    var quotes = std.ArrayList([]const u8){};
    errdefer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        // Trim whitespace (including \r for Windows line endings)
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Skip empty lines
        if (trimmed.len == 0) continue;

        // Duplicate the quote for ownership
        const quote = try allocator.dupe(u8, trimmed);
        try quotes.append(allocator, quote);
    }

    return quotes;
}

// Unit tests
test "plaintext parser - basic quotes" {
    const allocator = std.testing.allocator;
    const content = "First quote\nSecond quote\nThird quote";

    var quotes = try parse(allocator, content, "test.txt");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), quotes.items.len);
    try std.testing.expectEqualStrings("First quote", quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", quotes.items[1]);
    try std.testing.expectEqualStrings("Third quote", quotes.items[2]);
}

test "plaintext parser - whitespace trimming" {
    const allocator = std.testing.allocator;
    const content = "  Quote with spaces  \n\tTabbed quote\t\nQuote\r\n";

    var quotes = try parse(allocator, content, "test.txt");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), quotes.items.len);
    try std.testing.expectEqualStrings("Quote with spaces", quotes.items[0]);
    try std.testing.expectEqualStrings("Tabbed quote", quotes.items[1]);
    try std.testing.expectEqualStrings("Quote", quotes.items[2]);
}

test "plaintext parser - empty lines ignored" {
    const allocator = std.testing.allocator;
    const content = "First\n\n\nSecond\n  \n\t\nThird";

    var quotes = try parse(allocator, content, "test.txt");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), quotes.items.len);
    try std.testing.expectEqualStrings("First", quotes.items[0]);
    try std.testing.expectEqualStrings("Second", quotes.items[1]);
    try std.testing.expectEqualStrings("Third", quotes.items[2]);
}

test "plaintext parser - empty file" {
    const allocator = std.testing.allocator;
    const content = "";

    var quotes = try parse(allocator, content, "test.txt");
    defer quotes.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), quotes.items.len);
}

test "plaintext parser - single quote" {
    const allocator = std.testing.allocator;
    const content = "Only one quote";

    var quotes = try parse(allocator, content, "test.txt");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 1), quotes.items.len);
    try std.testing.expectEqualStrings("Only one quote", quotes.items[0]);
}
