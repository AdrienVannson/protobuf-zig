const std = @import("std");
const example = @import("example_pb");
const protobuf = @import("protobuf");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // <!-- include -->
    // The target owns its strings, which merge frees when overwritten
    var person = example.Person{ .name = try allocator.dupe(u8, "Alice"), .age = 30 };
    defer person.deinit(allocator);

    var emails = [_][]const u8{"alice@example.com"};
    const update = example.Person{ .age = 31, .emails = .fromOwnedSlice(&emails) };

    try protobuf.merge(&person, allocator, update);

    // merged: Alice, 31, alice@example.com
    std.debug.print("merged: {s}, {d}, {s}\n", .{ person.name, person.age, person.emails.items[0] });
    // <!-- /include -->
}
