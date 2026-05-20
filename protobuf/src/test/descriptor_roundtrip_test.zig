const std = @import("std");
const from_binary = @import("../wire/from_binary.zig").from_binary;
const example = @import("../testgen/example.pb.zig");
const FileDescriptorProto =
    @import("../wkt/google/protobuf/descriptor.pb.zig").FileDescriptorProto;

test "example.pb.zig DESCRIPTOR_BYTES decodes file name" {
    const alloc = std.testing.allocator;
    var msg: FileDescriptorProto = .{};
    // TODO proper deinit
    defer if (msg.name) |s| alloc.free(s);
    defer if (msg.package) |s| alloc.free(s);
    defer if (msg.syntax) |s| alloc.free(s);

    try from_binary(&msg, example.DESCRIPTOR_BYTES, alloc);
    try std.testing.expectEqualStrings("example.proto", msg.name.?);
}
