const std = @import("std");
const parser = @import("parser.zig");

/// Parse plaintext format: one quote per line
pub fn parse(allocator: std.mem.Allocator, content: []const u8) !parser.ParseResult {
    var quotes = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (quotes.items) |quote| allocator.free(quote);
        quotes.deinit();
    }

    // Split by newlines
    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |line| {
        // Normalize and trim each line
        if (try parser.normalizeQuote(allocator, line)) |normalized| {
            try quotes.append(normalized);
        }
    }

    return parser.ParseResult{
        .quotes = quotes,
        .format = .plaintext,
    };
}

pub const txtParser = parser.Parser{
    .parseFn = parse,
};

// Tests
test "txt - basic parsing" {
    const allocator = std.testing.allocator;
    const content = "First quote\nSecond quote\nThird quote";
    
    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
    try std.testing.expectEqualStrings("Third quote", result.quotes.items[2]);
}

test "txt - skip empty lines" {
    const allocator = std.testing.allocator;
    const content = "First quote\n\n\nSecond quote\n   \nThird quote";
    
    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
    try std.testing.expectEqualStrings("Third quote", result.quotes.items[2]);
}

test "txt - trim whitespace" {
    const allocator = std.testing.allocator;
    const content = "  Leading spaces\nTrailing spaces  \n  Both  ";
    
    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.quotes.items.len);
    try std.testing.expectEqualStrings("Leading spaces", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Trailing spaces", result.quotes.items[1]);
    try std.testing.expectEqualStrings("Both", result.quotes.items[2]);
}

test "txt - empty file" {
    const allocator = std.testing.allocator;
    const content = "";
    
    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.quotes.items.len);
}

test "txt - only whitespace" {
    const allocator = std.testing.allocator;
    const content = "   \n\n  \n\t\t\n";
    
    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.quotes.items.len);
}
