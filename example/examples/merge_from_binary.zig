const std = @import("std");
const example = @import("example_pb");
const protobuf = @import("protobuf");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // <!-- include -->
    // The message owns its strings, which are freed by `deinit` or when overwritten
    var person = example.Person{ .name = try allocator.dupe(u8, "Alice"), .age = 30 };
    defer person.deinit(allocator);

    // Person{ .age = 31, .email = "alice@example.com" }
    const encoded = "\x10\x1f\x1a\x11alice@example.com";
    try protobuf.mergeFromBinary(&person, allocator, encoded);

    // merged: Alice, 31, alice@example.com
    std.debug.print("merged: {s}, {d}, {s}\n", .{ person.name, person.age, person.email });
    // <!-- /include -->
}
