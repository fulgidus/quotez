const std = @import("std");
const logger = @import("logger.zig");

/// Selection mode for quote serving
pub const SelectionMode = enum {
    random,
    sequential,
    random_no_repeat,
    shuffle_cycle,

    pub fn fromString(s: []const u8) ?SelectionMode {
        if (std.mem.eql(u8, s, "random")) return .random;
        if (std.mem.eql(u8, s, "sequential")) return .sequential;
        if (std.mem.eql(u8, s, "random-no-repeat")) return .random_no_repeat;
        if (std.mem.eql(u8, s, "shuffle-cycle")) return .shuffle_cycle;
        return null;
    }

    pub fn asString(self: SelectionMode) []const u8 {
        return switch (self) {
            .random => "random",
            .sequential => "sequential",
            .random_no_repeat => "random-no-repeat",
            .shuffle_cycle => "shuffle-cycle",
        };
    }
};

/// Immutable configuration loaded from quotez.toml
pub const Configuration = struct {
    // Server section
    host: []const u8,
    tcp_port: u16,
    udp_port: u16,

    // Quotes section
    directories: [][]const u8,
    selection_mode: SelectionMode,

    // Polling section
    polling_interval: u32,

    // Allocator for owned strings
    allocator: std.mem.Allocator,

    /// Default values per contract
    pub const Defaults = struct {
        pub const host: []const u8 = "0.0.0.0";
        pub const tcp_port: u16 = 17;
        pub const udp_port: u16 = 17;
        pub const selection_mode: SelectionMode = .random;
        pub const polling_interval: u32 = 60;
    };

    /// Load and parse configuration from file
    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Configuration {
        var log = logger.Logger.init();

        // Read configuration file
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            log.err("config_error", .{ .reason = "file not found", .path = path });
            return err;
        };
        defer file.close();

        const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
            log.err("config_error", .{ .reason = "failed to read file", .path = path });
            return err;
        };
        defer allocator.free(content);

        // Parse TOML
        var parser = TomlParser.init(allocator, content);
        defer parser.deinit();

        var config = try parser.parse();
        
        // Log loaded configuration
        log.info("config_loaded", .{
            .file = path,
            .tcp_port = config.tcp_port,
            .udp_port = config.udp_port,
            .host = config.host,
            .directories = config.directories.len,
            .mode = config.selection_mode.asString(),
            .interval = config.polling_interval,
        });

        return config;
    }

    /// Free all owned memory
    pub fn deinit(self: *Configuration) void {
        for (self.directories) |dir| {
            self.allocator.free(dir);
        }
        self.allocator.free(self.directories);
        self.allocator.free(self.host);
    }
};

/// Minimal TOML parser for quotez configuration
/// Supports only the subset needed: sections, strings, integers, arrays
const TomlParser = struct {
    allocator: std.mem.Allocator,
    content: []const u8,
    pos: usize,
    log: logger.Logger,

    // Parsed values
    host: ?[]const u8 = null,
    tcp_port: ?u16 = null,
    udp_port: ?u16 = null,
    directories: ?std.ArrayList([]const u8) = null,
    mode: ?[]const u8 = null,
    interval: ?u32 = null,

    pub fn init(allocator: std.mem.Allocator, content: []const u8) TomlParser {
        return .{
            .allocator = allocator,
            .content = content,
            .pos = 0,
            .log = logger.Logger.init(),
        };
    }

    pub fn deinit(self: *TomlParser) void {
        if (self.directories) |*dirs| {
            dirs.deinit();
        }
    }

    pub fn parse(self: *TomlParser) !Configuration {
        var current_section: ?[]const u8 = null;

        while (self.pos < self.content.len) {
            self.skipWhitespaceAndComments();
            if (self.pos >= self.content.len) break;

            // Check for section header [section]
            if (self.content[self.pos] == '[') {
                current_section = try self.parseSection();
                continue;
            }

            // Parse key = value
            try self.parseKeyValue(current_section);
        }

        // Validate required fields
        if (self.directories == null or self.directories.?.items.len == 0) {
            self.log.err("config_error", .{ .reason = "missing required field: quotes.directories" });
            return error.MissingRequiredField;
        }

        // Apply defaults and build configuration
        var config = Configuration{
            .allocator = self.allocator,
            .host = self.host orelse try self.allocator.dupe(u8, Configuration.Defaults.host),
            .tcp_port = self.tcp_port orelse Configuration.Defaults.tcp_port,
            .udp_port = self.udp_port orelse Configuration.Defaults.udp_port,
            .directories = try self.directories.?.toOwnedSlice(),
            .selection_mode = blk: {
                if (self.mode) |mode_str| {
                    if (SelectionMode.fromString(mode_str)) |mode| {
                        break :blk mode;
                    } else {
                        self.log.err("config_error", .{
                            .reason = "invalid selection mode",
                            .value = mode_str,
                        });
                        return error.InvalidSelectionMode;
                    }
                } else {
                    self.log.info("default_applied", .{ .field = "quotes.mode", .value = "random" });
                    break :blk Configuration.Defaults.selection_mode;
                }
            },
            .polling_interval = self.interval orelse blk: {
                self.log.info("default_applied", .{ .field = "polling.interval_seconds", .value = 60 });
                break :blk Configuration.Defaults.polling_interval;
            },
        };

        // Validate ranges
        if (config.tcp_port == 0 or config.udp_port == 0) {
            self.log.err("config_error", .{ .reason = "port must be in range 1-65535" });
            return error.InvalidPort;
        }

        if (config.polling_interval == 0) {
            self.log.err("config_error", .{ .reason = "polling interval must be positive" });
            return error.InvalidInterval;
        }

        // Log defaults that were applied
        if (self.host == null) {
            self.log.info("default_applied", .{ .field = "server.host", .value = "0.0.0.0" });
        }
        if (self.tcp_port == null) {
            self.log.info("default_applied", .{ .field = "server.tcp_port", .value = 17 });
        }
        if (self.udp_port == null) {
            self.log.info("default_applied", .{ .field = "server.udp_port", .value = 17 });
        }

        return config;
    }

    fn skipWhitespaceAndComments(self: *TomlParser) void {
        while (self.pos < self.content.len) {
            const c = self.content[self.pos];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.pos += 1;
            } else if (c == '#') {
                // Skip comment until end of line
                while (self.pos < self.content.len and self.content[self.pos] != '\n') {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }
    }

    fn parseSection(self: *TomlParser) ![]const u8 {
        self.pos += 1; // Skip '['
        const start = self.pos;
        while (self.pos < self.content.len and self.content[self.pos] != ']') {
            self.pos += 1;
        }
        if (self.pos >= self.content.len) return error.UnterminatedSection;
        const section = std.mem.trim(u8, self.content[start..self.pos], " \t");
        self.pos += 1; // Skip ']'
        return section;
    }

    fn parseKeyValue(self: *TomlParser, section: ?[]const u8) !void {
        // Parse key
        const key_start = self.pos;
        while (self.pos < self.content.len and self.content[self.pos] != '=' and self.content[self.pos] != '\n') {
            self.pos += 1;
        }
        if (self.pos >= self.content.len or self.content[self.pos] == '\n') {
            return; // Empty line or malformed
        }
        const key = std.mem.trim(u8, self.content[key_start..self.pos], " \t");
        self.pos += 1; // Skip '='
        self.skipWhitespaceAndComments();

        // Parse value based on section and key
        if (section) |sec| {
            if (std.mem.eql(u8, sec, "server")) {
                try self.parseServerValue(key);
            } else if (std.mem.eql(u8, sec, "quotes")) {
                try self.parseQuotesValue(key);
            } else if (std.mem.eql(u8, sec, "polling")) {
                try self.parsePollingValue(key);
            }
        }
    }

    fn parseServerValue(self: *TomlParser, key: []const u8) !void {
        if (std.mem.eql(u8, key, "host")) {
            self.host = try self.parseString();
        } else if (std.mem.eql(u8, key, "tcp_port")) {
            self.tcp_port = try self.parseInteger(u16);
        } else if (std.mem.eql(u8, key, "udp_port")) {
            self.udp_port = try self.parseInteger(u16);
        }
    }

    fn parseQuotesValue(self: *TomlParser, key: []const u8) !void {
        if (std.mem.eql(u8, key, "directories")) {
            self.directories = try self.parseStringArray();
        } else if (std.mem.eql(u8, key, "mode")) {
            self.mode = try self.parseString();
        }
    }

    fn parsePollingValue(self: *TomlParser, key: []const u8) !void {
        if (std.mem.eql(u8, key, "interval_seconds")) {
            self.interval = try self.parseInteger(u32);
        }
    }

    fn parseString(self: *TomlParser) ![]const u8 {
        if (self.pos >= self.content.len) return error.UnexpectedEof;
        const quote_char = self.content[self.pos];
        if (quote_char != '"' and quote_char != '\'') return error.ExpectedString;
        self.pos += 1;
        const start = self.pos;
        while (self.pos < self.content.len and self.content[self.pos] != quote_char) {
            self.pos += 1;
        }
        if (self.pos >= self.content.len) return error.UnterminatedString;
        const value = self.content[start..self.pos];
        self.pos += 1; // Skip closing quote
        return try self.allocator.dupe(u8, value);
    }

    fn parseInteger(self: *TomlParser, comptime T: type) !T {
        const start = self.pos;
        while (self.pos < self.content.len and std.ascii.isDigit(self.content[self.pos])) {
            self.pos += 1;
        }
        const value_str = self.content[start..self.pos];
        return std.fmt.parseInt(T, value_str, 10) catch return error.InvalidInteger;
    }

    fn parseStringArray(self: *TomlParser) !std.ArrayList([]const u8) {
        if (self.pos >= self.content.len or self.content[self.pos] != '[') {
            return error.ExpectedArray;
        }
        self.pos += 1; // Skip '['
        
        var array = std.ArrayList([]const u8).init(self.allocator);
        errdefer {
            for (array.items) |item| {
                self.allocator.free(item);
            }
            array.deinit();
        }

        while (true) {
            self.skipWhitespaceAndComments();
            if (self.pos >= self.content.len) return error.UnterminatedArray;
            if (self.content[self.pos] == ']') {
                self.pos += 1;
                break;
            }
            if (self.content[self.pos] == ',') {
                self.pos += 1;
                continue;
            }
            const item = try self.parseString();
            try array.append(item);
        }

        return array;
    }
};

// Unit tests
test "selection mode from string" {
    try std.testing.expectEqual(SelectionMode.random, SelectionMode.fromString("random").?);
    try std.testing.expectEqual(SelectionMode.sequential, SelectionMode.fromString("sequential").?);
    try std.testing.expectEqual(SelectionMode.random_no_repeat, SelectionMode.fromString("random-no-repeat").?);
    try std.testing.expectEqual(SelectionMode.shuffle_cycle, SelectionMode.fromString("shuffle-cycle").?);
    try std.testing.expectEqual(@as(?SelectionMode, null), SelectionMode.fromString("invalid"));
}

test "minimal valid configuration" {
    const allocator = std.testing.allocator;
    const content =
        \\[quotes]
        \\directories = ["/data/quotes"]
    ;

    var parser = TomlParser.init(allocator, content);
    defer parser.deinit();

    var config = try parser.parse();
    defer config.deinit();

    try std.testing.expectEqual(@as(u16, 17), config.tcp_port);
    try std.testing.expectEqual(@as(u16, 17), config.udp_port);
    try std.testing.expectEqualStrings("0.0.0.0", config.host);
    try std.testing.expectEqual(@as(usize, 1), config.directories.len);
    try std.testing.expectEqualStrings("/data/quotes", config.directories[0]);
    try std.testing.expectEqual(SelectionMode.random, config.selection_mode);
    try std.testing.expectEqual(@as(u32, 60), config.polling_interval);
}

test "full configuration with all fields" {
    const allocator = std.testing.allocator;
    const content =
        \\[server]
        \\host = "127.0.0.1"
        \\tcp_port = 8017
        \\udp_port = 8017
        \\
        \\[quotes]
        \\directories = ["/data/quotes", "/etc/quotez/custom"]
        \\mode = "shuffle-cycle"
        \\
        \\[polling]
        \\interval_seconds = 120
    ;

    var parser = TomlParser.init(allocator, content);
    defer parser.deinit();

    var config = try parser.parse();
    defer config.deinit();

    try std.testing.expectEqual(@as(u16, 8017), config.tcp_port);
    try std.testing.expectEqual(@as(u16, 8017), config.udp_port);
    try std.testing.expectEqualStrings("127.0.0.1", config.host);
    try std.testing.expectEqual(@as(usize, 2), config.directories.len);
    try std.testing.expectEqualStrings("/data/quotes", config.directories[0]);
    try std.testing.expectEqualStrings("/etc/quotez/custom", config.directories[1]);
    try std.testing.expectEqual(SelectionMode.shuffle_cycle, config.selection_mode);
    try std.testing.expectEqual(@as(u32, 120), config.polling_interval);
}

test "missing required field" {
    const allocator = std.testing.allocator;
    const content =
        \\[server]
        \\tcp_port = 17
    ;

    var parser = TomlParser.init(allocator, content);
    defer parser.deinit();

    const result = parser.parse();
    try std.testing.expectError(error.MissingRequiredField, result);
}

test "invalid selection mode" {
    const allocator = std.testing.allocator;
    const content =
        \\[quotes]
        \\directories = ["/data"]
        \\mode = "invalid_mode"
    ;

    var parser = TomlParser.init(allocator, content);
    defer parser.deinit();

    const result = parser.parse();
    try std.testing.expectError(error.InvalidSelectionMode, result);
}

test "empty directories array" {
    const allocator = std.testing.allocator;
    const content =
        \\[quotes]
        \\directories = []
    ;

    var parser = TomlParser.init(allocator, content);
    defer parser.deinit();

    const result = parser.parse();
    try std.testing.expectError(error.MissingRequiredField, result);
}

test "configuration with comments" {
    const allocator = std.testing.allocator;
    const content =
        \\# This is a comment
        \\[quotes]
        \\directories = ["/data/quotes"] # inline comment
        \\# Another comment
        \\mode = "sequential"
    ;

    var parser = TomlParser.init(allocator, content);
    defer parser.deinit();

    var config = try parser.parse();
    defer config.deinit();

    try std.testing.expectEqual(SelectionMode.sequential, config.selection_mode);
}
