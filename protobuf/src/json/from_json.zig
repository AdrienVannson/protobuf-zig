const std = @import("std");
const field_access = @import("../_codegen/field_access.zig");
const metadata = @import("../_codegen/metadata.zig");

const ScalarType = metadata.ScalarType;
const FieldMetadata = metadata.FieldMetadata;
const MessageMetadata = metadata.MessageMetadata;

fn intFromJson(val: std.json.Value, comptime int_type: type) !int_type {
    switch (val) {
        .number_string, .string => |s| {
            if (s.len == 0) {
                return error.InvalidJson;
            }
            return std.fmt.parseInt(int_type, s, 10) catch error.InvalidJson;
        },
        else => return error.InvalidJson,
    }
}

fn scalarFromJson(comptime scalar: ScalarType, val: std.json.Value) !metadata.scalarZigType(scalar) {
    switch (scalar) {
        .int32, .sint32, .sfixed32, .uint32, .fixed32, .int64, .sint64, .sfixed64, .uint64, .fixed64 => {
            return intFromJson(val, metadata.scalarZigType(scalar));
        },
        .bool => {
            return switch (val) {
                .bool => |b| b,
                else => error.InvalidJson,
            };
        },
        .float, .double, .string, .bytes => return error.UnsupportedFieldType,
    }
}

fn readScalarField(
    msg: anytype,
    comptime field_meta: FieldMetadata,
    val: std.json.Value,
    allocator: std.mem.Allocator,
) !void {
    if (val == .null) {
        field_access.clearField(msg, field_meta, allocator);
    } else {
        const v = try scalarFromJson(field_meta.kind.scalar.scalar, val);
        field_access.setField(msg, field_meta, v, allocator);
    }
}

/// Returns true when a JSON null should reset the field to its unset state.
/// Returns false for types where null is a meaningful value (google.protobuf.Value,
/// google.protobuf.NullValue), because those need further handling instead.
fn isResetSentinelNullValue(
    comptime field_meta: FieldMetadata,
    val: std.json.Value,
) bool {
    if (val != .null) return false;
    return switch (comptime field_meta.kind) {
        // TODO: return false when child message type is google.protobuf.Value.
        // Blocked: MessageMetadata has no fully_qualified_proto_name field.
        .message_field => true,
        // TODO: return false when enum type is google.protobuf.NullValue.
        // Blocked: MessageMetadata has no fully_qualified_proto_name field.
        .enum_field => true,
        else => true,
    };
}

fn readMessageField(
    msg: anytype,
    comptime field_meta: FieldMetadata,
    val: std.json.Value,
    allocator: std.mem.Allocator,
) !void {
    if (isResetSentinelNullValue(field_meta, val)) {
        field_access.clearField(msg, field_meta, allocator);
        return;
    }
    const obj = switch (val) {
        .object => |o| o,
        else => return error.InvalidJson,
    };
    const existing = field_access.getField(msg.*, field_meta);
    const child_ptr = existing orelse blk: {
        const Child = std.meta.Child(@typeInfo(@TypeOf(existing)).optional.child);
        const p = try allocator.create(Child);
        p.* = .{};
        field_access.setField(msg, field_meta, p, allocator);
        break :blk p;
    };
    try readMessage(child_ptr, &obj, allocator);
}

fn readField(
    msg: anytype,
    comptime field_meta: FieldMetadata,
    val: std.json.Value,
    allocator: std.mem.Allocator,
) !void {
    switch (comptime field_meta.kind) {
        .scalar => try readScalarField(msg, field_meta, val, allocator),
        .enum_field => return error.UnsupportedFieldType,
        .message_field => try readMessageField(msg, field_meta, val, allocator),
        .list => return error.UnsupportedFieldType,
        .map => return error.UnsupportedFieldType,
    }
}

fn readMessage(
    msg: anytype,
    obj: *const std.json.ObjectMap,
    allocator: std.mem.Allocator,
) error{ InvalidJson, UnsupportedFieldType, OutOfMemory }!void {
    const T = std.meta.Child(@TypeOf(msg));

    var it = obj.iterator();
    while (it.next()) |entry| {
        const val = entry.value_ptr.*;

        inline for (T._desc.fields) |field_meta| {
            if (std.mem.eql(u8, entry.key_ptr.*, field_meta.json_name)) {
                try readField(msg, field_meta, val, allocator);
            }
        }
    }
}

pub fn from_json(msg: anytype, json: []const u8, allocator: std.mem.Allocator) !void {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{
        .parse_numbers = false,
    });
    defer parsed.deinit();

    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return error.InvalidJson,
    };

    try readMessage(msg, &obj, allocator);
}
