const std = @import("std");

/// Common error types for all parsers
pub const ParserError = error{
    MalformedFormat,
    InvalidUtf8,
    EmptyFile,
    UnsupportedStructure,
};

/// Format types supported by quotez
pub const Format = enum {
    json,
    csv,
    toml,
    yaml,
    plaintext,
};

/// Result of parsing a file
pub const ParseResult = struct {
    quotes: std.ArrayList([]const u8),
    format: Format,

    pub fn deinit(self: *ParseResult) void {
        for (self.quotes.items) |quote| {
            self.quotes.allocator.free(quote);
        }
        self.quotes.deinit();
    }
};

/// Parser interface - each format parser implements this
pub const Parser = struct {
    parseFn: *const fn (allocator: std.mem.Allocator, content: []const u8) anyerror!ParseResult,

    pub fn parse(self: Parser, allocator: std.mem.Allocator, content: []const u8) !ParseResult {
        return self.parseFn(allocator, content);
    }
};

/// Detect file format based on extension and content
pub fn detectFormat(file_path: []const u8, content: []const u8) Format {
    // Check extension first
    if (std.mem.endsWith(u8, file_path, ".json")) {
        if (looksLikeJson(content)) return .json;
    } else if (std.mem.endsWith(u8, file_path, ".csv")) {
        if (looksLikeCsv(content)) return .csv;
    } else if (std.mem.endsWith(u8, file_path, ".toml")) {
        if (looksLikeToml(content)) return .toml;
    } else if (std.mem.endsWith(u8, file_path, ".yaml") or std.mem.endsWith(u8, file_path, ".yml")) {
        if (looksLikeYaml(content)) return .yaml;
    }

    // Try format detection by content in order: JSON → CSV → TOML → YAML → plaintext
    if (looksLikeJson(content)) return .json;
    if (looksLikeCsv(content)) return .csv;
    if (looksLikeToml(content)) return .toml;
    if (looksLikeYaml(content)) return .yaml;

    // Fallback to plaintext
    return .plaintext;
}

/// Check if content looks like JSON
fn looksLikeJson(content: []const u8) bool {
    const trimmed = std.mem.trim(u8, content, &std.ascii.whitespace);
    if (trimmed.len == 0) return false;
    return trimmed[0] == '{' or trimmed[0] == '[';
}

/// Check if content looks like CSV
fn looksLikeCsv(content: []const u8) bool {
    // Look for comma or tab in first line
    var it = std.mem.splitScalar(u8, content, '\n');
    if (it.next()) |first_line| {
        const has_comma = std.mem.indexOf(u8, first_line, ",") != null;
        const has_tab = std.mem.indexOf(u8, first_line, "\t") != null;
        return has_comma or has_tab;
    }
    return false;
}

/// Check if content looks like TOML
fn looksLikeToml(content: []const u8) bool {
    // Look for [section] or key = value patterns
    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;
        if (trimmed[0] == '#') continue; // Comment

        // Check for [section]
        if (trimmed[0] == '[') return true;

        // Check for key = value
        if (std.mem.indexOf(u8, trimmed, " = ") != null or
            std.mem.indexOf(u8, trimmed, "=") != null)
        {
            return true;
        }
    }
    return false;
}

/// Check if content looks like YAML
fn looksLikeYaml(content: []const u8) bool {
    const trimmed = std.mem.trim(u8, content, &std.ascii.whitespace);
    if (trimmed.len == 0) return false;

    // Check for --- document separator
    if (std.mem.startsWith(u8, trimmed, "---")) return true;

    // Check for key: value or - item patterns
    var it = std.mem.splitScalar(u8, trimmed, '\n');
    while (it.next()) |line| {
        const line_trim = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (line_trim.len == 0) continue;
        if (line_trim[0] == '#') continue; // Comment

        // Check for - list item
        if (line_trim[0] == '-' and line_trim.len > 1 and line_trim[1] == ' ') return true;

        // Check for key: value
        if (std.mem.indexOf(u8, line_trim, ": ") != null or
            std.mem.indexOf(u8, line_trim, ":") != null)
        {
            return true;
        }
    }
    return false;
}

/// Normalize UTF-8 and trim whitespace from a quote
pub fn normalizeQuote(allocator: std.mem.Allocator, input: []const u8) !?[]const u8 {
    // Trim whitespace
    const trimmed = std.mem.trim(u8, input, &std.ascii.whitespace);
    if (trimmed.len == 0) return null;

    // Validate UTF-8 and replace invalid sequences
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < trimmed.len) {
        const len = std.unicode.utf8ByteSequenceLength(trimmed[i]) catch {
            // Invalid UTF-8, insert replacement character
            try result.appendSlice("�");
            i += 1;
            continue;
        };

        if (i + len > trimmed.len) {
            // Incomplete sequence at end
            try result.appendSlice("�");
            break;
        }

        // Validate the full sequence
        _ = std.unicode.utf8Decode(trimmed[i .. i + len]) catch {
            // Invalid sequence
            try result.appendSlice("�");
            i += len;
            continue;
        };

        // Valid UTF-8, copy it
        try result.appendSlice(trimmed[i .. i + len]);
        i += len;
    }

    // Collapse multiple whitespace to single space
    return try collapseWhitespace(allocator, result.items);
}

/// Collapse multiple whitespace characters into single spaces
fn collapseWhitespace(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var prev_was_space = false;
    for (input) |c| {
        if (std.ascii.isWhitespace(c)) {
            if (!prev_was_space) {
                try result.append(' ');
                prev_was_space = true;
            }
        } else {
            try result.append(c);
            prev_was_space = false;
        }
    }

    return result.toOwnedSlice();
}

// Tests
test "detectFormat - JSON" {
    try std.testing.expectEqual(Format.json, detectFormat("test.json", "[\"quote\"]"));
    try std.testing.expectEqual(Format.json, detectFormat("test.txt", "{\"quotes\": []}"));
}

test "detectFormat - CSV" {
    try std.testing.expectEqual(Format.csv, detectFormat("test.csv", "quote,author\nHello,World"));
    try std.testing.expectEqual(Format.csv, detectFormat("test.txt", "one,two,three"));
}

test "detectFormat - TOML" {
    try std.testing.expectEqual(Format.toml, detectFormat("test.toml", "quotes = []"));
    try std.testing.expectEqual(Format.toml, detectFormat("test.txt", "[section]"));
}

test "detectFormat - YAML" {
    try std.testing.expectEqual(Format.yaml, detectFormat("test.yaml", "---\n- quote"));
    try std.testing.expectEqual(Format.yaml, detectFormat("test.txt", "key: value"));
}

test "detectFormat - plaintext fallback" {
    try std.testing.expectEqual(Format.plaintext, detectFormat("test.txt", "Just plain text"));
}

test "normalizeQuote - basic trim" {
    const allocator = std.testing.allocator;
    const result = try normalizeQuote(allocator, "  hello  ");
    defer if (result) |r| allocator.free(r);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("hello", result.?);
}

test "normalizeQuote - collapse whitespace" {
    const allocator = std.testing.allocator;
    const result = try normalizeQuote(allocator, "hello    world");
    defer if (result) |r| allocator.free(r);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("hello world", result.?);
}

test "normalizeQuote - empty after trim" {
    const allocator = std.testing.allocator;
    const result = try normalizeQuote(allocator, "   ");
    try std.testing.expect(result == null);
}
