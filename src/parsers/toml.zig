const std = @import("std");
const parser = @import("parser.zig");

/// Simple TOML parser for quote arrays
/// Supports: quotes = ["quote1", "quote2"] and [[quotes]] tables with text/quote field
pub fn parse(allocator: std.mem.Allocator, content: []const u8) !parser.ParseResult {
    var quotes = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (quotes.items) |quote| allocator.free(quote);
        quotes.deinit();
    }

    var in_array = false;
    var in_table = false;
    var lines_it = std.mem.splitScalar(u8, content, '\n');

    while (lines_it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;
        if (trimmed[0] == '#') continue; // Comment

        // Check for [[quotes]] table
        if (std.mem.startsWith(u8, trimmed, "[[quotes]]")) {
            in_table = true;
            continue;
        }

        // Check for quotes = [ array start
        if (std.mem.indexOf(u8, trimmed, "quotes") != null and
            std.mem.indexOf(u8, trimmed, "=") != null and
            std.mem.indexOf(u8, trimmed, "[") != null)
        {
            in_array = true;
            // Try to extract quotes from the same line
            if (try extractQuotesFromLine(allocator, trimmed)) |line_quotes| {
                for (line_quotes.items) |q| {
                    if (try parser.normalizeQuote(allocator, q)) |normalized| {
                        try quotes.append(normalized);
                    }
                    allocator.free(q);
                }
                line_quotes.deinit();
            }

            // Check if array closes on same line
            if (std.mem.indexOf(u8, trimmed, "]") != null) {
                in_array = false;
            }
            continue;
        }

        // Continue array extraction
        if (in_array) {
            if (try extractQuotesFromLine(allocator, trimmed)) |line_quotes| {
                for (line_quotes.items) |q| {
                    if (try parser.normalizeQuote(allocator, q)) |normalized| {
                        try quotes.append(normalized);
                    }
                    allocator.free(q);
                }
                line_quotes.deinit();
            }

            if (std.mem.indexOf(u8, trimmed, "]") != null) {
                in_array = false;
            }
            continue;
        }

        // Extract from table: text = "..." or quote = "..."
        if (in_table) {
            if (std.mem.startsWith(u8, trimmed, "text") or std.mem.startsWith(u8, trimmed, "quote")) {
                if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
                    const value_part = std.mem.trim(u8, trimmed[eq_pos + 1 ..], &std.ascii.whitespace);
                    if (try extractString(allocator, value_part)) |str| {
                        if (try parser.normalizeQuote(allocator, str)) |normalized| {
                            try quotes.append(normalized);
                        }
                        allocator.free(str);
                    }
                }
            }

            // Check for next table or section
            if (trimmed[0] == '[') {
                in_table = false;
            }
        }
    }

    if (quotes.items.len == 0) {
        return parser.ParserError.EmptyFile;
    }

    return parser.ParseResult{
        .quotes = quotes,
        .format = .toml,
    };
}

/// Extract quoted strings from a line
fn extractQuotesFromLine(allocator: std.mem.Allocator, line: []const u8) !?std.ArrayList([]const u8) {
    var results = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (results.items) |item| allocator.free(item);
        results.deinit();
    }

    var i: usize = 0;
    while (i < line.len) {
        if (line[i] == '"') {
            i += 1; // Skip opening quote
            const start = i;

            // Find closing quote
            while (i < line.len and line[i] != '"') : (i += 1) {}

            if (i > start) {
                const str = try allocator.dupe(u8, line[start..i]);
                try results.append(str);
            }

            if (i < line.len) i += 1; // Skip closing quote
        } else {
            i += 1;
        }
    }

    if (results.items.len == 0) {
        results.deinit();
        return null;
    }

    return results;
}

/// Extract a single quoted string
fn extractString(allocator: std.mem.Allocator, value: []const u8) !?[]const u8 {
    if (value.len < 2) return null;
    if (value[0] != '"') return null;

    var i: usize = 1;
    while (i < value.len) : (i += 1) {
        if (value[i] == '"') {
            return try allocator.dupe(u8, value[1..i]);
        }
    }

    return null;
}

pub const tomlParser = parser.Parser{
    .parseFn = parse,
};

// Tests
test "toml - array of strings" {
    const allocator = std.testing.allocator;
    const content =
        \\quotes = ["First quote", "Second quote", "Third quote"]
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
    try std.testing.expectEqualStrings("Third quote", result.quotes.items[2]);
}

test "toml - multi-line array" {
    const allocator = std.testing.allocator;
    const content =
        \\quotes = [
        \\    "First quote",
        \\    "Second quote",
        \\    "Third quote"
        \\]
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
    try std.testing.expectEqualStrings("Third quote", result.quotes.items[2]);
}

test "toml - array of tables with text field" {
    const allocator = std.testing.allocator;
    const content =
        \\[[quotes]]
        \\text = "First quote"
        \\author = "Someone"
        \\
        \\[[quotes]]
        \\text = "Second quote"
        \\author = "Other"
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
}

test "toml - array of tables with quote field" {
    const allocator = std.testing.allocator;
    const content =
        \\[[quotes]]
        \\quote = "First quote"
        \\
        \\[[quotes]]
        \\quote = "Second quote"
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
}

test "toml - with comments" {
    const allocator = std.testing.allocator;
    const content =
        \\# Comment line
        \\quotes = [
        \\    "First quote",  # inline comment
        \\    "Second quote"
        \\]
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
}
