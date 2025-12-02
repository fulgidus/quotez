const std = @import("std");

/// Parse quotes from TOML file
/// Supports:
/// - quotes = ["q1", "q2"]  (array of strings)
/// - [[quotes]] sections with quote and optional author fields
/// If author field exists, format as: "quote — author"
pub fn parse(allocator: std.mem.Allocator, content: []const u8, path: []const u8) !std.ArrayList([]const u8) {
    _ = path; // unused but required by interface

    var quotes = std.ArrayList([]const u8){};
    errdefer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    var pos: usize = 0;
    var in_quotes_table = false;
    var current_quote: ?[]const u8 = null;
    var current_author: ?[]const u8 = null;

    while (pos < content.len) {
        skipWhitespaceAndComments(&pos, content);
        if (pos >= content.len) break;

        // Check for [[quotes]] table header
        if (std.mem.startsWith(u8, content[pos..], "[[quotes]]")) {
            pos += 10; // Skip "[[quotes]]"

            // Save previous quote if any
            if (current_quote) |quote_text| {
                const formatted = if (current_author) |author|
                    try std.fmt.allocPrint(allocator, "{s} — {s}", .{ quote_text, author })
                else
                    try allocator.dupe(u8, quote_text);
                try quotes.append(allocator, formatted);
                current_quote = null;
                current_author = null;
            }

            in_quotes_table = true;
            continue;
        }

        // Check for [quotes] section (for legacy array format)
        if (std.mem.startsWith(u8, content[pos..], "[quotes]")) {
            pos += 8;
            in_quotes_table = false;
            continue;
        }

        // If in quotes table, look for quote = "..." or author = "..."
        if (in_quotes_table) {
            if (std.mem.startsWith(u8, content[pos..], "quote")) {
                pos += 5;
                skipWhitespaceAndComments(&pos, content);

                if (pos < content.len and content[pos] == '=') {
                    pos += 1;
                    skipWhitespaceAndComments(&pos, content);

                    current_quote = try parseString(&pos, content, allocator);
                }
            } else if (std.mem.startsWith(u8, content[pos..], "author")) {
                pos += 6;
                skipWhitespaceAndComments(&pos, content);

                if (pos < content.len and content[pos] == '=') {
                    pos += 1;
                    skipWhitespaceAndComments(&pos, content);

                    current_author = try parseString(&pos, content, allocator);
                }
            }
        } else {
            // Look for quotes = [...] pattern
            if (std.mem.startsWith(u8, content[pos..], "quotes")) {
                pos += 6;
                skipWhitespaceAndComments(&pos, content);

                if (pos < content.len and content[pos] == '=') {
                    pos += 1;
                    skipWhitespaceAndComments(&pos, content);

                    if (pos < content.len and content[pos] == '[') {
                        try parseArray(&quotes, &pos, content, allocator);
                        break; // Found quotes array, done
                    }
                }
            }
        }

        // Skip to next line
        while (pos < content.len and content[pos] != '\n') {
            pos += 1;
        }
        if (pos < content.len) pos += 1; // Skip newline
    }

    // Save any pending quote
    if (current_quote) |quote_text| {
        const formatted = if (current_author) |author|
            try std.fmt.allocPrint(allocator, "{s} — {s}", .{ quote_text, author })
        else
            try allocator.dupe(u8, quote_text);
        try quotes.append(allocator, formatted);
    }

    return quotes;
}

fn skipWhitespaceAndComments(pos: *usize, content: []const u8) void {
    while (pos.* < content.len) {
        const c = content[pos.*];
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
            pos.* += 1;
        } else if (c == '#') {
            // Skip comment until newline
            while (pos.* < content.len and content[pos.*] != '\n') {
                pos.* += 1;
            }
        } else {
            break;
        }
    }
}

fn parseArray(quotes: *std.ArrayList([]const u8), pos: *usize, content: []const u8, allocator: std.mem.Allocator) !void {
    pos.* += 1; // Skip '['

    while (pos.* < content.len) {
        skipWhitespaceAndComments(pos, content);
        if (pos.* >= content.len) return error.UnterminatedArray;

        if (content[pos.*] == ']') {
            pos.* += 1;
            return; // End of array
        }

        if (content[pos.*] == ',') {
            pos.* += 1;
            continue;
        }

        // Parse string
        const quote_text = try parseString(pos, content, allocator);
        try quotes.append(allocator, quote_text);
    }

    return error.UnterminatedArray;
}

fn parseString(pos: *usize, content: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    if (pos.* >= content.len) return error.UnexpectedEof;

    const quote_char = content[pos.*];
    if (quote_char != '"' and quote_char != '\'') return error.ExpectedString;

    pos.* += 1;
    const start = pos.*;

    while (pos.* < content.len and content[pos.*] != quote_char) {
        if (content[pos.*] == '\\') {
            pos.* += 1; // Skip escape char
        }
        pos.* += 1;
    }

    if (pos.* >= content.len) return error.UnterminatedString;

    const value = content[start..pos.*];
    pos.* += 1; // Skip closing quote

    return try allocator.dupe(u8, value);
}

// Unit tests
test "toml parser - quotes array" {
    const allocator = std.testing.allocator;
    const content =
        \\quotes = [
        \\    "First quote",
        \\    "Second quote",
        \\    "Third quote"
        \\]
    ;

    var quotes = try parse(allocator, content, "test.toml");
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

test "toml parser - table array format with authors" {
    const allocator = std.testing.allocator;
    const content =
        \\[[quotes]]
        \\quote = "First quote"
        \\author = "Someone"
        \\
        \\[[quotes]]
        \\quote = "Second quote"
        \\author = "Other"
    ;

    var quotes = try parse(allocator, content, "test.toml");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), quotes.items.len);
    try std.testing.expectEqualStrings("First quote — Someone", quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote — Other", quotes.items[1]);
}

test "toml parser - table array without authors" {
    const allocator = std.testing.allocator;
    const content =
        \\[[quotes]]
        \\quote = "First quote"
        \\
        \\[[quotes]]
        \\quote = "Second quote"
        \\author = "Someone"
    ;

    var quotes = try parse(allocator, content, "test.toml");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), quotes.items.len);
    try std.testing.expectEqualStrings("First quote", quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote — Someone", quotes.items[1]);
}

test "toml parser - single line array" {
    const allocator = std.testing.allocator;
    const content = "quotes = [\"One\", \"Two\", \"Three\"]";

    var quotes = try parse(allocator, content, "test.toml");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), quotes.items.len);
}

test "toml parser - with comments" {
    const allocator = std.testing.allocator;
    const content =
        \\# Comment
        \\quotes = [
        \\    "First",  # inline comment
        \\    "Second"
        \\]
    ;

    var quotes = try parse(allocator, content, "test.toml");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), quotes.items.len);
}

test "toml parser - single quotes" {
    const allocator = std.testing.allocator;
    const content = "quotes = ['First', 'Second']";

    var quotes = try parse(allocator, content, "test.toml");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), quotes.items.len);
    try std.testing.expectEqualStrings("First", quotes.items[0]);
}

test "toml parser - empty array" {
    const allocator = std.testing.allocator;
    const content = "quotes = []";

    var quotes = try parse(allocator, content, "test.toml");
    defer quotes.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), quotes.items.len);
}

test "toml parser - no quotes field" {
    const allocator = std.testing.allocator;
    const content =
        \\[section]
        \\other = "value"
    ;

    var quotes = try parse(allocator, content, "test.toml");
    defer quotes.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), quotes.items.len);
}
