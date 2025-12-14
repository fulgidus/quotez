const std = @import("std");
const parser = @import("parser.zig");

/// Simple YAML parser for quote lists
/// Supports: list of strings, list of objects with quote/text field, and quotes: [...] structure
pub fn parse(allocator: std.mem.Allocator, content: []const u8) !parser.ParseResult {
    var quotes = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (quotes.items) |quote| allocator.free(quote);
        quotes.deinit();
    }

    var in_quotes_array = false;
    var current_obj_indent: ?usize = null;
    var lines_it = std.mem.splitScalar(u8, content, '\n');

    while (lines_it.next()) |line| {
        if (line.len == 0) continue;

        // Calculate indentation
        const indent = countLeadingSpaces(line);
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;
        if (trimmed[0] == '#') continue; // Comment

        // Skip document separator
        if (std.mem.eql(u8, trimmed, "---")) continue;

        // Check for "quotes:" key
        if (std.mem.startsWith(u8, trimmed, "quotes:")) {
            in_quotes_array = true;
            continue;
        }

        // Handle list item: "- quote" or "- key: value"
        if (trimmed[0] == '-' and trimmed.len > 1 and trimmed[1] == ' ') {
            const item_content = std.mem.trim(u8, trimmed[2..], &std.ascii.whitespace);

            // Direct string: "- Some quote"
            if (item_content.len > 0 and item_content[0] != '"' and std.mem.indexOf(u8, item_content, ":") == null) {
                if (try parser.normalizeQuote(allocator, item_content)) |normalized| {
                    try quotes.append(normalized);
                }
                current_obj_indent = null;
                continue;
            }

            // Quoted string: "- "Some quote""
            if (item_content.len > 0 and item_content[0] == '"') {
                if (try extractQuotedString(allocator, item_content)) |str| {
                    if (try parser.normalizeQuote(allocator, str)) |normalized| {
                        try quotes.append(normalized);
                    }
                    allocator.free(str);
                }
                current_obj_indent = null;
                continue;
            }

            // Object start: "- quote: value" or "- text: value"
            if (std.mem.indexOf(u8, item_content, "quote:")) |_| {
                if (try extractYamlValue(allocator, item_content, "quote:")) |str| {
                    if (try parser.normalizeQuote(allocator, str)) |normalized| {
                        try quotes.append(normalized);
                    }
                    allocator.free(str);
                }
                current_obj_indent = indent;
                continue;
            }

            if (std.mem.indexOf(u8, item_content, "text:")) |_| {
                if (try extractYamlValue(allocator, item_content, "text:")) |str| {
                    if (try parser.normalizeQuote(allocator, str)) |normalized| {
                        try quotes.append(normalized);
                    }
                    allocator.free(str);
                }
                current_obj_indent = indent;
                continue;
            }

            // Object start without quote/text on first line
            current_obj_indent = indent;
            continue;
        }

        // Handle nested object fields
        if (current_obj_indent) |obj_indent| {
            if (indent > obj_indent) {
                if (std.mem.startsWith(u8, trimmed, "quote:") or std.mem.startsWith(u8, trimmed, "text:")) {
                    const key = if (std.mem.startsWith(u8, trimmed, "quote:")) "quote:" else "text:";
                    if (try extractYamlValue(allocator, trimmed, key)) |str| {
                        if (try parser.normalizeQuote(allocator, str)) |normalized| {
                            try quotes.append(normalized);
                        }
                        allocator.free(str);
                    }
                }
                continue;
            } else {
                current_obj_indent = null;
            }
        }

        // Handle quotes array items (indented under "quotes:")
        if (in_quotes_array and indent > 0) {
            if (trimmed[0] == '-' and trimmed.len > 1 and trimmed[1] == ' ') {
                const item = std.mem.trim(u8, trimmed[2..], &std.ascii.whitespace);
                if (item.len > 0 and item[0] == '"') {
                    if (try extractQuotedString(allocator, item)) |str| {
                        if (try parser.normalizeQuote(allocator, str)) |normalized| {
                            try quotes.append(normalized);
                        }
                        allocator.free(str);
                    }
                } else {
                    if (try parser.normalizeQuote(allocator, item)) |normalized| {
                        try quotes.append(normalized);
                    }
                }
            }
        }

        // Exit quotes array if we hit a non-indented line
        if (in_quotes_array and indent == 0 and trimmed[0] != '-') {
            in_quotes_array = false;
        }
    }

    if (quotes.items.len == 0) {
        return parser.ParserError.EmptyFile;
    }

    return parser.ParseResult{
        .quotes = quotes,
        .format = .yaml,
    };
}

/// Count leading spaces
fn countLeadingSpaces(line: []const u8) usize {
    var count: usize = 0;
    for (line) |c| {
        if (c == ' ') {
            count += 1;
        } else {
            break;
        }
    }
    return count;
}

/// Extract value after key
fn extractYamlValue(allocator: std.mem.Allocator, line: []const u8, key: []const u8) !?[]const u8 {
    if (std.mem.indexOf(u8, line, key)) |key_pos| {
        const value_start = key_pos + key.len;
        if (value_start >= line.len) return null;

        const value = std.mem.trim(u8, line[value_start..], &std.ascii.whitespace);
        if (value.len == 0) return null;

        // Handle quoted string
        if (value[0] == '"') {
            return extractQuotedString(allocator, value);
        }

        // Unquoted value
        return try allocator.dupe(u8, value);
    }
    return null;
}

/// Extract quoted string
fn extractQuotedString(allocator: std.mem.Allocator, value: []const u8) !?[]const u8 {
    if (value.len < 2 or value[0] != '"') return null;

    var i: usize = 1;
    while (i < value.len) : (i += 1) {
        if (value[i] == '"') {
            return try allocator.dupe(u8, value[1..i]);
        }
    }

    // Unclosed quote - return what we have
    return try allocator.dupe(u8, value[1..]);
}

pub const yamlParser = parser.Parser{
    .parseFn = parse,
};

// Tests
test "yaml - list of strings" {
    const allocator = std.testing.allocator;
    const content =
        \\---
        \\- First quote
        \\- Second quote
        \\- Third quote
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
    try std.testing.expectEqualStrings("Third quote", result.quotes.items[2]);
}

test "yaml - list of quoted strings" {
    const allocator = std.testing.allocator;
    const content =
        \\---
        \\- "First quote"
        \\- "Second quote"
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
}

test "yaml - list of objects with quote field" {
    const allocator = std.testing.allocator;
    const content =
        \\---
        \\- quote: "First quote"
        \\  author: "Someone"
        \\- quote: "Second quote"
        \\  author: "Other"
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
}

test "yaml - list of objects with text field" {
    const allocator = std.testing.allocator;
    const content =
        \\---
        \\- text: First quote
        \\  author: Someone
        \\- text: Second quote
        \\  author: Other
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
}

test "yaml - quotes key with array" {
    const allocator = std.testing.allocator;
    const content =
        \\---
        \\quotes:
        \\  - "First quote"
        \\  - "Second quote"
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
}

test "yaml - with comments" {
    const allocator = std.testing.allocator;
    const content =
        \\---
        \\# Comment line
        \\- First quote
        \\# Another comment
        \\- Second quote
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
}
