/// Serializes a message to its binary Protocol Buffer representation.
///
/// Returns error.NotImplemented; full implementation is pending.
pub fn to_binary(msg: anytype, ignore_unknown_fields: bool) ![]u8 {
    _ = msg;
    _ = ignore_unknown_fields;
    return error.NotImplemented;
}

/// Deserializes a message from its binary Protocol Buffer representation.
///
/// Returns error.NotImplemented; full implementation is pending.
pub fn from_binary(msg: anytype, ignore_unknown_fields: bool) !void {
    _ = msg;
    _ = ignore_unknown_fields;
    return error.NotImplemented;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const std = @import("std");
const testing = std.testing;

test "to_binary returns NotImplemented" {
    try testing.expectError(error.NotImplemented, to_binary(.{}, false));
}

test "from_binary returns NotImplemented" {
    try testing.expectError(error.NotImplemented, from_binary(.{}, false));
}
