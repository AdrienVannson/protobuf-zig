const std = @import("std");
const binary_reader = @import("binary_reader.zig");
const tag = @import("tag.zig");
const metadata = @import("../_codegen/metadata.zig");
const field_access = @import("../_codegen/field_access.zig");

const BinaryReader = binary_reader.BinaryReader;
const WireType = tag.WireType;
const ScalarType = metadata.ScalarType;

fn readScalar(reader: *BinaryReader, comptime scalar: ScalarType) !metadata.scalarZigType(scalar) {
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

const ReadMessageError = error{
    UnexpectedEof,
    InvalidVarint,
    InvalidFieldNumber,
    InvalidWireType,
    UnexpectedEgroupTag,
    MismatchedGroupTag,
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
            try readMessageField(reader, p, allocator);
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

fn readMapEntry(
    reader: *BinaryReader,
    map_ptr: anytype,
    comptime map_meta: anytype,
    allocator: std.mem.Allocator,
) ReadMessageError!void {
    const MapType = std.meta.Child(@TypeOf(map_ptr));

    const KeyType = @FieldType(MapType.KV, "key");
    var opt_key: ?KeyType = null;
    errdefer if (opt_key) |k| {
        if (comptime map_meta.key == .string or map_meta.key == .bytes) allocator.free(k);
    };

    const ValueType = @FieldType(MapType.KV, "value");
    var opt_value: ?ValueType = null;
    errdefer if (opt_value) |v| {
        switch (comptime map_meta.value) {
            .scalar => |sc| if (comptime sc == .string or sc == .bytes) allocator.free(v),
            .message => {
                v.deinit(allocator);
                allocator.destroy(v);
            },
            .enum_type => {},
        }
    };

    try reader.fork();
    while (reader.remainingInScope() > 0) {
        const field_tag = try reader.tag();
        switch (field_tag.number) {
            1 => opt_key = try readScalar(reader, map_meta.key),
            2 => switch (comptime map_meta.value) {
                .scalar => |sc| opt_value = try readScalar(reader, sc),
                .enum_type => opt_value = @enumFromInt(try reader.int32()),
                .message => {
                    const Child = std.meta.Child(ValueType);
                    const p = try allocator.create(Child);
                    p.* = .{};
                    errdefer allocator.destroy(p); // TODO also deinit, same problem elsewhere
                    try readMessageField(reader, p, allocator);
                    opt_value = p;
                },
            },
            else => _ = try reader.skip(field_tag),
        }
    }
    try reader.join();

    const key = opt_key orelse switch (comptime map_meta.key) {
        .string, .bytes => try allocator.alloc(u8, 0),
        .bool => false,
        else => 0,
    };

    const value = opt_value orelse switch (comptime map_meta.value) {
        .scalar => |sc| switch (comptime sc) {
            .string, .bytes => try allocator.alloc(u8, 0),
            .bool => false,
            else => 0,
        },
        .message => blk: {
            const Child = std.meta.Child(ValueType);
            const p = try allocator.create(Child);
            p.* = .{};
            break :blk p;
        },
        .enum_type => @as(ValueType, @enumFromInt(0)),
    };

    try map_ptr.*.put(allocator, key, value);
}

fn readMessageField(reader: *BinaryReader, child_ptr: anytype, allocator: std.mem.Allocator) ReadMessageError!void {
    try reader.fork();
    try readMessage(reader, child_ptr, allocator);
    try reader.join();
}

/// Decodes all fields of msg from the current scope of reader.
fn readMessage(reader: *BinaryReader, msg: anytype, allocator: std.mem.Allocator) ReadMessageError!void {
    const T = std.meta.Child(@TypeOf(msg));
    const struct_fields = std.meta.fields(T);

    while (reader.remainingInScope() > 0) {
        const field_tag = try reader.tag();
        const number = field_tag.number;

        var handled = false;

        // TODO: check that the compiler is able to optimize this loop into O(log(n))
        inline for (T._metadata.fields) |field_meta| {
            if (field_meta.number == number) {
                handled = true;
                const field_name = comptime struct_fields[field_meta.field_index].name;

                switch (field_meta.kind) {
                    .scalar => |sc| {
                        field_access.setField(msg, field_meta, try readScalar(reader, sc.scalar), allocator);
                    },
                    .enum_field => {
                        field_access.setField(msg, field_meta, @enumFromInt(try reader.int32()), allocator);
                    },
                    .message_field => {
                        const field = field_access.getField(msg.*, field_meta);
                        const child_ptr = field orelse blk: {
                            // Merge into the existing message if set; otherwise allocate a new one.
                            const Child = std.meta.Child(@typeInfo(@TypeOf(field)).optional.child);
                            const p = try allocator.create(Child);
                            p.* = .{};
                            field_access.setField(msg, field_meta, p, allocator);
                            break :blk p;
                        };
                        try readMessageField(reader, child_ptr, allocator);
                    },
                    .list => |list_meta| try readListField(reader, &@field(msg.*, field_name), list_meta, field_tag.wire_type, allocator),
                    .map => |map_meta| try readMapEntry(reader, &@field(msg.*, field_name), map_meta, allocator),
                }
            }
        }

        if (!handled) {
            const raw = try reader.skip(field_tag);
            const owned = try allocator.dupe(u8, raw);
            errdefer allocator.free(owned);

            const gop = try msg._unknown_fields.getOrPut(allocator, field_tag.number);
            if (!gop.found_existing) gop.value_ptr.* = .empty;
            try gop.value_ptr.append(allocator, .{ .tag = field_tag, .data = owned });
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
