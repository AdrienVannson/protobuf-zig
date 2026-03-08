/// Serializes a message to its binary Protocol Buffer representation.
///
/// Returns error.NotImplemented; full implementation is pending.
pub fn to_binary(msg: anytype) ![]u8 {
    _ = msg;
    return error.NotImplemented;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const std = @import("std");
const testing = std.testing;

test "to_binary returns NotImplemented" {
    try testing.expectError(error.NotImplemented, to_binary(.{}));
}
