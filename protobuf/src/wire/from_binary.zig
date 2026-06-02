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

const ReadMessageError = error{
    UnexpectedEof,
    InvalidVarint,
    InvalidFieldNumber,
    InvalidWireType,
    UnsupportedWireType,
    OutOfMemory,
    JoinWithoutFork,
    UnconsumedBytes,
    IntegerOverflow,
};

fn readListField(
    reader: *BinaryReader,
    field_ptr: anytype,
    comptime list_meta: anytype,
    wire_type: WireType,
    allocator: std.mem.Allocator,
) ReadMessageError!void {
    switch (comptime list_meta.element) {
        .scalar => |sc| {
            // Packed repeated field
            if (wire_type == .length_delimited and
                comptime (sc != .string and sc != .bytes))
            {
                try reader.fork();
                while (reader.remainingInScope() > 0) {
                    try field_ptr.*.append(allocator, try readScalar(reader, sc));
                }
                try reader.join();
            } else {
                try field_ptr.*.append(allocator, try readScalar(reader, sc));
            }
        },
        .message => {
            const Child = comptime std.meta.Child(std.meta.Child(@TypeOf(field_ptr.*.items)));
            const p = try allocator.create(Child);
            p.* = .{};
            errdefer allocator.destroy(p);
            try reader.fork();
            try readMessage(reader, p, allocator);
            try reader.join();
            try field_ptr.*.append(allocator, p);
        },
        .enum_type => {
            const Elem = comptime std.meta.Child(@TypeOf(field_ptr.*.items));
            if (wire_type == .length_delimited) {
                // Packed repeated enum.
                try reader.fork();
                while (reader.remainingInScope() > 0) {
                    try field_ptr.*.append(allocator, @as(Elem, @enumFromInt(try reader.int32())));
                }
                try reader.join();
            } else {
                try field_ptr.*.append(allocator, @as(Elem, @enumFromInt(try reader.int32())));
            }
        },
    }
}

fn readMessageField(reader: *BinaryReader, field_ptr: anytype, allocator: std.mem.Allocator) ReadMessageError!void {
    const FieldType = @TypeOf(field_ptr.*); // ?*Child
    const Child = std.meta.Child(std.meta.Child(FieldType));
    const child_ptr = field_ptr.* orelse blk: { // Merge into existing message if non-null, otherwise allocate new one.
        const p = try allocator.create(Child);
        p.* = .{};
        field_ptr.* = p;
        break :blk p;
    };
    try reader.fork();
    try readMessage(reader, child_ptr, allocator);
    try reader.join();
}

/// Decodes all fields of msg from the current scope of reader.
fn readMessage(reader: *BinaryReader, msg: anytype, allocator: std.mem.Allocator) ReadMessageError!void {
    const T = std.meta.Child(@TypeOf(msg));
    const struct_fields = std.meta.fields(T);

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
                            try skipField(reader, tag.wire_type);
                        } else {
                            if (comptime (sc.scalar == .string or sc.scalar == .bytes) and
                                field_meta.presence != .implicit)
                            {
                                if (@field(msg.*, field_name)) |old| allocator.free(old);
                            }
                            @field(msg.*, field_name) = try readScalar(reader, sc.scalar);
                        }
                    },
                    .message_field => try readMessageField(reader, &@field(msg.*, field_name), allocator),
                    .list => |list_meta| try readListField(reader, &@field(msg.*, field_name), list_meta, tag.wire_type, allocator),
                    .enum_field => {
                        const EnumType = comptime std.meta.Child(struct_fields[field_meta.field_index].type);
                        @field(msg.*, field_name) = @as(EnumType, @enumFromInt(try reader.int32()));
                    },
                    else => try skipField(reader, tag.wire_type),
                }
            }
        }

        if (!handled) { // TODO: Unknown field
            try skipField(reader, tag.wire_type);
        }
    }
}

/// Deserializes a message from its binary Protocol Buffer representation.
///
/// msg must be a pointer to the message struct (e.g. &my_msg).
pub fn from_binary(msg: anytype, data: []const u8, allocator: std.mem.Allocator) !void {
    var reader = BinaryReader.init(allocator, data);
    defer reader.deinit();
    try readMessage(&reader, msg, allocator);
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

test "message field decoded" {
    // message_field: field number 5, wire type length_delimited
    // tag = 0x2a, length = 5
    // Bar.value ("foo"): tag = 0x0a, length = 3, 'f', 'o', 'o'
    var msg: FakeMessageFoo = .{};
    defer msg.deinit(testing.allocator);
    try from_binary(&msg, &.{ 0x2a, 0x05, 0x0a, 0x03, 'f', 'o', 'o' }, testing.allocator);
    try testing.expect(msg.message_field != null);
    try testing.expectEqualStrings("foo", msg.message_field.?.value.?);
}

test "repeated string field unpacked single element decoded" {
    // repeated_field: field number 4, wire type length_delimited
    // tag = (4 << 3) | 2 = 0x22, length = 3, "foo"
    var msg: FakeMessageFoo = .{};
    defer msg.deinit(testing.allocator);
    try from_binary(&msg, &.{ 0x22, 0x03, 'f', 'o', 'o' }, testing.allocator);
    try testing.expectEqual(@as(usize, 1), msg.repeated_field.items.len);
    try testing.expectEqualStrings("foo", msg.repeated_field.items[0]);
}

test "repeated string field unpacked two elements decoded" {
    // repeated_field: field number 4, two occurrences
    // first: tag 0x22, length 3, "foo"
    // second: tag 0x22, length 2, "hi"
    var msg: FakeMessageFoo = .{};
    defer msg.deinit(testing.allocator);
    try from_binary(&msg, &.{ 0x22, 0x03, 'f', 'o', 'o', 0x22, 0x02, 'h', 'i' }, testing.allocator);
    try testing.expectEqual(@as(usize, 2), msg.repeated_field.items.len);
    try testing.expectEqualStrings("foo", msg.repeated_field.items[0]);
    try testing.expectEqualStrings("hi", msg.repeated_field.items[1]);
}

test "singular enum field decoded" {
    // color_field: field number 10, varint: tag = 0x50, color_green = 2 = 0x02
    try expectFromBinary(FakeMessageFoo, FakeMessageFoo{ .color_field = .color_green }, &.{ 0x50, 0x02 });
}

test "singular enum field unknown value decoded" {
    // An unknown varint value (99) must round-trip via the non-exhaustive enum tag.
    // tag = 0x50, value 99 = 0x63
    var msg: FakeMessageFoo = .{};
    defer msg.deinit(testing.allocator);
    try from_binary(&msg, &.{ 0x50, 0x63 }, testing.allocator);
    try testing.expectEqual(@as(i32, 99), @intFromEnum(msg.color_field.?));
}

test "repeated packed enum field decoded" {
    // repeated_color_field: field number 13, packed: tag = 0x6a, length = 2, color_red=1, color_green=2
    var msg: FakeMessageFoo = .{};
    defer msg.deinit(testing.allocator);
    try from_binary(&msg, &.{ 0x6a, 0x02, 0x01, 0x02 }, testing.allocator);
    try testing.expectEqual(@as(usize, 2), msg.repeated_color_field.items.len);
    try testing.expectEqual(FakeMessageFoo.Color.color_red, msg.repeated_color_field.items[0]);
    try testing.expectEqual(FakeMessageFoo.Color.color_green, msg.repeated_color_field.items[1]);
}

test "repeated unpacked enum field decoded" {
    // Two unpacked occurrences of field number 13 (varint): tag=0x68, value, tag=0x68, value
    // tag = (13 << 3) | 0 = 0x68
    var msg: FakeMessageFoo = .{};
    defer msg.deinit(testing.allocator);
    try from_binary(&msg, &.{ 0x68, 0x01, 0x68, 0x02 }, testing.allocator);
    try testing.expectEqual(@as(usize, 2), msg.repeated_color_field.items.len);
    try testing.expectEqual(FakeMessageFoo.Color.color_red, msg.repeated_color_field.items[0]);
    try testing.expectEqual(FakeMessageFoo.Color.color_green, msg.repeated_color_field.items[1]);
}

test "repeated float field packed decoded" {
    // repeated_float_field: field number 12, wire type length_delimited (packed)
    // tag = (12 << 3) | 2 = 0x62, length = 8 (two f32 values)
    // 1.0 as f32 little-endian: 0x00 0x00 0x80 0x3f
    // 2.0 as f32 little-endian: 0x00 0x00 0x00 0x40
    var msg: FakeMessageFoo = .{};
    defer msg.deinit(testing.allocator);
    try from_binary(&msg, &.{ 0x62, 0x08, 0x00, 0x00, 0x80, 0x3f, 0x00, 0x00, 0x00, 0x40 }, testing.allocator);
    try testing.expectEqual(@as(usize, 2), msg.repeated_float_field.items.len);
    try testing.expectEqual(@as(f32, 1.0), msg.repeated_float_field.items[0]);
    try testing.expectEqual(@as(f32, 2.0), msg.repeated_float_field.items[1]);
}

test "repeated float field packed empty blob decoded" {
    // tag = 0x62, length = 0 (empty packed blob)
    var msg: FakeMessageFoo = .{};
    defer msg.deinit(testing.allocator);
    try from_binary(&msg, &.{ 0x62, 0x00 }, testing.allocator);
    try testing.expectEqual(@as(usize, 0), msg.repeated_float_field.items.len);
}
