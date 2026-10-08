const std = @import("std");
const example = @import("example_pb");
const protobuf = @import("protobuf");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // <!-- include -->
    var emails = [_][]const u8{"alice@example.com"};
    const person = example.Person{
        .name = "Alice",
        .age = 30,
        .emails = .fromOwnedSlice(&emails),
    };

    const encoded = try protobuf.toBinary(allocator, person);
    defer allocator.free(encoded);
    std.debug.print("encoded ({d} bytes): {x}\n", .{ encoded.len, encoded });
    // <!-- /include -->
}
