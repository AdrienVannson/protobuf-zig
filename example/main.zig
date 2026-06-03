const std = @import("std");
const example = @import("gen/example.pb.zig");
const protobuf = @import("protobuf");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const person = example.Person{
        .name = "Alice",
        .age = 30,
        .email = "alice@example.com",
    };

    const encoded = try protobuf.to_binary(allocator, person);
    defer allocator.free(encoded);
    std.debug.print("encoded ({d} bytes): {x}\n", .{ encoded.len, encoded });
}
