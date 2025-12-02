const std = @import("std");

/// Parse quotes from JSON file
/// Supports:
/// - Array of strings: ["quote1", "quote2"]
/// - Array of objects: [{"quote": "text", "author": "name"}]
/// If author field exists, it's concatenated as: "quote — author"
pub fn parse(allocator: std.mem.Allocator, content: []const u8, path: []const u8) !std.ArrayList([]const u8) {
    _ = path; // unused but required by interface

    var quotes = std.ArrayList([]const u8){};
    errdefer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    // Parse JSON
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch |err| {
        return err;
    };
    defer parsed.deinit();

    const root = parsed.value;

    // Expect array at root
    if (root != .array) return error.InvalidFormat;

    for (root.array.items) |item| {
        const quote_text = switch (item) {
            .string => |s| try allocator.dupe(u8, s),
            .object => |obj| blk: {
                // Look for "quote" field
                const quote = if (obj.get("quote")) |q| q: {
                    if (q == .string) {
                        break :q q.string;
                    }
                    continue; // Skip if quote is not a string
                } else {
                    continue; // Skip objects without quote field
                };

                // Check for author field
                if (obj.get("author")) |a| {
                    if (a == .string) {
                        // Concatenate: quote — author
                        const formatted = try std.fmt.allocPrint(allocator, "{s} — {s}", .{ quote, a.string });
                        break :blk formatted;
                    }
                }

                // No author, just return quote
                break :blk try allocator.dupe(u8, quote);
            },
            else => continue, // Skip non-string, non-object items
        };

        try quotes.append(allocator, quote_text);
    }

    return quotes;
}

// Unit tests
test "json parser - array of strings" {
    const allocator = std.testing.allocator;
    const content =
        \\["First quote", "Second quote", "Third quote"]
    ;

    var quotes = try parse(allocator, content, "test.json");
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

test "json parser - array of objects with authors" {
    const allocator = std.testing.allocator;
    const content =
        \\[
        \\  {"quote": "Be yourself", "author": "Oscar Wilde"},
        \\  {"quote": "Stay hungry", "author": "Steve Jobs"}
        \\]
    ;

    var quotes = try parse(allocator, content, "test.json");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), quotes.items.len);
    try std.testing.expectEqualStrings("Be yourself — Oscar Wilde", quotes.items[0]);
    try std.testing.expectEqualStrings("Stay hungry — Steve Jobs", quotes.items[1]);
}

test "json parser - objects without author" {
    const allocator = std.testing.allocator;
    const content =
        \\[
        \\  {"quote": "First quote"},
        \\  {"quote": "Second quote", "author": "Someone"}
        \\]
    ;

    var quotes = try parse(allocator, content, "test.json");
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

test "json parser - mixed array" {
    const allocator = std.testing.allocator;
    const content =
        \\[
        \\  "Plain string quote",
        \\  {"quote": "Object quote", "author": "Author"},
        \\  123,
        \\  {"other": "field"},
        \\  "Another string"
        \\]
    ;

    var quotes = try parse(allocator, content, "test.json");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), quotes.items.len);
    try std.testing.expectEqualStrings("Plain string quote", quotes.items[0]);
    try std.testing.expectEqualStrings("Object quote — Author", quotes.items[1]);
    try std.testing.expectEqualStrings("Another string", quotes.items[2]);
}

test "json parser - empty array" {
    const allocator = std.testing.allocator;
    const content = "[]";

    var quotes = try parse(allocator, content, "test.json");
    defer quotes.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), quotes.items.len);
}

test "json parser - invalid format" {
    const allocator = std.testing.allocator;
    const content = "{\"not\": \"an array\"}";

    const result = parse(allocator, content, "test.json");
    try std.testing.expectError(error.InvalidFormat, result);
}

test "json parser - malformed json" {
    const allocator = std.testing.allocator;
    const content = "[\"missing quote";

    const result = parse(allocator, content, "test.json");
    try std.testing.expect(std.meta.isError(result));
}
