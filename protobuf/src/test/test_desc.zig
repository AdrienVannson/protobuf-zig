const std = @import("std");
const example = @import("../testgen/example.pb.zig");
const import_main = @import("../testgen/import/import_main.pb.zig");

test "_desc exposes the linked message descriptor" {
    const io = std.testing.io;
    const foo = try example.Foo._desc(io);
    try std.testing.expectEqualStrings("Foo", foo.local_name);
    try std.testing.expectEqualStrings("example.Foo", foo.fully_qualified_proto_name);
    try std.testing.expectEqualStrings("example.proto", foo.file.name);
    // name, id, struct, and the two oneof members x/y.
    try std.testing.expectEqual(@as(usize, 5), foo.fields.len);
}

test "_desc resolves within-file message references by pointer identity" {
    const io = std.testing.io;
    const bar = try example.Bar._desc(io);
    // Fields are in field-number order: foo(1), tags(2), color(3), colors(4).
    const foo_field = bar.fields[0];
    try std.testing.expectEqualStrings("foo", foo_field.name);
    // The message_field points at the very same cached DescMessage as Foo._desc().
    try std.testing.expectEqual(try example.Foo._desc(io), foo_field.kind.message_field.message);
}

test "_desc links nested message to its parent" {
    const io = std.testing.io;
    const nested = try example.Bar.Nested._desc(io);
    try std.testing.expectEqualStrings("Nested", nested.local_name);
    try std.testing.expectEqual(try example.Bar._desc(io), nested.parent.?);
}

test "_desc resolves cross-file references" {
    const io = std.testing.io;
    const main = try import_main.ImportMain._desc(io);
    const single = main.fields[0];
    try std.testing.expectEqualStrings("single", single.name);
    const dep_msg = single.kind.message_field.message;
    try std.testing.expectEqualStrings("dep.DepMsg", dep_msg.fully_qualified_proto_name);
    // The referenced message lives in the imported file.
    try std.testing.expectEqualStrings("import/import_dep.proto", dep_msg.file.name);
}
