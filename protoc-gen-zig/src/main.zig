const std = @import("std");
const protobuf = @import("protobuf");

pub fn add(x: i64, y: i64) i64 {
    return x + y;
}

pub fn hello() void {
    std.debug.print("Hello from protoc-gen-zig!\n", .{});
}

pub fn main() !void {
    hello();
}

test "add" {
    try std.testing.expectEqual(@as(i64, 3), add(1, 2));
}
