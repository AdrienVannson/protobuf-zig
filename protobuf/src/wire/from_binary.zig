const std = @import("std");
const binary_reader_mod = @import("binary_reader.zig");
const tag_mod = @import("tag.zig");
const metadata_mod = @import("../_codegen/metadata.zig");

const BinaryReader = binary_reader_mod.BinaryReader;
const WireType = tag_mod.WireType;
const ScalarType = metadata_mod.ScalarType;

fn scalarZigType(comptime scalar: ScalarType) type {
    return switch (scalar) {
        .int32, .sint32, .sfixed32 => i32,
        .int64, .sint64, .sfixed64 => i64,
        .uint32, .fixed32 => u32,
        .uint64, .fixed64 => u64,
        .bool => bool,
        .float => f32,
        .double => f64,
        .string, .bytes => []const u8,
    };
}

fn readScalar(reader: *BinaryReader, comptime scalar: ScalarType) !scalarZigType(scalar) {
    return switch (scalar) {
        .int32 => reader.int32(),
        .int64 => reader.int64(),
        .uint32 => reader.uint32(),
        .uint64 => reader.uint64(),
        .sint32 => reader.sint32(),
        .sint64 => reader.sint64(),
        .fixed32 => reader.fixed32(),
        .fixed64 => reader.fixed64(),
        .sfixed32 => reader.sfixed32(),
        .sfixed64 => reader.sfixed64(),
        .bool => reader.bool_(),
        .float => reader.float_(),
        .double => reader.double(),
        .string => reader.string(),
        .bytes => reader.bytes(),
    };
}

fn skipField(reader: *BinaryReader, wire_type: WireType) !void {
    switch (wire_type) {
        .varint => _ = try reader.varint(),
        .bit32 => _ = try reader.fixed32(),
        .bit64 => _ = try reader.fixed64(),
        .length_delimited => {
            const b = try reader.bytes();
            reader.allocator.free(b);
        },
        .sgroup, .egroup => return error.UnsupportedWireType,
    }
}

/// Deserializes a message from its binary Protocol Buffer representation.
///
/// msg must be a pointer to the message struct (e.g. &my_msg).
pub fn from_binary(msg: anytype, data: []const u8, allocator: std.mem.Allocator) !void {
    const T = std.meta.Child(@TypeOf(msg));
    const struct_fields = std.meta.fields(T);

    var reader = BinaryReader.init(allocator, data);
    defer reader.deinit();

    while (reader.remainingInScope() > 0) {
        const tag = try reader.tag();
        const number = tag.number;

        var handled = false;

        // TODO: check that the compiler is able to optimize this loop into O(log(n))
        inline for (T._desc.fields) |field_meta| {
            if (field_meta.number == number) {
                handled = true;
                const field_name = comptime struct_fields[field_meta.field_index].name;

                switch (field_meta.kind) {
                    .scalar => |sc| {
                        if (comptime field_meta.oneof_variant != null) {
                            try skipField(&reader, tag.wire_type);
                        } else {
                            if (comptime (sc.scalar == .string or sc.scalar == .bytes) and
                                field_meta.presence != .implicit)
                            {
                                if (@field(msg.*, field_name)) |old| allocator.free(old);
                            }
                            @field(msg.*, field_name) = try readScalar(&reader, sc.scalar);
                        }
                    },
                    else => try skipField(&reader, tag.wire_type),
                }
            }
        }

        if (!handled) { // TODO: Unknown field
            try skipField(&reader, tag.wire_type);
        }
    }

    try reader.finish();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const FakeMessageFoo = @import("../test/fake_message_foo.zig").FakeMessageFoo;

fn expectFromBinary(comptime T: type, expected: T, data: []const u8) !void {
    var msg: T = .{};
    defer msg.deinit(testing.allocator);
    try from_binary(&msg, data, testing.allocator);
    try testing.expectEqualDeep(expected, msg);
}

test "empty input leaves message at zero values" {
    try expectFromBinary(FakeMessageFoo, FakeMessageFoo{}, &.{});
}

test "implicit int32 non-zero decoded" {
    // field 2, varint: tag = 0x10, value 42 = 0x2a
    try expectFromBinary(FakeMessageFoo, FakeMessageFoo{ .implicit_field = 42 }, &.{ 0x10, 0x2a });
}

test "explicit optional int32 decoded" {
    // field 1, varint: tag = 0x08, value 5 = 0x05
    try expectFromBinary(FakeMessageFoo, FakeMessageFoo{ .explicit_field = 5 }, &.{ 0x08, 0x05 });
}

test "legacy_required string decoded" {
    // field 3, length_delimited: tag = 0x1a, length 3, "foo"
    var msg: FakeMessageFoo = .{};
    try from_binary(&msg, &.{ 0x1a, 0x03, 'f', 'o', 'o' }, testing.allocator);
    defer testing.allocator.free(msg.legacy_required_field.?);
    try testing.expectEqualStrings("foo", msg.legacy_required_field.?);
}

test "two fields in one message decoded" {
    // explicit_field (1): tag 0x08, value 5
    // implicit_field (2): tag 0x10, value 42
    try expectFromBinary(
        FakeMessageFoo,
        FakeMessageFoo{ .explicit_field = 5, .implicit_field = 42 },
        &.{ 0x08, 0x05, 0x10, 0x2a },
    );
}

test "unknown field number skipped" {
    // Field 99 (varint wire type) with value 1, then implicit_field (2) with value 7.
    // tag for field 99 varint = (99 << 3) | 0 = 0x318 → encoded as 0x98 0x06
    try expectFromBinary(
        FakeMessageFoo,
        FakeMessageFoo{ .implicit_field = 7 },
        &.{ 0x98, 0x06, 0x01, 0x10, 0x07 },
    );
}
