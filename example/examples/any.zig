const std = @import("std");
const example = @import("example_pb");
const protobuf = @import("protobuf");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // <!-- include -->
    const Any = protobuf.wkt.any.Any;

    const person = example.Person{
        .name = "Alice",
        .age = 30,
        .email = "alice@example.com",
    };

    // Pack the person into an Any
    var payload = try Any.pack(allocator, person);
    defer payload.deinit(allocator);
    std.debug.print("type_url: {s}\n", .{payload.type_url}); // type.googleapis.com/example.Person

    // Check the type held by the Any, and unpack it
    if (payload.is(example.Person)) {
        var unpacked = try payload.unpack(allocator, example.Person);
        defer unpacked.deinit(allocator);
        std.debug.print("unpacked: {s}, {d}, {s}\n", .{ unpacked.name, unpacked.age, unpacked.email });
    }
    // <!-- /include -->
}
