const std = @import("std");
const parser = @import("parser.zig");

/// Parse JSON format: array of strings, object with "quotes" array, or array of objects with "quote"/"text" field
pub fn parse(allocator: std.mem.Allocator, content: []const u8) !parser.ParseResult {
    var quotes = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (quotes.items) |quote| allocator.free(quote);
        quotes.deinit();
    }

    // Parse JSON
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch |err| {
        return switch (err) {
            error.UnexpectedEndOfInput, error.SyntaxError => parser.ParserError.MalformedFormat,
            else => err,
        };
    };
    defer parsed.deinit();

    const root = parsed.value;

    // Try different JSON structures
    switch (root) {
        .array => |arr| {
            // Could be array of strings or array of objects
            for (arr.items) |item| {
                switch (item) {
                    .string => |str| {
                        if (try parser.normalizeQuote(allocator, str)) |normalized| {
                            try quotes.append(normalized);
                        }
                    },
                    .object => |obj| {
                        // Try to extract "quote" or "text" field
                        if (obj.get("quote")) |quote_val| {
                            if (quote_val == .string) {
                                if (try parser.normalizeQuote(allocator, quote_val.string)) |normalized| {
                                    try quotes.append(normalized);
                                }
                            }
                        } else if (obj.get("text")) |text_val| {
                            if (text_val == .string) {
                                if (try parser.normalizeQuote(allocator, text_val.string)) |normalized| {
                                    try quotes.append(normalized);
                                }
                            }
                        }
                    },
                    else => {}, // Ignore non-string, non-object items
                }
            }
        },
        .object => |obj| {
            // Look for "quotes" key containing an array
            if (obj.get("quotes")) |quotes_val| {
                if (quotes_val == .array) {
                    for (quotes_val.array.items) |item| {
                        if (item == .string) {
                            if (try parser.normalizeQuote(allocator, item.string)) |normalized| {
                                try quotes.append(normalized);
                            }
                        }
                    }
                }
            }
        },
        else => {
            return parser.ParserError.UnsupportedStructure;
        },
    }

    if (quotes.items.len == 0) {
        return parser.ParserError.EmptyFile;
    }

    return parser.ParseResult{
        .quotes = quotes,
        .format = .json,
    };
}

pub const jsonParser = parser.Parser{
    .parseFn = parse,
};

// Tests
test "json - array of strings" {
    const allocator = std.testing.allocator;
    const content =
        \\["First quote", "Second quote", "Third quote"]
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
    try std.testing.expectEqualStrings("Third quote", result.quotes.items[2]);
}

test "json - object with quotes array" {
    const allocator = std.testing.allocator;
    const content =
        \\{"quotes": ["First quote", "Second quote"]}
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
}

test "json - array of objects with quote field" {
    const allocator = std.testing.allocator;
    const content =
        \\[
        \\  {"quote": "First", "author": "Someone"},
        \\  {"quote": "Second", "author": "Other"}
        \\]
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.quotes.items.len);
    try std.testing.expectEqualStrings("First", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second", result.quotes.items[1]);
}

test "json - array of objects with text field" {
    const allocator = std.testing.allocator;
    const content =
        \\[
        \\  {"text": "First", "author": "Someone"},
        \\  {"text": "Second", "author": "Other"}
        \\]
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.quotes.items.len);
    try std.testing.expectEqualStrings("First", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second", result.quotes.items[1]);
}

test "json - mixed array (strings and objects)" {
    const allocator = std.testing.allocator;
    const content =
        \\["Direct quote", {"quote": "Object quote"}, 123, null]
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.quotes.items.len);
    try std.testing.expectEqualStrings("Direct quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Object quote", result.quotes.items[1]);
}

test "json - malformed JSON" {
    const allocator = std.testing.allocator;
    const content = "[\"quote\", invalid]";

    const result = parse(allocator, content);
    try std.testing.expectError(parser.ParserError.MalformedFormat, result);
}

test "json - empty array" {
    const allocator = std.testing.allocator;
    const content = "[]";

    const result = parse(allocator, content);
    try std.testing.expectError(parser.ParserError.EmptyFile, result);
}

test "json - trim whitespace" {
    const allocator = std.testing.allocator;
    const content =
        \\["  Leading spaces", "Trailing spaces  ", "  Both  "]
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.quotes.items.len);
    try std.testing.expectEqualStrings("Leading spaces", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Trailing spaces", result.quotes.items[1]);
    try std.testing.expectEqualStrings("Both", result.quotes.items[2]);
}
