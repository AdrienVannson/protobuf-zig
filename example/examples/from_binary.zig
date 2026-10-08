const std = @import("std");
const example = @import("example_pb");
const protobuf = @import("protobuf");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // <!-- include -->
    const encoded = "\x0a\x05Alice\x10\x1e\x1a\x11alice@example.com";

    var person = try protobuf.fromBinary(example.Person, allocator, encoded);
    defer person.deinit(allocator);

    // decoded: Alice, 30, alice@example.com
    std.debug.print("decoded: {s}, {d}, {s}\n", .{ person.name, person.age, person.emails.items[0] });
    // <!-- /include -->
}
