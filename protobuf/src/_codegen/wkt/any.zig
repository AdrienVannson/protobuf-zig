const std = @import("std");
const protobuf = @import("../../root.zig");

const type_url_prefix = "type.googleapis.com/";

/// Returns the fully-qualified type name of a type URL: the part after the
/// last `/`, or the whole URL if it contains none.
fn typeName(type_url: []const u8) []const u8 {
    const i = std.mem.lastIndexOfScalar(u8, type_url, '/') orelse return type_url;
    return type_url[i + 1 ..];
}

/// Packs `msg` into a new `AnyT`. The returned `type_url` and `value` are
/// owned by the caller and released by `AnyT.deinit`.
pub fn pack(comptime AnyT: type, allocator: std.mem.Allocator, msg: anytype) !AnyT {
    const T = @TypeOf(msg);
    const value = try protobuf.toBinary(allocator, msg);
    errdefer allocator.free(value);
    const type_url = try std.mem.concat(allocator, u8, &.{ type_url_prefix, T._metadata.fully_qualified_proto_name });
    return .{ .type_url = type_url, .value = value };
}

/// Returns whether `any` holds a message of type `T`.
pub fn is(any: anytype, comptime T: type) bool {
    return std.mem.eql(u8, typeName(any.type_url), T._metadata.fully_qualified_proto_name);
}

/// Decodes the message held by `any` as a `T`. Returns
/// `error.AnyTypeMismatch` if `any` does not hold a `T`.
pub fn unpack(any: anytype, allocator: std.mem.Allocator, comptime T: type) !T {
    if (!is(any, T)) return error.AnyTypeMismatch;
    var msg: T = .{};
    errdefer msg.deinit(allocator);
    try protobuf.fromBinary(&msg, allocator, any.value);
    return msg;
}

test "Any pack / is / unpack" {
    const example = @import("../../testgen/example.pb.zig");
    const Any = protobuf.wkt.any.Any;
    const allocator = std.testing.allocator;

    const original = example.Foo{ .name = "hello", .id = 42 };
    var any = try Any.pack(allocator, original);
    defer any.deinit(allocator);

    try std.testing.expectEqualStrings("type.googleapis.com/example.Foo", any.type_url);
    try std.testing.expect(any.is(example.Foo));
    try std.testing.expect(!any.is(example.Bar));

    var foo = try any.unpack(allocator, example.Foo);
    defer foo.deinit(allocator);
    try std.testing.expectEqualStrings("hello", foo.name);
    try std.testing.expectEqual(42, foo.id);

    try std.testing.expectError(error.AnyTypeMismatch, any.unpack(allocator, example.Bar));
}
