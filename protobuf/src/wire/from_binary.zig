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
                        if (comptime field_meta.oneof_variant) |variant| {
                            const field_ptr = &@field(msg.*, field_name);
                            const Union = comptime std.meta.Child(@TypeOf(field_ptr.*));
                            field_ptr.* = @unionInit(Union, variant, try readScalar(reader, sc.scalar));
                        } else {
                            if (comptime (sc.scalar == .string or sc.scalar == .bytes) and
                                field_meta.presence != .implicit)
                            {
                                if (@field(msg.*, field_name)) |old| allocator.free(old);
                            }
                            @field(msg.*, field_name) = try readScalar(reader, sc.scalar);
                        }
                    },
                    .enum_field => {
                        @field(msg.*, field_name) = @enumFromInt(try reader.int32());
                    },
                    .message_field => try readMessageField(reader, &@field(msg.*, field_name), allocator),
                    .list => |list_meta| try readListField(reader, &@field(msg.*, field_name), list_meta, tag.wire_type, allocator),
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
