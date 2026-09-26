const std = @import("std");
const fromBinary = @import("../wire/from_binary.zig").fromBinary;
const example = @import("../testgen/example.pb.zig");
const FileDescriptorProto = @import("../wkt/descriptor.pb.zig").FileDescriptorProto;

test "example.pb.zig _descriptor_bytes decodes file name" {
    const allocator = std.testing.allocator;
    var msg: FileDescriptorProto = .{};
    defer msg.deinit(allocator);

    try fromBinary(&msg, allocator, example._descriptor_bytes);
    try std.testing.expectEqualStrings("example.proto", msg.name.?);
}
