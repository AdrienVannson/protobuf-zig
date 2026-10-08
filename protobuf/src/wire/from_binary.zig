const std = @import("std");
const binary_reader = @import("binary_reader.zig");
const tag = @import("tag.zig");
const metadata = @import("../_codegen/metadata.zig");
const field_access = @import("../_codegen/field_access.zig");
const deinit = @import("../_codegen/deinit.zig");

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
    allocator: std.mem.Allocator,
    field_ptr: anytype,
    comptime list_meta: anytype,
    wire_type: WireType,
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
            try readMessageField(reader, allocator, p);
            try field_ptr.*.append(allocator, p);
        },
        .enum_type => {
            const Elem = comptime std.meta.Child(@TypeOf(field_ptr.*.items));
            if (wire_type == .length_delimited) {
                // Packed repeated enum.
                try reader.fork();
                while (reader.remainingInScope() > 0) {
                    try field_ptr.*.append(allocator, @as(Elem, @fromBackingInt(try reader.int32())));
                }
                try reader.join();
            } else {
                try field_ptr.*.append(allocator, @as(Elem, @fromBackingInt(try reader.int32())));
            }
        },
    }
}

fn readMapEntry(
    reader: *BinaryReader,
    allocator: std.mem.Allocator,
    map_ptr: anytype,
    comptime map_meta: anytype,
) ReadMessageError!void {
    const MapType = std.meta.Child(@TypeOf(map_ptr));

    const KeyType = @FieldType(MapType.KV, "key");
    var opt_key: ?KeyType = null;
    errdefer deinit.deinitElement(opt_key, allocator);

    const ValueType = @FieldType(MapType.KV, "value");
    var opt_value: ?ValueType = null;
    errdefer deinit.deinitElement(opt_value, allocator);

    try reader.fork();
    while (reader.remainingInScope() > 0) {
        const field_tag = try reader.tag();
        switch (field_tag.number) {
            1 => {
                const k = try readScalar(reader, map_meta.key);
                deinit.deinitElement(opt_key, allocator);
                opt_key = k;
            },
            2 => switch (comptime map_meta.value) {
                .scalar => |sc| {
                    const v = try readScalar(reader, sc);
                    deinit.deinitElement(opt_value, allocator);
                    opt_value = v;
                },
                .enum_type => opt_value = @fromBackingInt(try reader.int32()),
                .message => {
                    // A repeated value field is merged into the previous one.
                    if (opt_value == null) {
                        const p = try allocator.create(std.meta.Child(ValueType));
                        p.* = .{};
                        opt_value = p;
                    }
                    try readMessageField(reader, allocator, opt_value.?);
                },
            },
            else => _ = try reader.skip(field_tag),
        }
    }
    try reader.join();

    if (opt_key == null) opt_key = switch (comptime map_meta.key) {
        .string, .bytes => try allocator.alloc(u8, 0),
        .bool => false,
        else => 0,
    };

    if (opt_value == null) opt_value = switch (comptime map_meta.value) {
        .scalar => |sc| switch (comptime sc) {
            .string, .bytes => try allocator.alloc(u8, 0),
            .bool => false,
            else => 0,
        },
        .message => blk: {
            const p = try allocator.create(std.meta.Child(ValueType));
            p.* = .{};
            break :blk p;
        },
        .enum_type => @as(ValueType, @fromBackingInt(0)),
    };

    const gop = try map_ptr.*.getOrPut(allocator, opt_key.?);
    if (gop.found_existing) {
        // The map keeps its existing key; free the duplicate and the replaced value.
        deinit.deinitElement(opt_key.?, allocator);
        deinit.deinitElement(gop.value_ptr.*, allocator);
    }
    gop.value_ptr.* = opt_value.?;
}

fn readMessageField(reader: *BinaryReader, allocator: std.mem.Allocator, child_ptr: anytype) ReadMessageError!void {
    try reader.fork();
    try readMessage(reader, allocator, child_ptr);
    try reader.join();
}

/// Decodes all fields of msg from the current scope of reader.
fn readMessage(reader: *BinaryReader, allocator: std.mem.Allocator, msg: anytype) ReadMessageError!void {
    const T = std.meta.Child(@TypeOf(msg));

    while (reader.remainingInScope() > 0) {
        const field_tag = try reader.tag();
        const number = field_tag.number;

        var handled = false;

        // TODO: check that the compiler is able to optimize this loop into O(log(n))
        inline for (T._metadata.fields) |field_meta| {
            if (field_meta.number == number) {
                handled = true;
                const field_name = comptime @typeInfo(T).@"struct".field_names[field_meta.field_index];

                switch (field_meta.kind) {
                    .scalar => |sc| {
                        field_access.setField(msg, field_meta, try readScalar(reader, sc.scalar), allocator);
                    },
                    .enum_field => {
                        field_access.setField(msg, field_meta, @fromBackingInt(try reader.int32()), allocator);
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
                        try readMessageField(reader, allocator, child_ptr);
                    },
                    .list => |list_meta| try readListField(reader, allocator, &@field(msg.*, field_name), list_meta, field_tag.wire_type),
                    .map => |map_meta| try readMapEntry(reader, allocator, &@field(msg.*, field_name), map_meta),
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

/// Deserializes a new message of type T from its binary Protocol Buffer
/// representation. The caller owns the result and must `deinit` it.
pub fn fromBinary(comptime T: type, allocator: std.mem.Allocator, data: []const u8) !T {
    var msg: T = .{};
    errdefer msg.deinit(allocator);
    try mergeFromBinary(&msg, allocator, data);
    return msg;
}

/// Decodes a binary Protocol Buffer representation and merges it into msg,
/// following protobuf merge semantics: singular fields are overwritten, repeated
/// fields are appended, map entries are replaced by key, and set sub-messages
/// are merged recursively.
///
/// msg must be a pointer to the message struct (e.g. &my_msg). On error, msg
/// may be partially merged; the caller must still `deinit` it.
pub fn mergeFromBinary(msg: anytype, allocator: std.mem.Allocator, data: []const u8) !void {
    var reader = BinaryReader.init(allocator, data);
    defer reader.deinit();
    try readMessage(&reader, allocator, msg);
    try reader.finish();
}
