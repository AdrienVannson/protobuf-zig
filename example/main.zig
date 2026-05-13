const std = @import("std");
const example = @import("gen/example.pb.zig");

pub fn main() void {
    const person = example.Person{
        .name = "Alice",
        .age = 30,
        .email = "alice@example.com",
    };

    std.debug.print("name:  {s}\n", .{person.getName()});
    std.debug.print("age:   {d}\n", .{person.getAge()});
    std.debug.print("email: {s}\n", .{person.getEmail()});
}
