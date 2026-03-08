/// Deserializes a message from its binary Protocol Buffer representation.
///
/// Returns error.NotImplemented; full implementation is pending.
pub fn from_binary(msg: anytype) !void {
    _ = msg;
    return error.NotImplemented;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const std = @import("std");
const testing = std.testing;

test "from_binary returns NotImplemented" {
    try testing.expectError(error.NotImplemented, from_binary(.{}));
}
