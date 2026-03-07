const std = @import("std");

pub fn add(x: i64, y: i64) i64 {
    return x + y;
}

pub fn hello() void {
    std.debug.print("Hello from protobuf!\n", .{});
}

test "add" {
    try std.testing.expectEqual(@as(i64, 5), add(2, 3));
}
