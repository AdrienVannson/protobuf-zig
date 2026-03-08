const std = @import("std");

/// Serializes a message to its binary Protocol Buffer representation,
/// writing the encoded bytes to writer.
///
/// Returns error.NotImplemented; full implementation is pending.
pub fn to_binary(allocator: std.mem.Allocator, msg: anytype, writer: anytype) !void {
    _ = allocator;
    _ = msg;
    _ = writer;
    return error.NotImplemented;
}
