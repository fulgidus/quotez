const std = @import("std");

/// Log level enumeration matching standard severity levels
pub const Level = enum {
    debug,
    info,
    warn,
    err,

    pub fn asString(self: Level) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
        };
    }
};

/// Minimal structured logger that writes to stdout
/// Format: [timestamp] LEVEL event key1=value1 key2=value2
pub const Logger = struct {
    writer: std.fs.File.Writer,
    mutex: std.Thread.Mutex = .{},

    /// Initialize logger with stdout
    pub fn init() Logger {
        return .{
            .writer = std.io.getStdOut().writer(),
        };
    }

    /// Log a structured message with key-value fields
    /// Thread-safe via mutex
    pub fn log(self: *Logger, level: Level, event: []const u8, fields: anytype) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Write timestamp
        const timestamp = std.time.timestamp();
        self.writer.print("[{d}] ", .{timestamp}) catch return;

        // Write level
        self.writer.print("{s} ", .{level.asString()}) catch return;

        // Write event name
        self.writer.print("{s}", .{event}) catch return;

        // Write structured fields
        const FieldsType = @TypeOf(fields);
        if (@typeInfo(FieldsType) == .Struct) {
            inline for (std.meta.fields(FieldsType)) |field| {
                const value = @field(fields, field.name);
                self.writer.print(" {s}=", .{field.name}) catch return;
                self.writeValue(value) catch return;
            }
        }

        self.writer.print("\n", .{}) catch return;
    }

    /// Write a value with appropriate formatting
    fn writeValue(self: *Logger, value: anytype) !void {
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);

        switch (type_info) {
            .Int, .ComptimeInt => try self.writer.print("{d}", .{value}),
            .Float, .ComptimeFloat => try self.writer.print("{d:.2}", .{value}),
            .Bool => try self.writer.print("{}", .{value}),
            .Pointer => |ptr_info| {
                if (ptr_info.size == .Slice and ptr_info.child == u8) {
                    // String slice
                    try self.writer.print("{s}", .{value});
                } else {
                    try self.writer.print("{any}", .{value});
                }
            },
            .Array => |arr_info| {
                if (arr_info.child == u8) {
                    // String array
                    try self.writer.print("{s}", .{value});
                } else {
                    try self.writer.print("{any}", .{value});
                }
            },
            .Optional => {
                if (value) |v| {
                    try self.writeValue(v);
                } else {
                    try self.writer.print("null", .{});
                }
            },
            else => try self.writer.print("{any}", .{value}),
        }
    }

    /// Convenience methods for each log level
    pub fn debug(self: *Logger, event: []const u8, fields: anytype) void {
        self.log(.debug, event, fields);
    }

    pub fn info(self: *Logger, event: []const u8, fields: anytype) void {
        self.log(.info, event, fields);
    }

    pub fn warn(self: *Logger, event: []const u8, fields: anytype) void {
        self.log(.warn, event, fields);
    }

    pub fn err(self: *Logger, event: []const u8, fields: anytype) void {
        self.log(.err, event, fields);
    }
};

// Unit tests
test "logger initialization" {
    var logger = Logger.init();
    try std.testing.expect(@TypeOf(logger.writer) == std.fs.File.Writer);
}

test "log level string conversion" {
    try std.testing.expectEqualStrings("DEBUG", Level.debug.asString());
    try std.testing.expectEqualStrings("INFO", Level.info.asString());
    try std.testing.expectEqualStrings("WARN", Level.warn.asString());
    try std.testing.expectEqualStrings("ERROR", Level.err.asString());
}

test "structured logging with various types" {
    var logger = Logger.init();

    // Test with integer
    logger.info("test_event", .{ .count = 42 });

    // Test with string
    logger.info("test_event", .{ .message = "hello" });

    // Test with multiple fields
    logger.info("test_event", .{
        .port = 17,
        .host = "0.0.0.0",
        .enabled = true,
    });

    // Test with optional
    const maybe_value: ?u32 = null;
    logger.info("test_event", .{ .optional = maybe_value });
}

test "all log levels" {
    var logger = Logger.init();

    logger.debug("debug_event", .{ .level = 0 });
    logger.info("info_event", .{ .level = 1 });
    logger.warn("warn_event", .{ .level = 2 });
    logger.err("error_event", .{ .level = 3 });
}
