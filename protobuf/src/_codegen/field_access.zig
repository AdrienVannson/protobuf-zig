const std = @import("std");
const metadata = @import("metadata.zig");

const FieldMetadata = metadata.FieldMetadata;
const FieldMetadataKind = metadata.FieldMetadataKind;
const ScalarType = metadata.ScalarType;
const DefaultValue = metadata.DefaultValue;

fn getScalarDefault(
    comptime scalar: ScalarType,
    comptime default_value: ?DefaultValue,
) metadata.scalarZigType(scalar) {
    if (comptime default_value) |dv| {
        return switch (comptime scalar) {
            .bool => dv.bool,
            .int32, .sint32, .sfixed32 => dv.int32,
            .int64, .sint64, .sfixed64 => dv.int64,
            .uint32, .fixed32 => dv.uint32,
            .uint64, .fixed64 => dv.uint64,
            .float => dv.float,
            .double => dv.double,
            .string => dv.string,
            .bytes => dv.bytes,
        };
    }
    return switch (comptime scalar) {
        .string, .bytes => []const u8{},
        .bool => false,
        else => 0,
    };
}

// TODO simplify with getScalarDefault
fn isScalarDefault(
    comptime scalar: ScalarType,
    comptime default_value: ?DefaultValue,
    value: metadata.scalarZigType(scalar),
) bool {
    if (comptime default_value) |dv| {
        return switch (comptime scalar) {
            .bool => value == dv.bool,
            .int32, .sint32, .sfixed32 => value == dv.int32,
            .int64, .sint64, .sfixed64 => value == dv.int64,
            .uint32, .fixed32 => value == dv.uint32,
            .uint64, .fixed64 => value == dv.uint64,
            .float => value == dv.float,
            .double => value == dv.double,
            .string => std.mem.eql(u8, value, dv.string),
            .bytes => std.mem.eql(u8, value, dv.bytes),
        };
    }
    return switch (comptime scalar) {
        .string, .bytes => value.len == 0,
        .bool => !value,
        else => value == 0,
    };
}

/// Computes the payload type for a field, assuming the field is set.
fn SetFieldPayloadType(comptime MsgType: type, comptime field_meta: FieldMetadata) type {
    const struct_fields = std.meta.fields(MsgType);
    const StructFieldType = struct_fields[field_meta.field_index].type;

    if (comptime field_meta.oneof_variant) |variant_name| {
        const UnionType = std.meta.Child(StructFieldType); // strip ? from ?union(enum){...}
        inline for (std.meta.fields(UnionType)) |uf| {
            if (comptime std.mem.eql(u8, uf.name, variant_name)) {
                return uf.type;
            }
        }
        @compileError("oneof variant not found in union: " ++ variant_name);
    }

    const info = comptime @typeInfo(StructFieldType);
    if (info == .optional) return info.optional.child;
    return StructFieldType;
}

/// Computes the payload type for a field, without assuming that the field is set.
fn FieldPayloadType(comptime MsgType: type, comptime field_meta: FieldMetadata) type {
    const field_payload_type = SetFieldPayloadType(MsgType, field_meta);

    if (comptime field_meta.kind == .message_field) {
        return ?field_payload_type;
    }
    return field_payload_type;
}

/// Returns the field value.
pub fn getField(
    msg: anytype,
    comptime field_meta: FieldMetadata,
) FieldPayloadType(@TypeOf(msg), field_meta) {
    const struct_fields = std.meta.fields(@TypeOf(msg));
    const field_name = comptime struct_fields[field_meta.field_index].name;

    const field = @field(msg, field_name);

    if (comptime field_meta.oneof_variant) |variant_name| {
        if (field) |active| {
            switch (active) {
                inline else => |payload, tag| {
                    if (comptime std.mem.eql(u8, @tagName(tag), variant_name)) return payload;
                },
            }
        }

        switch (comptime field_meta.kind) { // Return the default value for this variant
            .scalar => |sc| return getScalarDefault(sc.scalar, sc.default_value),
            .enum_field => return field_meta.kind.enum_field.default_value,
            .message_field => return null,
            .list => return .empty,
            .map => return .empty,
        }
    }

    if (field == null) {
        return comptime switch (field_meta.kind) {
            .scalar => |sc| getScalarDefault(sc.scalar, sc.default_value),
            .enum_field => field_meta.kind.enum_field.default_value,
            .message_field => null,
            .list, .map => @compileError("list/map fields are never null"),
        };
    }

    return field;
}

/// Returns the field value, assuming the field is set.
pub fn getSetField(
    msg: anytype,
    comptime field_meta: FieldMetadata,
) !SetFieldPayloadType(@TypeOf(msg), field_meta) {
    const struct_fields = std.meta.fields(@TypeOf(msg));
    const field_name = comptime struct_fields[field_meta.field_index].name;

    const field = @field(msg, field_name);

    if (comptime field_meta.oneof_variant) |variant_name| {
        if (field) |active| {
            switch (active) {
                inline else => |payload, tag| {
                    if (comptime std.mem.eql(u8, @tagName(tag), variant_name)) return payload;
                },
            }
        }
        return error.UnsetField;
    }

    if (comptime @typeInfo(@TypeOf(field)) == .optional) {
        return if (field) |v| v else error.UnsetField;
    }
    return field;
}

/// Returns true if the field is set (i.e. would be written to the wire).
pub fn hasField(msg: anytype, comptime field_meta: FieldMetadata) bool {
    const struct_fields = std.meta.fields(@TypeOf(msg));
    const field_name = comptime struct_fields[field_meta.field_index].name;

    const field = @field(msg, field_name);

    if (comptime field_meta.oneof_variant) |variant_name| {
        if (field) |active| {
            switch (active) {
                inline else => |_, tag| {
                    if (comptime std.mem.eql(u8, @tagName(tag), variant_name)) return true;
                },
            }
        }
        return false;
    }

    return switch (comptime field_meta.kind) {
        .scalar => |sc| switch (comptime sc.presence) {
            .implicit => !isScalarDefault(sc.scalar, sc.default_value, field),
            .explicit, .legacy_required => field != null, // TODO check behavior for required fields
        },
        .enum_field => |ef| switch (comptime ef.presence) {
            .implicit => @intFromEnum(field) != ef.default_value,
            .explicit, .legacy_required => field != null,
        },
        .message_field => field != null,
        .list => field.items.len > 0,
        .map => field.count() > 0,
    };
}

/// Sets the field value, handling oneof vs non-oneof transparently.
///
/// Frees any heap memory owned by the current field value before overwriting it.
pub fn setField(
    msg_ptr: anytype,
    comptime field_meta: FieldMetadata,
    value: SetFieldPayloadType(std.meta.Child(@TypeOf(msg_ptr)), field_meta),
    allocator: std.mem.Allocator,
) void {
    const MsgType = std.meta.Child(@TypeOf(msg_ptr));
    const field_name = comptime std.meta.fields(MsgType)[field_meta.field_index].name;
    if (comptime field_meta.oneof_variant) |variant_name| {
        const field_ptr = &@field(msg_ptr.*, field_name);
        if (field_ptr.*) |active| {
            switch (active) {
                inline else => |payload| deinitElement(payload, allocator),
            }
        }
        const UnionType = comptime std.meta.Child(@TypeOf(field_ptr.*));
        field_ptr.* = @unionInit(UnionType, variant_name, value);
    } else {
        clearField(msg_ptr, field_meta, allocator);
        @field(msg_ptr.*, field_name) = value;
    }
}

/// Frees any heap memory owned by a single field value.
fn deinitElement(value: anytype, allocator: std.mem.Allocator) void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .optional => if (value) |v| deinitElement(v, allocator),
        .pointer => |ptr| switch (ptr.size) {
            .slice => { // string / bytes
                if (ptr.child != u8) @compileError("unexpected slice field type");
                allocator.free(value);
            },
            .one => { // message pointer
                if (@typeInfo(ptr.child) != .@"struct") @compileError("unexpected pointer field type");
                value.deinit(allocator);
                allocator.destroy(value);
            },
            else => @compileError("unexpected pointer field type"),
        },
        .@"struct" => {
            if (comptime @hasField(T, "items")) {
                // std.ArrayList
                for (value.items) |item| deinitElement(item, allocator);
                var list = value;
                list.deinit(allocator);
            } else {
                // Hash map (AutoHashMapUnmanaged / StringHashMapUnmanaged)
                var it = value.iterator();
                while (it.next()) |entry| {
                    deinitElement(entry.key_ptr.*, allocator);
                    deinitElement(entry.value_ptr.*, allocator);
                }
                var m = value;
                m.deinit(allocator);
            }
        },
        .int, .float, .bool, .@"enum" => {}, // scalars / enums own no heap memory
        else => @compileError("unexpected field type: " ++ @typeName(T)),
    }
}

/// Frees any heap memory owned by the field and resets it to its unset / default state.
pub fn clearField(
    msg_ptr: anytype,
    comptime field_meta: FieldMetadata,
    allocator: std.mem.Allocator,
) void {
    const MsgType = std.meta.Child(@TypeOf(msg_ptr));
    const field = comptime std.meta.fields(MsgType)[field_meta.field_index];
    const field_name = comptime field.name;

    if (comptime field_meta.oneof_variant) |variant_name| {
        if (@field(msg_ptr.*, field_name)) |active| {
            switch (active) {
                inline else => |payload, tag| {
                    if (comptime std.mem.eql(u8, @tagName(tag), variant_name)) {
                        deinitElement(payload, allocator);
                        @field(msg_ptr.*, field_name) = null;
                    }
                },
            }
        }
    } else if (hasField(msg_ptr.*, field_meta)) {
        deinitElement(@field(msg_ptr.*, field_name), allocator);
        @field(msg_ptr.*, field_name) = comptime field.defaultValue().?;
    }
}

/// Iterates over every field in a message that is currently "set", calling
/// `callback(context, field_meta, value)` for each one.
///
/// The callback must be a comptime-known function that can accept any `value` type (use
/// `comptime callback: anytype` at the call-site) and must return `anyerror!void`.
pub fn forEachSetField(
    msg: anytype,
    context: anytype,
    comptime callback: anytype,
) !void {
    const MsgType = @TypeOf(msg);

    inline for (MsgType._desc.fields) |field_meta| {
        if (hasField(msg, field_meta)) {
            const field = getSetField(msg, field_meta) catch unreachable;
            try callback(context, field_meta, field);
        }
    }
}
