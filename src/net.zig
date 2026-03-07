const std = @import("std");

/// Parse an IPv4 string like "127.0.0.1" or "0.0.0.0" into a big-endian u32
pub fn parseIpv4(host: []const u8) !u32 {
    if (std.mem.eql(u8, host, "0.0.0.0")) return 0;
    if (std.mem.eql(u8, host, "127.0.0.1")) return std.mem.nativeToBig(u32, 0x7F000001);

    var parts = std.mem.splitScalar(u8, host, '.');
    var result: u32 = 0;
    var count: usize = 0;
    while (parts.next()) |part| {
        if (count >= 4) return error.InvalidIp;
        const val = try std.fmt.parseInt(u8, part, 10);
        result = (result << 8) | val;
        count += 1;
    }
    if (count != 4) return error.InvalidIp;
    return std.mem.nativeToBig(u32, result);
}
