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

/// Minimal structured logger that writes to stderr via std.debug.print
/// Format: [timestamp] LEVEL event key1=value1 key2=value2
pub const Logger = struct {
    mutex: std.Thread.Mutex = .{},

    /// Initialize logger
    pub fn init() Logger {
        return .{};
    }

    /// Log a structured message with key-value fields
    /// Thread-safe via mutex
    pub fn log(self: *Logger, level: Level, event: []const u8, fields: anytype) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Write timestamp, level, and event
        const timestamp = std.time.timestamp();
        std.debug.print("[{d}] {s} {s}", .{ timestamp, level.asString(), event });

        // Write structured fields
        const FieldsType = @TypeOf(fields);
        if (@typeInfo(FieldsType) == .@"struct") {
            inline for (std.meta.fields(FieldsType)) |field| {
                const value = @field(fields, field.name);
                std.debug.print(" {s}=", .{field.name});
                printValue(value);
            }
        }

        std.debug.print("\n", .{});
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

/// Print a value with appropriate formatting
fn printValue(value: anytype) void {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    switch (type_info) {
        .int, .comptime_int => std.debug.print("{d}", .{value}),
        .float, .comptime_float => std.debug.print("{d:.2}", .{value}),
        .bool => std.debug.print("{}", .{value}),
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                // String slice ([]const u8)
                std.debug.print("{s}", .{value});
            } else if (ptr_info.size == .one) {
                // Pointer to single item - check if it's a pointer to u8 array (string literal)
                const child_info = @typeInfo(ptr_info.child);
                if (child_info == .array and child_info.array.child == u8) {
                    // Pointer to u8 array (e.g., *const [5:0]u8 from "1.0.0")
                    std.debug.print("{s}", .{value});
                } else {
                    std.debug.print("{any}", .{value});
                }
            } else {
                std.debug.print("{any}", .{value});
            }
        },
        .array => |arr_info| {
            if (arr_info.child == u8) {
                // String array
                std.debug.print("{s}", .{value});
            } else {
                std.debug.print("{any}", .{value});
            }
        },
        .optional => {
            if (value) |v| {
                printValue(v);
            } else {
                std.debug.print("null", .{});
            }
        },
        else => std.debug.print("{any}", .{value}),
    }
}

// Unit tests
test "logger initialization" {
    const logger = Logger.init();
    _ = logger;
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
