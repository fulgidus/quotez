const std = @import("std");

/// Parser interface for quote file formats
/// All parsers implement this function signature
pub const ParseFn = *const fn (allocator: std.mem.Allocator, content: []const u8, path: []const u8) anyerror!std.ArrayList([]const u8);

/// Quote format types
pub const Format = enum {
    json,
    csv,
    toml,
    yaml,
    txt,

    pub fn fromExtension(ext: []const u8) ?Format {
        if (std.mem.eql(u8, ext, ".json")) return .json;
        if (std.mem.eql(u8, ext, ".csv")) return .csv;
        if (std.mem.eql(u8, ext, ".toml")) return .toml;
        if (std.mem.eql(u8, ext, ".yaml") or std.mem.eql(u8, ext, ".yml")) return .yaml;
        if (std.mem.eql(u8, ext, ".txt")) return .txt;
        return null;
    }
};

/// Detect format from file extension and content
pub fn detectFormat(path: []const u8, content: []const u8) Format {
    // Try extension first
    const ext = std.fs.path.extension(path);
    if (Format.fromExtension(ext)) |format| {
        return format;
    }

    // Content sniffing fallback (detection order per contract)
    if (content.len == 0) return .txt;

    // Skip whitespace
    var i: usize = 0;
    while (i < content.len and std.ascii.isWhitespace(content[i])) : (i += 1) {}
    if (i >= content.len) return .txt;

    // JSON: starts with { or [
    if (content[i] == '{' or content[i] == '[') return .json;

    // Look for YAML markers (--- or key:)
    if (std.mem.startsWith(u8, content[i..], "---")) return .yaml;
    if (std.mem.indexOf(u8, content, ":") != null) {
        // Could be YAML or TOML, check for [section]
        if (std.mem.indexOf(u8, content, "[") == null and 
            std.mem.indexOf(u8, content, "=") == null) {
            return .yaml;
        }
    }

    // TOML: [section] or key = value
    if (std.mem.indexOf(u8, content, "[") != null or 
        std.mem.indexOf(u8, content, " = ") != null) {
        return .toml;
    }

    // CSV: commas or tabs in first line
    const first_line_end = std.mem.indexOf(u8, content, "\n") orelse content.len;
    const first_line = content[0..first_line_end];
    if (std.mem.indexOf(u8, first_line, ",") != null or 
        std.mem.indexOf(u8, first_line, "\t") != null) {
        return .csv;
    }

    // Default: plaintext
    return .txt;
}

/// Parse quotes from file based on detected format
pub fn parse(allocator: std.mem.Allocator, path: []const u8, content: []const u8) !std.ArrayList([]const u8) {
    const format = detectFormat(path, content);
    
    return switch (format) {
        .json => @import("json.zig").parse(allocator, content, path),
        .csv => @import("csv.zig").parse(allocator, content, path),
        .toml => @import("toml.zig").parse(allocator, content, path),
        .yaml => @import("yaml.zig").parse(allocator, content, path),
        .txt => @import("txt.zig").parse(allocator, content, path),
    };
}

// Unit tests
test "format detection from extension" {
    try std.testing.expectEqual(Format.json, Format.fromExtension(".json").?);
    try std.testing.expectEqual(Format.csv, Format.fromExtension(".csv").?);
    try std.testing.expectEqual(Format.toml, Format.fromExtension(".toml").?);
    try std.testing.expectEqual(Format.yaml, Format.fromExtension(".yaml").?);
    try std.testing.expectEqual(Format.yaml, Format.fromExtension(".yml").?);
    try std.testing.expectEqual(Format.txt, Format.fromExtension(".txt").?);
    try std.testing.expectEqual(@as(?Format, null), Format.fromExtension(".xyz"));
}

test "content sniffing - json" {
    const json_content = "{ \"quotes\": [\"test\"] }";
    try std.testing.expectEqual(Format.json, detectFormat("unknown.dat", json_content));
    
    const json_array = "[\"quote1\", \"quote2\"]";
    try std.testing.expectEqual(Format.json, detectFormat("unknown", json_array));
}

test "content sniffing - yaml" {
    const yaml_doc = "---\n- quote1\n- quote2";
    try std.testing.expectEqual(Format.yaml, detectFormat("unknown", yaml_doc));
    
    const yaml_list = "- First quote\n- Second quote";
    try std.testing.expectEqual(Format.yaml, detectFormat("unknown", yaml_list));
}

test "content sniffing - toml" {
    const toml_section = "[quotes]\nlist = [\"a\", \"b\"]";
    try std.testing.expectEqual(Format.toml, detectFormat("unknown", toml_section));
    
    const toml_keyval = "key = \"value\"\nother = 123";
    try std.testing.expectEqual(Format.toml, detectFormat("unknown", toml_keyval));
}

test "content sniffing - csv" {
    const csv_content = "quote,author\n\"First\",\"Someone\"";
    try std.testing.expectEqual(Format.csv, detectFormat("unknown", csv_content));
    
    const tsv_content = "quote\tauthor\nFirst\tSomeone";
    try std.testing.expectEqual(Format.csv, detectFormat("unknown", tsv_content));
}

test "content sniffing - plaintext fallback" {
    const plain = "Just some text\nMore text";
    try std.testing.expectEqual(Format.txt, detectFormat("unknown", plain));
    
    const empty = "";
    try std.testing.expectEqual(Format.txt, detectFormat("unknown", empty));
}

test "extension overrides content" {
    const json_content = "{ \"quotes\": [] }";
    try std.testing.expectEqual(Format.json, detectFormat("file.json", json_content));
    try std.testing.expectEqual(Format.txt, detectFormat("file.txt", json_content));
}
