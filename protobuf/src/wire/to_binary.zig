const std = @import("std");
const binary_writer_mod = @import("binary_writer.zig");
const tag_mod = @import("tag.zig");
const metadata_mod = @import("../_codegen/metadata.zig");

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

const WriteMessageError = error{ OutOfMemory, JoinWithoutFork };

fn writeMessageField(bw: *BinaryWriter, comptime number: u32, child: anytype) WriteMessageError!void {
    try bw.tag(number, .length_delimited);
    try bw.fork();
    try writeMessage(bw, child);
    try bw.join();
}

fn writeListField(
    bw: *BinaryWriter,
    list: anytype,
    comptime list_meta: anytype,
    comptime number: u32,
) WriteMessageError!void {
    if (list.items.len == 0) return;
    switch (comptime list_meta.element) {
        .scalar => |sc| {
            if (comptime list_meta.is_packed) {
                try bw.tag(number, .length_delimited);
                try bw.fork();
                for (list.items) |v| try writeScalar(bw, sc, v);
                try bw.join();
            } else {
                for (list.items) |v| {
                    try bw.tag(number, comptime scalarWireType(sc));
                    try writeScalar(bw, sc, v);
                }
            }
        },
        .message => {
            for (list.items) |child_ptr| {
                try writeMessageField(bw, number, child_ptr.*);
            }
        },
        .enum_type => {
            if (comptime list_meta.is_packed) {
                try bw.tag(number, .length_delimited);
                try bw.fork();
                for (list.items) |v| try bw.int32(@intFromEnum(v));
                try bw.join();
            } else {
                for (list.items) |v| {
                    try bw.tag(number, .varint);
                    try bw.int32(@intFromEnum(v));
                }
            }
        },
    }
}

/// Encodes all fields of msg into bw.
///
/// Each FieldMetadata carries a `field_index` pointing into std.meta.fields(T)
/// and an optional `oneof_variant` for oneof members. This decouples the
/// metadata array order from the struct field order, allowing N oneof entries
/// to share a single struct field (the `?union(enum)`).
fn writeMessage(bw: *BinaryWriter, msg: anytype) WriteMessageError!void {
    const T = @TypeOf(msg);
    const struct_fields = std.meta.fields(T);

    inline for (T._desc.fields) |field_meta| {
        const fi = comptime field_meta.field_index;
        const field_name = comptime struct_fields[fi].name;

        if (comptime field_meta.oneof_variant) |variant_name| {
            // Oneof: the struct field is ?union(enum). Check if the active
            // variant matches this metadata entry.
            if (@field(msg, field_name)) |active_union| {
                switch (active_union) {
                    inline else => |payload, tag| {
                        if (comptime std.mem.eql(u8, @tagName(tag), variant_name)) {
                            switch (field_meta.kind) {
                                .scalar => |sc| {
                                    try bw.tag(field_meta.number, comptime scalarWireType(sc.scalar));
                                    try writeScalar(bw, sc.scalar, payload);
                                },
                                else => {},
                            }
                        }
                    },
                }
            }
        } else {
            switch (field_meta.kind) {
                .scalar => |sc| {
                    const ExpectedType = comptime scalarZigType(sc.scalar);
                    const StructFieldType = comptime struct_fields[fi].type;
                    const presence = comptime field_meta.presence;

                    const type_ok = comptime switch (presence) {
                        .implicit => StructFieldType == ExpectedType,
                        .explicit, .legacy_required => StructFieldType == ?ExpectedType,
                    };

                    if (comptime type_ok) {
                        switch (presence) {
                            .implicit => {
                                const value: ExpectedType = @field(msg, field_name);
                                if (!isDefault(sc.scalar, value)) {
                                    try bw.tag(@intCast(field_meta.number), comptime scalarWireType(sc.scalar));
                                    try writeScalar(bw, sc.scalar, value);
                                }
                            },
                            .explicit, .legacy_required => {
                                const opt: ?ExpectedType = @field(msg, field_name);
                                if (opt) |value| {
                                    try bw.tag(@intCast(field_meta.number), comptime scalarWireType(sc.scalar));
                                    try writeScalar(bw, sc.scalar, value);
                                }
                            },
                        }
                    }
                },
                .message_field => {
                    if (@field(msg, field_name)) |child_ptr| {
                        try writeMessageField(bw, field_meta.number, child_ptr.*);
                    }
                },
                .list => |list_meta| try writeListField(bw, @field(msg, field_name), list_meta, field_meta.number),
                .enum_field => {
                    if (@field(msg, field_name)) |value| {
                        try bw.tag(field_meta.number, .varint);
                        try bw.int32(@intFromEnum(value));
                    }
                },
                else => {},
            }
        }
    }
}

/// Serializes a message to its binary Protocol Buffer representation,
/// returning the encoded bytes as a caller-owned slice (freed with allocator).
pub fn to_binary(allocator: std.mem.Allocator, msg: anytype) ![]u8 {
    var bw = BinaryWriter.init(allocator);
    defer bw.deinit();
    try writeMessage(&bw, msg);
    return bw.toOwnedSlice();
}
