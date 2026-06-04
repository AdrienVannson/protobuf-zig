const std = @import("std");
const metadata = @import("metadata.zig");

pub const FieldMetadata = metadata.FieldMetadata;
const FieldMetadataKind = metadata.FieldMetadataKind;
const ScalarType = metadata.ScalarType;
const DefaultValue = metadata.DefaultValue;

fn isDefault(
    comptime scalar: ScalarType,
    comptime default_value: ?DefaultValue,
    value: metadata.scalarZigType(scalar),
) bool {
    if (comptime default_value) |dv| {
        return switch (comptime scalar) {
            .bool => value == dv.bool,
            .string => std.mem.eql(u8, value, dv.string),
            .bytes => std.mem.eql(u8, value, dv.bytes),
            .float => value == dv.float,
            .double => value == dv.double,
            .int32, .sint32, .sfixed32 => value == dv.int32,
            .int64, .sint64, .sfixed64 => value == dv.int64,
            .uint32, .fixed32 => value == dv.uint32,
            .uint64, .fixed64 => value == dv.uint64,
        };
    }
    return switch (comptime scalar) {
        .string, .bytes => value.len == 0,
        .bool => !value,
        else => value == 0,
    };
}

/// Computes the payload type for a field (the inner value type, not the struct field type).
///
/// For oneof fields, finds the union variant type by matching `field_meta.oneof_variant` against
/// the union tags in `?union(enum){...}`.
/// For non-oneof optional fields (?T): returns T.
/// For non-oneof non-optional fields (implicit-presence scalars): returns T directly.
pub fn FieldPayloadType(comptime MsgType: type, comptime field_meta: FieldMetadata) type {
    const struct_fields = std.meta.fields(MsgType);
    const StructFieldType = struct_fields[field_meta.field_index].type;
    if (comptime field_meta.oneof_variant) |variant_name| {
        const UnionType = std.meta.Child(StructFieldType); // strip ? from ?union(enum){...}
        inline for (std.meta.fields(UnionType)) |uf| {
            if (comptime std.mem.eql(u8, uf.name, variant_name)) return uf.type;
        }
        @compileError("oneof variant not found in union: " ++ variant_name);
    } else {
        const info = comptime @typeInfo(StructFieldType);
        if (info == .optional) return info.optional.child;
        return StructFieldType;
    }
}

/// Returns the field value as `?T` (where T is `FieldPayloadType`).
///
/// For oneof fields: returns the variant's payload if the named variant is active, else null.
/// For non-oneof optional fields: returns the optional field value (null if unset).
/// For non-oneof non-optional (implicit-presence) fields: always returns a value (Zig coerces T → ?T).
pub fn getField(
    msg: anytype,
    comptime field_meta: FieldMetadata,
) ?FieldPayloadType(@TypeOf(msg), field_meta) {
    const struct_fields = std.meta.fields(@TypeOf(msg));
    const field_name = comptime struct_fields[field_meta.field_index].name;
    if (comptime field_meta.oneof_variant) |variant_name| {
        if (@field(msg, field_name)) |active| {
            switch (active) {
                inline else => |payload, tag| {
                    if (comptime std.mem.eql(u8, @tagName(tag), variant_name)) return payload;
                },
            }
        }
        return null;
    } else {
        return @field(msg, field_name); // ?T returned directly; T coerces to ?T
    }
}

/// Returns true if the field is "set" (i.e. would be written to the wire).
pub fn hasField(msg: anytype, comptime field_meta: FieldMetadata) bool {
    const struct_fields = std.meta.fields(@TypeOf(msg));
    const field_name = comptime struct_fields[field_meta.field_index].name;
    if (comptime field_meta.oneof_variant) |variant_name| {
        if (@field(msg, field_name)) |active| {
            switch (active) {
                inline else => |_, tag| {
                    if (comptime std.mem.eql(u8, @tagName(tag), variant_name)) return true;
                },
            }
        }
        return false;
    } else {
        return switch (comptime field_meta.kind) {
            .scalar => |sc| switch (comptime sc.presence) {
                .implicit => !isDefault(sc.scalar, sc.default_value, @field(msg, field_name)),
                .explicit, .legacy_required => @field(msg, field_name) != null,
            },
            .enum_field, .message_field => @field(msg, field_name) != null,
            .list => @field(msg, field_name).items.len > 0,
            .map => false,
        };
    }
}

/// Sets the field value, handling oneof vs non-oneof transparently.
///
/// For oneof fields: initialises the union to the named variant with `value`.
/// For non-oneof fields: assigns `value` directly (Zig auto-wraps T → ?T when needed).
pub fn setField(
    msg_ptr: anytype,
    comptime field_meta: FieldMetadata,
    value: FieldPayloadType(std.meta.Child(@TypeOf(msg_ptr)), field_meta),
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
    const MsgType = std.meta.Child(@TypeOf(msg_ptr));
    const struct_fields = comptime std.meta.fields(MsgType);
    const field_name = comptime struct_fields[field_meta.field_index].name;
    if (comptime field_meta.oneof_variant) |variant_name| {
        if (@field(msg_ptr.*, field_name)) |active| {
            switch (active) {
                inline else => |payload, tag| {
                    if (comptime std.mem.eql(u8, @tagName(tag), variant_name)) {
                        switch (comptime field_meta.kind) {
                            .scalar => |sc| {
                                if (comptime sc.scalar == .string or sc.scalar == .bytes) {
                                    allocator.free(payload);
                                }
                            },
                            .message_field => {
                                payload.deinit(allocator);
                                allocator.destroy(payload);
                            },
                            else => {},
                        }
                        @field(msg_ptr.*, field_name) = null;
                    }
                    // A different variant is active → leave the union unchanged.
                },
            }
        }
    } else {
        switch (comptime field_meta.kind) {
            .scalar => |sc| {
                if (comptime sc.scalar == .string or sc.scalar == .bytes) {
                    if (comptime sc.presence == .implicit) {
                        const cur = @field(msg_ptr.*, field_name);
                        const def: []const u8 = comptime struct_fields[field_meta.field_index].defaultValue().?;
                        if (cur.ptr != def.ptr) allocator.free(cur);
                        @field(msg_ptr.*, field_name) = def;
                    } else {
                        if (@field(msg_ptr.*, field_name)) |old| allocator.free(old);
                        @field(msg_ptr.*, field_name) = null;
                    }
                } else if (comptime sc.presence == .implicit) {
                    @field(msg_ptr.*, field_name) = comptime struct_fields[field_meta.field_index].defaultValue().?;
                } else {
                    @field(msg_ptr.*, field_name) = null;
                }
            },
            .enum_field => {
                @field(msg_ptr.*, field_name) = null;
            },
            .message_field => {
                if (@field(msg_ptr.*, field_name)) |child| {
                    child.deinit(allocator);
                    allocator.destroy(child);
                }
                @field(msg_ptr.*, field_name) = null;
            },
            .list => {
                @field(msg_ptr.*, field_name).deinit(allocator);
                @field(msg_ptr.*, field_name) = .empty;
            },
            .map => {},
        }
    }
}

/// For message fields: returns the existing `*MessageType` pointer if already set (enabling merge
/// semantics), or allocates a new zeroed message, stores it, and returns the new pointer.
///
/// For oneof message fields: checks if the named variant is already active and returns its
/// pointer; otherwise allocates, initialises the union variant, and returns the pointer.
/// For non-oneof message fields (?*Child): returns the existing pointer or allocates a new one.
///
/// Replaces the readMessageField helper in from_binary.zig.
pub fn getOrCreateMessageField(
    msg_ptr: anytype,
    comptime field_meta: FieldMetadata,
    allocator: std.mem.Allocator,
) !FieldPayloadType(std.meta.Child(@TypeOf(msg_ptr)), field_meta) {
    const MsgType = std.meta.Child(@TypeOf(msg_ptr));
    const field_name = comptime std.meta.fields(MsgType)[field_meta.field_index].name;
    const PtrType = FieldPayloadType(MsgType, field_meta); // *MessageType
    const Child = std.meta.Child(PtrType); // MessageType
    if (comptime field_meta.oneof_variant) |variant_name| {
        if (@field(msg_ptr.*, field_name)) |active| {
            switch (active) {
                inline else => |payload, tag| {
                    if (comptime std.mem.eql(u8, @tagName(tag), variant_name)) return payload;
                },
            }
        }
        const p = try allocator.create(Child);
        p.* = .{};
        const field_ptr = &@field(msg_ptr.*, field_name);
        const UnionType = comptime std.meta.Child(@TypeOf(field_ptr.*));
        field_ptr.* = @unionInit(UnionType, variant_name, p);
        return p;
    } else {
        const field_ptr = &@field(msg_ptr.*, field_name);
        if (field_ptr.*) |existing| return existing;
        const p = try allocator.create(Child);
        p.* = .{};
        field_ptr.* = p;
        return p;
    }
}

/// Iterates over every field in a message that is currently "set", calling
/// `callback(context, field_meta, value)` for each one.
///
/// For scalar / enum / message fields: `value` is the inner payload (the type returned by
///   `getField`, e.g. `i32`, `MyEnum`, `*MyMessage`).
/// For list fields: `value` is the whole `std.ArrayList(T)`, since the list IS the payload.
/// Map fields and unset fields are skipped.
///
/// The callback must be a comptime-known function that can accept any `value` type (use
/// `comptime callback: anytype` at the call-site) and must return `anyerror!void`.
pub fn forEachSetField(
    msg: anytype,
    context: anytype,
    comptime callback: anytype,
) !void {
    const MsgType = @TypeOf(msg);
    const struct_fields = std.meta.fields(MsgType);
    inline for (MsgType._desc.fields) |field_meta| {
        if (hasField(msg, field_meta)) {
            if (comptime field_meta.kind == .list) {
                const field_name = comptime struct_fields[field_meta.field_index].name;
                try callback(context, field_meta, @field(msg, field_name));
            } else if (comptime field_meta.kind != .map) {
                try callback(context, field_meta, getField(msg, field_meta).?);
            }
        }
    }
}
