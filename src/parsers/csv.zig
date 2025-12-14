const std = @import("std");
const parser = @import("parser.zig");

/// Parse CSV format: extract first column from each row
pub fn parse(allocator: std.mem.Allocator, content: []const u8) !parser.ParseResult {
    var quotes = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (quotes.items) |quote| allocator.free(quote);
        quotes.deinit();
    }

    // Detect delimiter (comma or tab)
    const delimiter = detectDelimiter(content);

    // Split into lines
    var lines_it = std.mem.splitScalar(u8, content, '\n');
    var first_line = true;
    var skip_first = false;

    while (lines_it.next()) |line| {
        const trimmed_line = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed_line.len == 0) continue;

        // Check if first line is a header
        if (first_line) {
            first_line = false;
            if (isHeader(trimmed_line)) {
                skip_first = true;
                continue;
            }
        }

        // Extract first column
        if (try extractFirstColumn(allocator, trimmed_line, delimiter)) |column_value| {
            if (try parser.normalizeQuote(allocator, column_value)) |normalized| {
                try quotes.append(normalized);
            }
            allocator.free(column_value);
        }
    }

    if (quotes.items.len == 0) {
        return parser.ParserError.EmptyFile;
    }

    return parser.ParseResult{
        .quotes = quotes,
        .format = .csv,
    };
}

/// Detect delimiter: comma or tab
fn detectDelimiter(content: []const u8) u8 {
    var lines_it = std.mem.splitScalar(u8, content, '\n');
    if (lines_it.next()) |first_line| {
        const has_comma = std.mem.indexOf(u8, first_line, ",") != null;
        const has_tab = std.mem.indexOf(u8, first_line, "\t") != null;

        // Prefer comma if both present
        if (has_comma) return ',';
        if (has_tab) return '\t';
    }
    return ','; // Default to comma
}

/// Check if line looks like a header
fn isHeader(line: []const u8) bool {
    const lower = std.ascii.lowerString(line, line) catch return false;
    defer {};
    
    // Check for common header keywords
    return std.mem.indexOf(u8, line, "quote") != null or
        std.mem.indexOf(u8, line, "text") != null or
        std.mem.indexOf(u8, line, "content") != null;
}

/// Extract first column from CSV line
fn extractFirstColumn(allocator: std.mem.Allocator, line: []const u8, delimiter: u8) !?[]const u8 {
    if (line.len == 0) return null;

    // Handle quoted field: "text with, comma"
    if (line[0] == '"') {
        var i: usize = 1;
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        while (i < line.len) : (i += 1) {
            if (line[i] == '"') {
                // Check if it's an escaped quote ""
                if (i + 1 < line.len and line[i + 1] == '"') {
                    try result.append('"');
                    i += 1;
                } else {
                    // End of quoted field
                    return try result.toOwnedSlice();
                }
            } else {
                try result.append(line[i]);
            }
        }

        // Unclosed quote - return what we have
        return try result.toOwnedSlice();
    }

    // Unquoted field: extract until delimiter
    if (std.mem.indexOfScalar(u8, line, delimiter)) |delim_pos| {
        return try allocator.dupe(u8, line[0..delim_pos]);
    }

    // No delimiter - entire line is the field
    return try allocator.dupe(u8, line);
}

pub const csvParser = parser.Parser{
    .parseFn = parse,
};

// Tests
test "csv - basic parsing with header" {
    const allocator = std.testing.allocator;
    const content =
        \\quote,author
        \\First quote,Someone
        \\Second quote,Other
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
}

test "csv - no header" {
    const allocator = std.testing.allocator;
    const content =
        \\First quote,Someone
        \\Second quote,Other
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
}

test "csv - quoted fields with commas" {
    const allocator = std.testing.allocator;
    const content =
        \\quote,author
        \\"First, with comma",Someone
        \\"Second quote",Other
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.quotes.items.len);
    try std.testing.expectEqualStrings("First, with comma", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
}

test "csv - tab delimiter" {
    const allocator = std.testing.allocator;
    const content = "quote\tauthor\nFirst quote\tSomeone\nSecond quote\tOther";

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
}

test "csv - single column (no delimiter)" {
    const allocator = std.testing.allocator;
    const content =
        \\First quote
        \\Second quote
        \\Third quote
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
    try std.testing.expectEqualStrings("Third quote", result.quotes.items[2]);
}

test "csv - skip empty lines" {
    const allocator = std.testing.allocator;
    const content =
        \\First quote
        \\
        \\Second quote
        \\
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.quotes.items.len);
    try std.testing.expectEqualStrings("First quote", result.quotes.items[0]);
    try std.testing.expectEqualStrings("Second quote", result.quotes.items[1]);
}

test "csv - escaped quotes" {
    const allocator = std.testing.allocator;
    const content =
        \\quote
        \\"Quote with ""escaped"" quotes"
    ;

    var result = try parse(allocator, content);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.quotes.items.len);
    try std.testing.expectEqualStrings("Quote with \"escaped\" quotes", result.quotes.items[0]);
}
