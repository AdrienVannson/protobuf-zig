const std = @import("std");
const binary_writer_mod = @import("binary_writer.zig");
const tag_mod = @import("tag.zig");
const metadata_mod = @import("../metadata.zig");
const field_access = @import("../field_access.zig");

const BinaryWriter = binary_writer_mod.BinaryWriter;
const WireType = tag_mod.WireType;
const ScalarType = metadata_mod.ScalarType;

const scalarZigType = field_access.scalarZigType;

/// Returns the wire type for a ScalarType.
fn scalarWireType(comptime scalar: ScalarType) WireType {
    return switch (scalar) {
        .int32, .int64, .uint32, .uint64, .sint32, .sint64, .bool => .varint,
        .fixed32, .sfixed32, .float => .bit32,
        .fixed64, .sfixed64, .double => .bit64,
        .string, .bytes => .length_delimited,
    };
}

/// Writes a scalar value to bw using the appropriate BinaryWriter method.
fn writeScalar(bw: *BinaryWriter, comptime scalar: ScalarType, value: scalarZigType(scalar)) !void {
    switch (scalar) {
        .int32 => try bw.int32(value),
        .int64 => try bw.int64(value),
        .uint32 => try bw.uint32(value),
        .uint64 => try bw.uint64(value),
        .sint32 => try bw.sint32(value),
        .sint64 => try bw.sint64(value),
        .fixed32 => try bw.fixed32(value),
        .fixed64 => try bw.fixed64(value),
        .sfixed32 => try bw.sfixed32(value),
        .sfixed64 => try bw.sfixed64(value),
        .bool => try bw.bool_(value),
        .float => try bw.float_(value),
        .double => try bw.double(value),
        .string => try bw.string(value),
        .bytes => try bw.bytes(value),
    }
}

/// Encodes all fields of msg into bw.
///
/// Uses field_access to uniformly handle both regular fields and oneof
/// variants, eliminating separate code paths.
fn writeMessage(bw: *BinaryWriter, msg: anytype) !void {
    const T = @TypeOf(msg);

    inline for (T._desc.fields) |field_meta| {
        if (field_access.hasField(msg, field_meta)) {
            switch (field_meta.kind) {
                .scalar => |sc| {
                    try bw.tag(@intCast(field_meta.number), comptime scalarWireType(sc.scalar));
                    try writeScalar(bw, sc.scalar, field_access.getField(msg, field_meta).?);
                },
                else => {},
            }
        }
    }
}

/// Serializes a message to its binary Protocol Buffer representation,
/// writing the encoded bytes to writer.
pub fn to_binary(allocator: std.mem.Allocator, msg: anytype, writer: anytype) !void {
    var bw = BinaryWriter.init(allocator);
    defer bw.deinit();
    try writeMessage(&bw, msg);
    try bw.finish(writer);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const FakeMessageFoo = @import("../test/fake_message_foo.zig").FakeMessageFoo;
const FakeOneofMessage = @import("../test/fake_message_foo.zig").FakeOneofMessage;

fn expectToBinary(msg: anytype, expected: []const u8) !void {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try to_binary(testing.allocator, msg, buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, expected, buf.items);
}

test "empty message encodes to nothing" {
    try expectToBinary(FakeMessageFoo{}, &.{});
}

test "implicit int32 non-zero encodes tag and varint" {
    // implicit_field: field number 2, wire type varint
    // tag = (2 << 3) | 0 = 0x10, value 42 = 0x2a
    try expectToBinary(FakeMessageFoo{ .implicit_field = 42 }, &.{ 0x10, 0x2a });
}

test "explicit optional int32 null emits nothing" {
    try expectToBinary(FakeMessageFoo{ .explicit_field = null }, &.{});
}

test "explicit optional int32 some value encodes tag and varint" {
    // explicit_field: field number 1, wire type varint
    // tag = (1 << 3) | 0 = 0x08, value 5 = 0x05
    try expectToBinary(FakeMessageFoo{ .explicit_field = 5 }, &.{ 0x08, 0x05 });
}

test "legacy_required string non-empty encodes tag, length, and bytes" {
    // legacy_required_field: field number 3, wire type length_delimited
    // tag = (3 << 3) | 2 = 0x1a, length = 3, "foo"
    try expectToBinary(
        FakeMessageFoo{ .legacy_required_field = "foo" },
        &.{ 0x1a, 0x03, 'f', 'o', 'o' },
    );
}

test "oneof null emits nothing" {
    try expectToBinary(FakeOneofMessage{}, &.{});
}

test "oneof uint32 variant encodes tag and varint" {
    // field number 2, wire type varint
    // tag = (2 << 3) | 0 = 0x10, value 99 = 0x63
    try expectToBinary(
        FakeOneofMessage{ .my_oneof = .{ .a_uint32 = 99 } },
        &.{ 0x10, 0x63 },
    );
}

test "oneof string variant encodes tag, length, and bytes" {
    // field number 3, wire type length_delimited
    // tag = (3 << 3) | 2 = 0x1a, length = 2, "hi"
    try expectToBinary(
        FakeOneofMessage{ .my_oneof = .{ .a_string = "hi" } },
        &.{ 0x1a, 0x02, 'h', 'i' },
    );
}

test "oneof with regular field combined" {
    // some_field (number 1, implicit int32): tag = 0x08, value 7 = 0x07
    // oneof a_uint32 (number 2): tag = 0x10, value 5 = 0x05
    try expectToBinary(
        FakeOneofMessage{ .some_field = 7, .my_oneof = .{ .a_uint32 = 5 } },
        &.{ 0x08, 0x07, 0x10, 0x05 },
    );
}
