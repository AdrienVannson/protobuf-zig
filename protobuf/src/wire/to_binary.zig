const std = @import("std");
const binary_writer_mod = @import("binary_writer.zig");
const tag_mod = @import("tag.zig");
const metadata_mod = @import("../metadata.zig");

const BinaryWriter = binary_writer_mod.BinaryWriter;
const WireType = tag_mod.WireType;
const ScalarType = metadata_mod.ScalarType;
const FieldPresence = metadata_mod.FieldPresence;

/// Returns the Zig value type corresponding to a ScalarType.
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

/// Returns the wire type for a ScalarType.
fn scalarWireType(comptime scalar: ScalarType) WireType {
    return switch (scalar) {
        .int32, .int64, .uint32, .uint64, .sint32, .sint64, .bool => .varint,
        .fixed32, .sfixed32, .float => .bit32,
        .fixed64, .sfixed64, .double => .bit64,
        .string, .bytes => .length_delimited,
    };
}

/// Returns true when value equals the proto3 zero default for the scalar type.
fn isDefault(comptime scalar: ScalarType, value: scalarZigType(scalar)) bool {
    switch (scalar) {
        .string, .bytes => return value.len == 0,
        .bool => return !value,
        else => return value == 0,
    }
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

/// Encodes all scalar fields of msg into bw.
///
/// Iterates T._desc.fields in parallel with std.meta.fields(T): metadata entry i
/// corresponds to struct field i. Two safety checks skip misaligned entries:
///
/// 1. Bounds check: skip if i >= std.meta.fields(T).len.
/// 2. Type-compatibility check: skip any .scalar entry whose expected Zig type does
///    not match the actual struct field type at index i.
///
/// Non-scalar kinds (.message_field, .enum_field, .list, .map) are skipped.
fn writeMessage(bw: *BinaryWriter, msg: anytype) !void {
    const T = @TypeOf(msg);
    const struct_fields = std.meta.fields(T);

    inline for (T._desc.fields, 0..) |field_meta, i| {
        // Bounds check: skip if there is no struct field at this index.
        if (comptime i >= struct_fields.len) continue;

        switch (field_meta.kind) {
            .scalar => |sc| {
                const ExpectedType = comptime scalarZigType(sc.scalar);
                const StructFieldType = comptime struct_fields[i].type;
                const presence = comptime field_meta.presence;

                // Type-compatibility check: verify the struct field type matches
                // what the metadata scalar type expects before accessing the field.
                const type_ok = comptime switch (presence) {
                    .implicit => StructFieldType == ExpectedType,
                    .explicit, .legacy_required => StructFieldType == ?ExpectedType,
                };

                if (comptime type_ok) {
                    switch (presence) {
                        .implicit => {
                            const value: ExpectedType = @field(msg, struct_fields[i].name);
                            if (!isDefault(sc.scalar, value)) {
                                try bw.tag(@intCast(field_meta.number), comptime scalarWireType(sc.scalar));
                                try writeScalar(bw, sc.scalar, value);
                            }
                        },
                        .explicit, .legacy_required => {
                            const opt: ?ExpectedType = @field(msg, struct_fields[i].name);
                            if (opt) |value| {
                                try bw.tag(@intCast(field_meta.number), comptime scalarWireType(sc.scalar));
                                try writeScalar(bw, sc.scalar, value);
                            }
                        },
                    }
                }
            },
            else => {},
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
