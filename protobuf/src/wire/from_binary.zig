const std = @import("std");
const binary_reader_mod = @import("binary_reader.zig");
const tag_mod = @import("tag.zig");
const scalar_meta = @import("scalar_meta.zig");
const metadata_mod = @import("../metadata.zig");

const BinaryReader = binary_reader_mod.BinaryReader;
const WireType = tag_mod.WireType;
const ScalarType = metadata_mod.ScalarType;
const scalarZigType = scalar_meta.scalarZigType;
const scalarWireType = scalar_meta.scalarWireType;

fn readScalar(allocator: std.mem.Allocator, reader: *BinaryReader, comptime scalar: ScalarType) !scalarZigType(scalar) {
    _ = allocator;
    return switch (scalar) {
        .int32 => try reader.int32(),
        .int64 => try reader.int64(),
        .uint32 => try reader.uint32(),
        .uint64 => try reader.uint64(),
        .sint32 => try reader.sint32(),
        .sint64 => try reader.sint64(),
        .fixed32 => try reader.fixed32(),
        .fixed64 => try reader.fixed64(),
        .sfixed32 => try reader.sfixed32(),
        .sfixed64 => try reader.sfixed64(),
        .bool => try reader.bool_(),
        .float => try reader.float_(),
        .double => try reader.double(),
        .string => try reader.string(),
        .bytes => try reader.bytes(),
    };
}

fn readMessage(allocator: std.mem.Allocator, msg: anytype, reader: *BinaryReader) !void {
    const T = @TypeOf(msg.*);
    const struct_fields = std.meta.fields(T);
    while (!reader.eof()) {
        const t = try reader.tag();
        var matched = false;
        inline for (T._desc.fields) |fm| {
            if (!matched and @as(u32, @intCast(fm.number)) == t.number) {
                const field_name = comptime struct_fields[fm.field_index].name;
                if (comptime fm.oneof_variant) |variant_name| {
                    switch (fm.kind) {
                        .scalar => |sc| {
                            if (t.wire_type != comptime scalarWireType(sc.scalar)) return error.WireTypeMismatch;
                            const value = try readScalar(allocator, reader, sc.scalar);
                            // Free heap-owned payload of the existing oneof variant if it's a slice.
                            if (@field(msg.*, field_name)) |old_union| {
                                switch (old_union) {
                                    inline else => |payload| {
                                        if (comptime (@TypeOf(payload) == []const u8 or @TypeOf(payload) == []u8)) {
                                            allocator.free(payload);
                                        }
                                    },
                                }
                            }
                            const UnionType = @typeInfo(@TypeOf(@field(msg.*, field_name))).optional.child;
                            @field(msg.*, field_name) = @unionInit(UnionType, variant_name, value);
                        },
                        else => try reader.skipField(t.wire_type),
                    }
                } else {
                    switch (fm.kind) {
                        .scalar => |sc| {
                            if (t.wire_type != comptime scalarWireType(sc.scalar)) return error.WireTypeMismatch;
                            const value = try readScalar(allocator, reader, sc.scalar);
                            switch (fm.presence) {
                                .implicit => {
                                    if (comptime (scalarZigType(sc.scalar) == []const u8)) {
                                        const old: []const u8 = @field(msg.*, field_name);
                                        if (old.len != 0) allocator.free(old);
                                    }
                                    @field(msg.*, field_name) = value;
                                },
                                .explicit, .legacy_required => {
                                    if (comptime (scalarZigType(sc.scalar) == []const u8)) {
                                        if (@field(msg.*, field_name)) |old| allocator.free(old);
                                    }
                                    @field(msg.*, field_name) = value;
                                },
                            }
                        },
                        else => try reader.skipField(t.wire_type),
                    }
                }
                matched = true;
            }
        }
        if (!matched) try reader.skipField(t.wire_type);
    }
}

/// Deserializes a message from its binary Protocol Buffer representation.
///
/// msg must be a pointer to a message struct with a _desc field. String and
/// bytes fields decoded here are allocator-owned and must be freed by the
/// caller. Fields of unsupported kinds (.message_field, .enum_field, .list,
/// .map) are skipped.
pub fn from_binary(allocator: std.mem.Allocator, msg: anytype, data: []const u8) !void {
    var reader = BinaryReader.init(allocator, data);
    defer reader.deinit();
    try readMessage(allocator, msg, &reader);
    try reader.finish();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const FakeMessageFoo = @import("../test/fake_message_foo.zig").FakeMessageFoo;
const FakeOneofMessage = @import("../test/fake_message_foo.zig").FakeOneofMessage;
const to_binary = @import("to_binary.zig").to_binary;

test "empty message decodes to defaults" {
    var msg = FakeMessageFoo{};
    try from_binary(testing.allocator, &msg, &.{});
    try testing.expectEqual(@as(?i32, null), msg.explicit_field);
    try testing.expectEqual(@as(i32, 0), msg.implicit_field);
    try testing.expectEqual(@as(?[]const u8, null), msg.legacy_required_field);
}

test "implicit int32 non-zero decodes" {
    var msg = FakeMessageFoo{};
    try from_binary(testing.allocator, &msg, &.{ 0x10, 0x2a });
    try testing.expectEqual(@as(i32, 42), msg.implicit_field);
}

test "explicit optional int32 null: empty bytes leaves null" {
    var msg = FakeMessageFoo{};
    try from_binary(testing.allocator, &msg, &.{});
    try testing.expectEqual(@as(?i32, null), msg.explicit_field);
}

test "explicit optional int32 some value decodes" {
    var msg = FakeMessageFoo{};
    try from_binary(testing.allocator, &msg, &.{ 0x08, 0x05 });
    try testing.expectEqual(@as(?i32, 5), msg.explicit_field);
}

test "legacy_required string decodes" {
    var msg = FakeMessageFoo{};
    try from_binary(testing.allocator, &msg, &.{ 0x1a, 0x03, 'f', 'o', 'o' });
    defer if (msg.legacy_required_field) |s| testing.allocator.free(s);
    try testing.expectEqualStrings("foo", msg.legacy_required_field.?);
}

test "oneof null: empty bytes leaves null" {
    var msg = FakeOneofMessage{};
    try from_binary(testing.allocator, &msg, &.{});
    try testing.expectEqual(@as(?FakeOneofMessage.MyOneof, null), msg.my_oneof);
}

test "oneof uint32 variant decodes" {
    var msg = FakeOneofMessage{};
    try from_binary(testing.allocator, &msg, &.{ 0x10, 0x63 });
    try testing.expectEqual(FakeOneofMessage.MyOneof{ .a_uint32 = 99 }, msg.my_oneof.?);
}

test "oneof string variant decodes" {
    var msg = FakeOneofMessage{};
    try from_binary(testing.allocator, &msg, &.{ 0x1a, 0x02, 'h', 'i' });
    defer if (msg.my_oneof) |u| switch (u) {
        .a_string => |s| testing.allocator.free(s),
        else => {},
    };
    try testing.expectEqualStrings("hi", msg.my_oneof.?.a_string);
}

test "oneof with regular field combined" {
    var msg = FakeOneofMessage{};
    try from_binary(testing.allocator, &msg, &.{ 0x08, 0x07, 0x10, 0x05 });
    try testing.expectEqual(@as(i32, 7), msg.some_field);
    try testing.expectEqual(FakeOneofMessage.MyOneof{ .a_uint32 = 5 }, msg.my_oneof.?);
}

test "unknown field number is silently skipped" {
    // field 99 (varint, value=1) followed by field 2 (implicit int32=42)
    // tag(99, varint) = (99 << 3) | 0 = 792 → varint 792 = 0x98 0x06
    var msg = FakeMessageFoo{};
    try from_binary(testing.allocator, &msg, &.{ 0x98, 0x06, 0x01, 0x10, 0x2a });
    try testing.expectEqual(@as(i32, 42), msg.implicit_field);
}

test "wire type mismatch on known field returns error" {
    // field 2 (implicit int32) encoded as length_delimited (wire type 2) instead of varint
    // tag = (2 << 3) | 2 = 0x12
    var msg = FakeMessageFoo{};
    try testing.expectError(error.WireTypeMismatch, from_binary(testing.allocator, &msg, &.{ 0x12, 0x01, 0x2a }));
}

test "same scalar field twice: last value wins" {
    // field 2 (implicit int32) = 1, then field 2 = 42
    var msg = FakeMessageFoo{};
    try from_binary(testing.allocator, &msg, &.{ 0x10, 0x01, 0x10, 0x2a });
    try testing.expectEqual(@as(i32, 42), msg.implicit_field);
}

test "same string field twice: prior allocation freed, last value kept" {
    // field 3 (legacy_required string) = "foo", then "bar"
    var msg = FakeMessageFoo{};
    try from_binary(testing.allocator, &msg, &.{
        0x1a, 0x03, 'f', 'o', 'o',
        0x1a, 0x03, 'b', 'a', 'r',
    });
    defer if (msg.legacy_required_field) |s| testing.allocator.free(s);
    try testing.expectEqualStrings("bar", msg.legacy_required_field.?);
}

test "oneof variant overwritten: prior string freed" {
    // field 3 oneof a_string = "hi", then overwritten by field 2 oneof a_uint32 = 5
    var msg = FakeOneofMessage{};
    try from_binary(testing.allocator, &msg, &.{
        0x1a, 0x02, 'h', 'i',
        0x10, 0x05,
    });
    try testing.expectEqual(FakeOneofMessage.MyOneof{ .a_uint32 = 5 }, msg.my_oneof.?);
}

test "truncated varint returns UnexpectedEof" {
    var msg = FakeMessageFoo{};
    try testing.expectError(error.UnexpectedEof, from_binary(testing.allocator, &msg, &.{0x80}));
}

test "truncated length_delimited field returns LengthExceedsBuffer" {
    // tag for field 3 (string), then length=5 but only 2 bytes of payload
    var msg = FakeMessageFoo{};
    try testing.expectError(error.LengthExceedsBuffer, from_binary(testing.allocator, &msg, &.{
        0x1a, 0x05, 'a', 'b',
    }));
}

test "round-trip scalar fields" {
    const original = FakeMessageFoo{
        .explicit_field = 5,
        .implicit_field = 42,
        .legacy_required_field = "hello",
    };
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try to_binary(testing.allocator, original, buf.writer(testing.allocator));

    var decoded = FakeMessageFoo{};
    defer if (decoded.legacy_required_field) |s| testing.allocator.free(s);
    try from_binary(testing.allocator, &decoded, buf.items);

    try testing.expectEqual(original.explicit_field, decoded.explicit_field);
    try testing.expectEqual(original.implicit_field, decoded.implicit_field);
    try testing.expectEqualStrings(original.legacy_required_field.?, decoded.legacy_required_field.?);
}

test "round-trip oneof uint32" {
    const original = FakeOneofMessage{ .some_field = 7, .my_oneof = .{ .a_uint32 = 99 } };
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try to_binary(testing.allocator, original, buf.writer(testing.allocator));

    var decoded = FakeOneofMessage{};
    try from_binary(testing.allocator, &decoded, buf.items);

    try testing.expectEqual(original.some_field, decoded.some_field);
    try testing.expectEqual(original.my_oneof.?, decoded.my_oneof.?);
}

test "round-trip oneof string" {
    const original = FakeOneofMessage{ .my_oneof = .{ .a_string = "world" } };
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try to_binary(testing.allocator, original, buf.writer(testing.allocator));

    var decoded = FakeOneofMessage{};
    defer if (decoded.my_oneof) |u| switch (u) {
        .a_string => |s| testing.allocator.free(s),
        else => {},
    };
    try from_binary(testing.allocator, &decoded, buf.items);

    try testing.expectEqualStrings(original.my_oneof.?.a_string, decoded.my_oneof.?.a_string);
}
