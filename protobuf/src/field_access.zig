const std = @import("std");
const metadata_mod = @import("metadata.zig");

const ScalarType = metadata_mod.ScalarType;
const FieldPresence = metadata_mod.FieldPresence;
const FieldMetadata = metadata_mod.FieldMetadata;

/// Returns the Zig value type corresponding to a ScalarType.
pub fn scalarZigType(comptime scalar: ScalarType) type {
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

/// Returns true when value equals the proto3 zero default for the scalar type.
fn isDefault(comptime scalar: ScalarType, value: scalarZigType(scalar)) bool {
    switch (scalar) {
        .string, .bytes => return value.len == 0,
        .bool => return !value,
        else => return value == 0,
    }
}

/// Returns the unwrapped payload type for a field.
///
/// - Oneof: the union variant's payload type.
/// - Scalar/enum implicit: the struct field type directly.
/// - Scalar/enum explicit/required: unwraps the optional.
/// - Message: unwraps the optional.
/// - List/map: the container type as-is.
fn PayloadType(comptime T: type, comptime field_meta: FieldMetadata) type {
    @setEvalBranchQuota(10_000);
    const struct_fields = std.meta.fields(T);
    const StructFieldType = struct_fields[field_meta.field_index].type;

    if (field_meta.oneof_variant) |variant_name| {
        // The struct field is ?union(enum). Get the union type, then the variant payload.
        const UnionType = @typeInfo(StructFieldType).optional.child;
        const union_fields = std.meta.fields(UnionType);
        inline for (union_fields) |uf| {
            if (comptime std.mem.eql(u8, uf.name, variant_name)) {
                return uf.type;
            }
        }
        unreachable;
    }

    return switch (field_meta.kind) {
        .scalar => switch (field_meta.presence) {
            .implicit => StructFieldType,
            .explicit, .legacy_required => @typeInfo(StructFieldType).optional.child,
        },
        .enum_field => switch (field_meta.presence) {
            .implicit => StructFieldType,
            .explicit, .legacy_required => @typeInfo(StructFieldType).optional.child,
        },
        .message_field => @typeInfo(StructFieldType).optional.child,
        .list, .map => StructFieldType,
    };
}

/// Returns true if the field is "present" in the message.
pub inline fn hasField(msg: anytype, comptime field_meta: FieldMetadata) bool {
    const T = @TypeOf(msg);
    const struct_fields = std.meta.fields(T);
    const field_name = struct_fields[field_meta.field_index].name;

    if (comptime field_meta.oneof_variant != null) {
        return hasOneofVariant(msg, field_meta);
    }

    return switch (field_meta.kind) {
        .scalar => |sc| switch (field_meta.presence) {
            .implicit => !isDefault(sc.scalar, @field(msg, field_name)),
            .explicit, .legacy_required => @field(msg, field_name) != null,
        },
        .enum_field => switch (field_meta.presence) {
            .implicit => @intFromEnum(@field(msg, field_name)) != 0,
            .explicit, .legacy_required => @field(msg, field_name) != null,
        },
        .message_field => @field(msg, field_name) != null,
        .list => @field(msg, field_name).items.len > 0,
        .map => @field(msg, field_name).count() > 0,
    };
}

// Separate function to avoid comptime issues with the inline switch.
inline fn hasOneofVariant(msg: anytype, comptime field_meta: FieldMetadata) bool {
    const T = @TypeOf(msg);
    const struct_fields = std.meta.fields(T);
    const field_name = struct_fields[field_meta.field_index].name;
    const variant_name = comptime field_meta.oneof_variant.?;

    if (@field(msg, field_name)) |active_union| {
        switch (active_union) {
            inline else => |_, tag| {
                return comptime std.mem.eql(u8, @tagName(tag), variant_name);
            },
        }
    }
    return false;
}

/// Returns the field value if present, or null if absent.
pub inline fn getField(msg: anytype, comptime field_meta: FieldMetadata) ?PayloadType(@TypeOf(msg), field_meta) {
    const T = @TypeOf(msg);
    const struct_fields = std.meta.fields(T);
    const field_name = struct_fields[field_meta.field_index].name;

    if (comptime field_meta.oneof_variant != null) {
        return getOneofVariant(msg, field_meta);
    }

    return @field(msg, field_name);
}

inline fn getOneofVariant(msg: anytype, comptime field_meta: FieldMetadata) ?PayloadType(@TypeOf(msg), field_meta) {
    const T = @TypeOf(msg);
    const struct_fields = std.meta.fields(T);
    const field_name = struct_fields[field_meta.field_index].name;
    const variant_name = comptime field_meta.oneof_variant.?;

    if (@field(msg, field_name)) |active_union| {
        switch (active_union) {
            inline else => |payload, tag| {
                if (comptime std.mem.eql(u8, @tagName(tag), variant_name)) {
                    return payload;
                }
            },
        }
    }
    return null;
}

/// Sets a field value on the message.
pub inline fn setField(msg: anytype, comptime field_meta: FieldMetadata, value: PayloadType(PointerChild(@TypeOf(msg)), field_meta)) void {
    const T = PointerChild(@TypeOf(msg));
    const struct_fields = std.meta.fields(T);
    const fi = field_meta.field_index;
    const field_name = struct_fields[fi].name;

    if (comptime field_meta.oneof_variant) |variant_name| {
        const StructFieldType = struct_fields[fi].type;
        const UnionType = @typeInfo(StructFieldType).optional.child;
        @field(msg, field_name) = @unionInit(UnionType, variant_name, value);
    } else {
        @field(msg, field_name) = value;
    }
}

fn PointerChild(comptime T: type) type {
    return @typeInfo(T).pointer.child;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const FakeMessageFoo = @import("test/fake_message_foo.zig").FakeMessageFoo;
const FakeOneofMessage = @import("test/fake_message_foo.zig").FakeOneofMessage;

test "hasField: implicit default is false" {
    const msg = FakeMessageFoo{};
    try testing.expect(!hasField(msg, FakeMessageFoo._desc.fields[1])); // implicit_field = 0
}

test "hasField: implicit non-default is true" {
    const msg = FakeMessageFoo{ .implicit_field = 42 };
    try testing.expect(hasField(msg, FakeMessageFoo._desc.fields[1]));
}

test "hasField: explicit null is false" {
    const msg = FakeMessageFoo{};
    try testing.expect(!hasField(msg, FakeMessageFoo._desc.fields[0])); // explicit_field = null
}

test "hasField: explicit set is true" {
    const msg = FakeMessageFoo{ .explicit_field = 5 };
    try testing.expect(hasField(msg, FakeMessageFoo._desc.fields[0]));
}

test "hasField: oneof null is false" {
    const msg = FakeOneofMessage{};
    try testing.expect(!hasField(msg, FakeOneofMessage._desc.fields[1])); // a_uint32
    try testing.expect(!hasField(msg, FakeOneofMessage._desc.fields[2])); // a_string
}

test "hasField: oneof wrong variant is false" {
    const msg = FakeOneofMessage{ .my_oneof = .{ .a_string = "hi" } };
    try testing.expect(!hasField(msg, FakeOneofMessage._desc.fields[1])); // a_uint32
}

test "hasField: oneof correct variant is true" {
    const msg = FakeOneofMessage{ .my_oneof = .{ .a_uint32 = 99 } };
    try testing.expect(hasField(msg, FakeOneofMessage._desc.fields[1])); // a_uint32
    try testing.expect(!hasField(msg, FakeOneofMessage._desc.fields[2])); // a_string
}

test "getField: implicit returns value" {
    const msg = FakeMessageFoo{ .implicit_field = 42 };
    try testing.expectEqual(@as(?i32, 42), getField(msg, FakeMessageFoo._desc.fields[1]));
}

test "getField: explicit null returns null" {
    const msg = FakeMessageFoo{};
    try testing.expectEqual(@as(?i32, null), getField(msg, FakeMessageFoo._desc.fields[0]));
}

test "getField: explicit set returns value" {
    const msg = FakeMessageFoo{ .explicit_field = 5 };
    try testing.expectEqual(@as(?i32, 5), getField(msg, FakeMessageFoo._desc.fields[0]));
}

test "getField: oneof matching returns payload" {
    const msg = FakeOneofMessage{ .my_oneof = .{ .a_uint32 = 99 } };
    try testing.expectEqual(@as(?u32, 99), getField(msg, FakeOneofMessage._desc.fields[1]));
}

test "getField: oneof wrong returns null" {
    const msg = FakeOneofMessage{ .my_oneof = .{ .a_string = "hi" } };
    try testing.expectEqual(@as(?u32, null), getField(msg, FakeOneofMessage._desc.fields[1]));
}

test "setField: set implicit scalar" {
    var msg = FakeMessageFoo{};
    setField(&msg, FakeMessageFoo._desc.fields[1], 42);
    try testing.expectEqual(@as(i32, 42), msg.implicit_field);
}

test "setField: set explicit scalar wraps optional" {
    var msg = FakeMessageFoo{};
    setField(&msg, FakeMessageFoo._desc.fields[0], 10);
    try testing.expectEqual(@as(?i32, 10), msg.explicit_field);
}

test "setField: set oneof variant" {
    var msg = FakeOneofMessage{};
    setField(&msg, FakeOneofMessage._desc.fields[1], 99);
    try testing.expectEqual(@as(?u32, 99), getField(msg, FakeOneofMessage._desc.fields[1]));
}

test "setField: switch oneof variant" {
    var msg = FakeOneofMessage{ .my_oneof = .{ .a_uint32 = 99 } };
    setField(&msg, FakeOneofMessage._desc.fields[2], "hello");
    try testing.expectEqual(@as(?u32, null), getField(msg, FakeOneofMessage._desc.fields[1]));
    try testing.expectEqualStrings("hello", getField(msg, FakeOneofMessage._desc.fields[2]).?);
}
