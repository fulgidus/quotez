const std = @import("std");

/// Parse quotes from CSV/TSV file
/// Supports comma and tab delimiters
/// First column is treated as quote text
/// Second column (if present) is treated as author
/// Format: "quote — author" if both columns exist
pub fn parse(allocator: std.mem.Allocator, content: []const u8, path: []const u8) !std.ArrayList([]const u8) {
    _ = path; // unused but required by interface

    var quotes = std.ArrayList([]const u8){};
    errdefer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    // Detect delimiter (comma or tab)
    const delimiter = detectDelimiter(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    var first_line = true;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Skip header if it looks like one
        if (first_line) {
            first_line = false;
            if (isHeaderLine(trimmed, delimiter)) {
                continue;
            }
        }

        // Extract columns
        var columns = try extractColumns(trimmed, delimiter, allocator);
        defer {
            for (columns.items) |col| {
                allocator.free(col);
            }
            columns.deinit(allocator);
        }

        if (columns.items.len == 0) continue;

        // Build quote text
        const quote_text = if (columns.items.len >= 2 and columns.items[1].len > 0)
            // Has author: format as "quote — author"
            try std.fmt.allocPrint(allocator, "{s} — {s}", .{ columns.items[0], columns.items[1] })
        else
            // No author: just the quote
            try allocator.dupe(u8, columns.items[0]);

        if (quote_text.len > 0) {
            try quotes.append(allocator, quote_text);
        } else {
            allocator.free(quote_text);
        }
    }

    return quotes;
}

/// Detect CSV delimiter (comma or tab)
fn detectDelimiter(content: []const u8) u8 {
    // Check first line for delimiters
    const first_line_end = std.mem.indexOf(u8, content, "\n") orelse content.len;
    const first_line = content[0..first_line_end];

    // Count commas and tabs
    const comma_count = std.mem.count(u8, first_line, ",");
    const tab_count = std.mem.count(u8, first_line, "\t");

    return if (tab_count > comma_count) '\t' else ',';
}

/// Check if line looks like a header
fn isHeaderLine(line: []const u8, delimiter: u8) bool {
    // Simple heuristic: if first column contains common header words
    var iter = std.mem.splitScalar(u8, line, delimiter);
    if (iter.next()) |first_col| {
        const trimmed = std.mem.trim(u8, first_col, " \t\"'");
        const lower = std.ascii.allocLowerString(std.heap.page_allocator, trimmed) catch return false;
        defer std.heap.page_allocator.free(lower);

        return std.mem.eql(u8, lower, "quote") or
            std.mem.eql(u8, lower, "text") or
            std.mem.eql(u8, lower, "content") or
            std.mem.eql(u8, lower, "quotes");
    }
    return false;
}

/// Extract all columns from CSV line
fn extractColumns(line: []const u8, delimiter: u8, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var columns = std.ArrayList([]const u8){};
    errdefer {
        for (columns.items) |col| {
            allocator.free(col);
        }
        columns.deinit(allocator);
    }

    var iter = std.mem.splitScalar(u8, line, delimiter);
    while (iter.next()) |col| {
        // Trim whitespace and quotes
        var trimmed = std.mem.trim(u8, col, " \t");

        // Remove surrounding quotes if present
        if (trimmed.len >= 2) {
            if ((trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') or
                (trimmed[0] == '\'' and trimmed[trimmed.len - 1] == '\''))
            {
                trimmed = trimmed[1 .. trimmed.len - 1];
            }
        }

        const owned = try allocator.dupe(u8, trimmed);
        try columns.append(allocator, owned);
    }

    return columns;
}

// Unit tests
test "csv parser - basic comma-separated with authors" {
    const allocator = std.testing.allocator;
    const content =
        \\quote,author
        \\"First quote","Author 1"
        \\"Second quote","Author 2"
    ;

    var quotes = try parse(allocator, content, "test.csv");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), quotes.items.len);
    try std.testing.expectEqualStrings("First quote — Author 1", quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote — Author 2", quotes.items[1]);
}

test "csv parser - tab-separated" {
    const allocator = std.testing.allocator;
    const content = "quote\tauthor\nFirst\tSomeone\nSecond\tOther";

    var quotes = try parse(allocator, content, "test.tsv");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), quotes.items.len);
    try std.testing.expectEqualStrings("First — Someone", quotes.items[0]);
    try std.testing.expectEqualStrings("Second — Other", quotes.items[1]);
}

test "csv parser - no header" {
    const allocator = std.testing.allocator;
    const content =
        \\"Just a quote","Someone"
        \\"Another quote","Other"
    ;

    var quotes = try parse(allocator, content, "test.csv");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), quotes.items.len);
    try std.testing.expectEqualStrings("Just a quote — Someone", quotes.items[0]);
    try std.testing.expectEqualStrings("Another quote — Other", quotes.items[1]);
}

test "csv parser - single column" {
    const allocator = std.testing.allocator;
    const content = "First quote\nSecond quote\nThird quote";

    var quotes = try parse(allocator, content, "test.csv");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), quotes.items.len);
    try std.testing.expectEqualStrings("First quote", quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", quotes.items[1]);
}

test "csv parser - mixed with and without author" {
    const allocator = std.testing.allocator;
    const content =
        \\quote,author
        \\"Quote with author","Someone"
        \\"Quote without author",""
        \\"Another with author","Other"
    ;

    var quotes = try parse(allocator, content, "test.csv");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), quotes.items.len);
    try std.testing.expectEqualStrings("Quote with author — Someone", quotes.items[0]);
    try std.testing.expectEqualStrings("Quote without author", quotes.items[1]);
}

test "csv parser - empty lines ignored" {
    const allocator = std.testing.allocator;
    const content =
        \\quote,author
        \\
        \\"First","A"
        \\
        \\"Second","B"
    ;

    var quotes = try parse(allocator, content, "test.csv");
    defer {
        for (quotes.items) |quote| {
            allocator.free(quote);
        }
        quotes.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), quotes.items.len);
}

test "csv parser - delimiter detection" {
    try std.testing.expectEqual(@as(u8, ','), detectDelimiter("a,b,c\n1,2,3"));
    try std.testing.expectEqual(@as(u8, '\t'), detectDelimiter("a\tb\tc\n1\t2\t3"));
    try std.testing.expectEqual(@as(u8, ','), detectDelimiter("a,b\tc\n1,2\t3")); // More commas
}
