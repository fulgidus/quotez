const std = @import("std");

/// Parse quotes from YAML file
/// Supports minimal YAML subset:
/// - List of strings: - "quote1"
/// - List of objects: - quote: "text" (with optional author field)
/// - Document separator: ---
/// - Quoted and unquoted strings
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

    var lines = std.mem.splitScalar(u8, content, '\n');
    var current_quote: ?[]const u8 = null;
    var current_author: ?[]const u8 = null;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Skip empty lines and document separators
        if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "---")) {
            continue;
        }

        // Look for list items: - "quote" or - quote: "text"
        if (std.mem.startsWith(u8, trimmed, "- ")) {
            // If we have a pending quote from object format, save it
            if (current_quote) |quote_text| {
                const final_text = if (current_author) |author_text|
                    try std.fmt.allocPrint(allocator, "{s} — {s}", .{ quote_text, author_text })
                else
                    try allocator.dupe(u8, quote_text);

                try quotes.append(allocator, final_text);

                // Free temporary strings
                allocator.free(quote_text);
                if (current_author) |author_text| {
                    allocator.free(author_text);
                }
                current_quote = null;
                current_author = null;
            }

            const item_part = std.mem.trim(u8, trimmed[2..], " \t");

            // Check if it's an object (contains "quote:")
            if (std.mem.startsWith(u8, item_part, "quote:")) {
                const quote_value = std.mem.trim(u8, item_part[6..], " \t");
                current_quote = try extractYamlString(quote_value, allocator);
            } else {
                // It's a simple string
                const quote_text = try extractYamlString(item_part, allocator);
                if (quote_text.len > 0) {
                    try quotes.append(allocator, quote_text);
                }
            }
        } else if (std.mem.startsWith(u8, trimmed, "quote:")) {
            // Quote field within an object (no dash)
            const quote_value = std.mem.trim(u8, trimmed[6..], " \t");
            current_quote = try extractYamlString(quote_value, allocator);
        } else if (std.mem.startsWith(u8, trimmed, "author:")) {
            // Author field - extract and store it
            const author_value = std.mem.trim(u8, trimmed[7..], " \t");
            const author_text = try extractYamlString(author_value, allocator);
            if (author_text.len > 0) {
                current_author = author_text;
            }
        }
    }

    // Save any pending quote
    if (current_quote) |quote_text| {
        const final_text = if (current_author) |author_text|
            try std.fmt.allocPrint(allocator, "{s} — {s}", .{ quote_text, author_text })
        else
            try allocator.dupe(u8, quote_text);

        try quotes.append(allocator, final_text);

        // Free temporary strings
        allocator.free(quote_text);
        if (current_author) |author_text| {
            allocator.free(author_text);
        }
    }

    return quotes;
}

fn extractYamlString(s: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var text = s;

    // Remove surrounding quotes if present
    if (text.len >= 2) {
        if ((text[0] == '"' and text[text.len - 1] == '"') or
            (text[0] == '\'' and text[text.len - 1] == '\''))
        {
            text = text[1 .. text.len - 1];
        }
    }

    return try allocator.dupe(u8, text);
}

// Unit tests
test "yaml parser - quoted strings" {
    const allocator = std.testing.allocator;
    const content =
        \\---
        \\- "First quote"
        \\- "Second quote"
        \\- "Third quote"
    ;

    var quotes = try parse(allocator, content, "test.yaml");
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

test "yaml parser - object format with authors" {
    const allocator = std.testing.allocator;
    const content =
        \\---
        \\- quote: "First quote"
        \\  author: "Someone"
        \\- quote: "Second quote"
        \\  author: "Other"
    ;

    var quotes = try parse(allocator, content, "test.yaml");
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

test "yaml parser - object format without authors" {
    const allocator = std.testing.allocator;
    const content =
        \\---
        \\- quote: "First quote"
        \\- quote: "Second quote"
        \\  author: "Has Author"
    ;

    var quotes = try parse(allocator, content, "test.yaml");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), quotes.items.len);
    try std.testing.expectEqualStrings("First quote", quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote — Has Author", quotes.items[1]);
}

test "yaml parser - unquoted strings" {
    const allocator = std.testing.allocator;
    const content =
        \\- First quote
        \\- Second quote
        \\- Third quote
    ;

    var quotes = try parse(allocator, content, "test.yaml");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), quotes.items.len);
    try std.testing.expectEqualStrings("First quote", quotes.items[0]);
}

test "yaml parser - single quotes" {
    const allocator = std.testing.allocator;
    const content =
        \\- 'First quote'
        \\- 'Second quote'
    ;

    var quotes = try parse(allocator, content, "test.yaml");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), quotes.items.len);
    try std.testing.expectEqualStrings("First quote", quotes.items[0]);
}

test "yaml parser - mixed formats" {
    const allocator = std.testing.allocator;
    const content =
        \\---
        \\- "Quoted"
        \\- Unquoted
        \\- quote: "Object format"
        \\  author: "Author"
    ;

    var quotes = try parse(allocator, content, "test.yaml");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), quotes.items.len);
    try std.testing.expectEqualStrings("Quoted", quotes.items[0]);
    try std.testing.expectEqualStrings("Unquoted", quotes.items[1]);
    try std.testing.expectEqualStrings("Object format — Author", quotes.items[2]);
}

test "yaml parser - empty lines ignored" {
    const allocator = std.testing.allocator;
    const content =
        \\- First
        \\
        \\- Second
        \\
        \\---
        \\- Third
    ;

    var quotes = try parse(allocator, content, "test.yaml");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), quotes.items.len);
}

test "yaml parser - no list items" {
    const allocator = std.testing.allocator;
    const content =
        \\key: value
        \\other: data
    ;

    var quotes = try parse(allocator, content, "test.yaml");
    defer quotes.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), quotes.items.len);
}

test "yaml parser - empty file" {
    const allocator = std.testing.allocator;
    const content = "";

    var quotes = try parse(allocator, content, "test.yaml");
    defer quotes.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), quotes.items.len);
}
