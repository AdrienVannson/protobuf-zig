const std = @import("std");
const example = @import("gen/example.pb.zig");
const protobuf = @import("protobuf");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const person = example.Person{
        .name = "Alice",
        .age = 30,
        .email = "alice@example.com",
    };

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);
    try protobuf.to_binary(allocator, person, buf.writer(allocator));
    std.debug.print("encoded ({d} bytes): {x}\n", .{ buf.items.len, buf.items });
}
