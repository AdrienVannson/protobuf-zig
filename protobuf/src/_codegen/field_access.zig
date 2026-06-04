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
            .list => .empty,
            .map => .empty,
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
            // TODO generate implicit enum fields without optional
            .implicit => field != null,
            // .implicit => field != field_meta.kind.enum_field.default_value,
            .explicit, .legacy_required => field != null,
        },
        .message_field => field != null,
        .list => field.items.len > 0,
        .map => false, // TODO
    };
}

/// Sets the field value, handling oneof vs non-oneof transparently.
///
/// For oneof fields: initialises the union to the named variant with `value`.
/// For non-oneof fields: assigns `value` directly (Zig auto-wraps T → ?T when needed).
pub fn setField(
    msg_ptr: anytype,
    comptime field_meta: FieldMetadata,
    value: SetFieldPayloadType(std.meta.Child(@TypeOf(msg_ptr)), field_meta),
) void {
    const MsgType = std.meta.Child(@TypeOf(msg_ptr));
    const field_name = comptime std.meta.fields(MsgType)[field_meta.field_index].name;
    if (comptime field_meta.oneof_variant) |variant_name| {
        const field_ptr = &@field(msg_ptr.*, field_name);
        const UnionType = comptime std.meta.Child(@TypeOf(field_ptr.*));
        field_ptr.* = @unionInit(UnionType, variant_name, value);
    } else {
        @field(msg_ptr.*, field_name) = value;
    }
}

/// Frees any heap memory owned by the field and resets it to its unset / default state.
///
/// Non-oneof string/bytes with explicit presence: frees the old slice, sets to null.
/// Non-oneof string/bytes with implicit presence: frees if the pointer != default ptr, resets to
///   the compile-time default literal.
/// Non-oneof message: calls deinit(allocator) + destroy(allocator), sets to null.
/// Non-oneof other scalar (explicit): sets to null.
/// Non-oneof other scalar (implicit): resets to compile-time default value.
/// Non-oneof enum: sets to null.
/// Non-oneof list: deinits the ArrayList buffer, resets to .empty.
/// Oneof with this named variant active: performs kind-specific cleanup then nulls the union.
/// Oneof with a different variant active: no-op (leaves the other variant untouched).
pub fn clearField(
    msg_ptr: anytype,
    comptime field_meta: FieldMetadata,
    allocator: std.mem.Allocator,
) void {
    _ = msg_ptr;
    _ = field_meta;
    _ = allocator;
    // const MsgType = std.meta.Child(@TypeOf(msg_ptr));
    // const struct_fields = comptime std.meta.fields(MsgType);
    // const field_name = comptime struct_fields[field_meta.field_index].name;
    // if (comptime field_meta.oneof_variant) |variant_name| {
    //     if (@field(msg_ptr.*, field_name)) |active| {
    //         switch (active) {
    //             inline else => |payload, tag| {
    //                 if (comptime std.mem.eql(u8, @tagName(tag), variant_name)) {
    //                     switch (comptime field_meta.kind) {
    //                         .scalar => |sc| {
    //                             if (comptime sc.scalar == .string or sc.scalar == .bytes) {
    //                                 allocator.free(payload);
    //                             }
    //                         },
    //                         .message_field => {
    //                             payload.deinit(allocator);
    //                             allocator.destroy(payload);
    //                         },
    //                         else => {},
    //                     }
    //                     @field(msg_ptr.*, field_name) = null;
    //                 }
    //                 // A different variant is active → leave the union unchanged.
    //             },
    //         }
    //     }
    // } else {
    //     switch (comptime field_meta.kind) {
    //         .scalar => |sc| {
    //             if (comptime sc.scalar == .string or sc.scalar == .bytes) {
    //                 if (comptime sc.presence == .implicit) {
    //                     const cur = @field(msg_ptr.*, field_name);
    //                     const def: []const u8 = comptime struct_fields[field_meta.field_index].defaultValue().?;
    //                     if (cur.ptr != def.ptr) allocator.free(cur);
    //                     @field(msg_ptr.*, field_name) = def;
    //                 } else {
    //                     if (@field(msg_ptr.*, field_name)) |old| allocator.free(old);
    //                     @field(msg_ptr.*, field_name) = null;
    //                 }
    //             } else if (comptime sc.presence == .implicit) {
    //                 @field(msg_ptr.*, field_name) = comptime struct_fields[field_meta.field_index].defaultValue().?;
    //             } else {
    //                 @field(msg_ptr.*, field_name) = null;
    //             }
    //         },
    //         .enum_field => {
    //             @field(msg_ptr.*, field_name) = null;
    //         },
    //         .message_field => {
    //             if (@field(msg_ptr.*, field_name)) |child| {
    //                 child.deinit(allocator);
    //                 allocator.destroy(child);
    //             }
    //             @field(msg_ptr.*, field_name) = null;
    //         },
    //         .list => {
    //             @field(msg_ptr.*, field_name).deinit(allocator);
    //             @field(msg_ptr.*, field_name) = .empty;
    //         },
    //         .map => {},
    //     }
    // }
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
