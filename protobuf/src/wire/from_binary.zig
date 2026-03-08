const std = @import("std");

/// Deserializes a message from its binary Protocol Buffer representation.
///
/// Returns error.NotImplemented; full implementation is pending.
pub fn from_binary(allocator: std.mem.Allocator, msg: anytype, data: []const u8) !void {
    _ = allocator;
    _ = msg;
    _ = data;
    return error.NotImplemented;
}
