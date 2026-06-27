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

fn boolFromJson(val: std.json.Value) !bool {
    return switch (val) {
        .bool => |b| b,
        else => error.InvalidJson,
    };
}

fn floatFromJson(val: std.json.Value, comptime T: type) !T {
    return switch (val) {
        .number_string => |s| std.fmt.parseFloat(T, s) catch error.InvalidJson,
        .string => |s| {
            if (std.mem.eql(u8, s, "NaN")) return std.math.nan(T);
            if (std.mem.eql(u8, s, "Infinity")) return std.math.inf(T);
            if (std.mem.eql(u8, s, "-Infinity")) return -std.math.inf(T);
            return std.fmt.parseFloat(T, s) catch error.InvalidJson;
        },
        else => error.InvalidJson,
    };
}

fn stringFromJson(val: std.json.Value, allocator: std.mem.Allocator) ![]const u8 {
    return switch (val) {
        .string => |s| try allocator.dupe(u8, s),
        else => return error.InvalidJson,
    };
}

fn bytesFromJson(val: std.json.Value, allocator: std.mem.Allocator) ![]const u8 {
    const s = switch (val) {
        .string => |s| s,
        else => return error.InvalidJson,
    };
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(s) catch return error.InvalidJson;
    const buf = try allocator.alloc(u8, decoded_len);
    std.base64.standard.Decoder.decode(buf, s) catch return error.InvalidJson;
    return buf;
}

fn enumFromJson(comptime EnumType: type, val: std.json.Value) !EnumType {
    switch (val) {
        .string => |s| {
            inline for (@typeInfo(EnumType).@"enum".fields) |f| {
                // TODO the proto name may be different from the local name
                if (std.mem.eql(u8, s, f.name)) return @enumFromInt(f.value);
            }
            return error.InvalidJson;
        },
        .number_string => |s| {
            const n = std.fmt.parseInt(std.meta.Tag(EnumType), s, 10) catch return error.InvalidJson;
            return @enumFromInt(n);
        },
        else => return error.InvalidJson,
    }
}

fn scalarFromJson(comptime scalar: ScalarType, val: std.json.Value, allocator: std.mem.Allocator) !metadata.scalarZigType(scalar) {
    switch (scalar) {
        .int32, .sint32, .sfixed32, .uint32, .fixed32, .int64, .sint64, .sfixed64, .uint64, .fixed64 => {
            return intFromJson(val, metadata.scalarZigType(scalar));
        },
        .bool => {
            return boolFromJson(val);
        },
        .float => {
            return floatFromJson(val, f32);
        },
        .double => {
            return floatFromJson(val, f64);
        },
        .string => {
            return stringFromJson(val, allocator);
        },
        .bytes => {
            return bytesFromJson(val, allocator);
        },
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
        const v = try scalarFromJson(field_meta.kind.scalar.scalar, val, allocator);
        field_access.setField(msg, field_meta, v, allocator);
    }
}

fn readEnumField(
    msg: anytype,
    comptime field_meta: FieldMetadata,
    val: std.json.Value,
    allocator: std.mem.Allocator,
) !void {
    if (isResetSentinelNullValue(field_meta, val)) {
        field_access.clearField(msg, field_meta, allocator);
        return;
    }
    const EnumType = field_access.FieldPayloadType(std.meta.Child(@TypeOf(msg)), field_meta);
    const v = try enumFromJson(EnumType, val);
    field_access.setField(msg, field_meta, v, allocator);
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

fn tryReadWktValue(msg: anytype, val: std.json.Value, allocator: std.mem.Allocator) !bool {
    const name = comptime std.meta.Child(@TypeOf(msg))._metadata.fully_qualified_proto_name;
    if (comptime std.mem.eql(u8, name, "google.protobuf.DoubleValue")) {
        msg.value = try floatFromJson(val, f64);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.FloatValue")) {
        msg.value = try floatFromJson(val, f32);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.Int64Value")) {
        msg.value = try intFromJson(val, i64);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.UInt64Value")) {
        msg.value = try intFromJson(val, u64);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.Int32Value")) {
        msg.value = try intFromJson(val, i32);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.UInt32Value")) {
        msg.value = try intFromJson(val, u32);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.BoolValue")) {
        msg.value = try boolFromJson(val);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.StringValue")) {
        msg.value = try stringFromJson(val, allocator);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.BytesValue")) {
        msg.value = try bytesFromJson(val, allocator);
        return true;
    }
    return false;
}

fn tryReadWkt(msg: anytype, val: std.json.Value, allocator: std.mem.Allocator) !bool {
    return try tryReadWktValue(msg, val, allocator);
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
    const existing = field_access.getField(msg.*, field_meta);
    const child_ptr = existing orelse blk: {
        const Child = std.meta.Child(@typeInfo(@TypeOf(existing)).optional.child);
        const p = try allocator.create(Child);
        p.* = .{};
        field_access.setField(msg, field_meta, p, allocator);
        break :blk p;
    };

    try readMessage(child_ptr, val, allocator);
}

fn readListField(
    msg: anytype,
    comptime field_meta: FieldMetadata,
    val: std.json.Value,
    allocator: std.mem.Allocator,
) !void {
    if (val == .null) {
        field_access.clearField(msg, field_meta, allocator);
        return;
    }
    const arr = switch (val) {
        .array => |a| a,
        else => return error.InvalidJson,
    };

    const list_ptr = field_access.getFieldPtr(msg, field_meta);

    for (arr.items) |item| {
        switch (comptime field_meta.kind.list.element) {
            .scalar => |sc| {
                const v = try scalarFromJson(sc, item, allocator);
                try list_ptr.append(allocator, v);
            },
            .message => {
                const ChildMsg = std.meta.Child(@typeInfo(@TypeOf(list_ptr.items)).pointer.child);
                const p = try allocator.create(ChildMsg);
                p.* = .{};
                try list_ptr.append(allocator, p);
                try readMessage(p, item, allocator);
            },
            .enum_type => {
                const EnumType = std.meta.Child(@TypeOf(list_ptr.items));
                const v = try enumFromJson(EnumType, item);
                try list_ptr.append(allocator, v);
            },
        }
    }
}

fn readMapField(
    msg: anytype,
    comptime field_meta: FieldMetadata,
    val: std.json.Value,
    allocator: std.mem.Allocator,
) !void {
    if (val == .null) {
        field_access.clearField(msg, field_meta, allocator);
        return;
    }
    const obj = switch (val) {
        .object => |o| o,
        else => return error.InvalidJson,
    };

    const map_ptr = field_access.getFieldPtr(msg, field_meta);
    const MapType = @TypeOf(map_ptr.*);
    const ValueType = @FieldType(MapType.KV, "value");
    const KeyType = @FieldType(MapType.KV, "key");

    var it = obj.iterator();
    while (it.next()) |entry| {
        const key_str = entry.key_ptr.*;
        const key: KeyType = switch (comptime field_meta.kind.map.key) {
            .string => try allocator.dupe(u8, key_str),
            .bool => if (std.mem.eql(u8, key_str, "true")) true else if (std.mem.eql(u8, key_str, "false")) false else return error.InvalidJson,
            inline else => |sc| std.fmt.parseInt(metadata.scalarZigType(sc), key_str, 10) catch return error.InvalidJson,
        };
        errdefer if (comptime field_meta.kind.map.key == .string) allocator.free(key);

        switch (comptime field_meta.kind.map.value) {
            .scalar => |sc| {
                const v = try scalarFromJson(sc, entry.value_ptr.*, allocator);
                try map_ptr.put(allocator, key, v);
            },
            .enum_type => {
                const v = try enumFromJson(ValueType, entry.value_ptr.*);
                try map_ptr.put(allocator, key, v);
            },
            .message => {
                const Child = std.meta.Child(ValueType);
                const p = try allocator.create(Child);
                p.* = .{};
                try readMessage(p, entry.value_ptr.*, allocator);
                try map_ptr.put(allocator, key, p);
            },
        }
    }
}

fn readField(
    msg: anytype,
    comptime field_meta: FieldMetadata,
    val: std.json.Value,
    allocator: std.mem.Allocator,
) !void {
    switch (comptime field_meta.kind) {
        .scalar => try readScalarField(msg, field_meta, val, allocator),
        .enum_field => try readEnumField(msg, field_meta, val, allocator),
        .message_field => try readMessageField(msg, field_meta, val, allocator),
        .list => try readListField(msg, field_meta, val, allocator),
        .map => try readMapField(msg, field_meta, val, allocator),
    }
}

fn readMessage(
    msg: anytype,
    json_value: std.json.Value,
    allocator: std.mem.Allocator,
) error{ InvalidJson, UnsupportedFieldType, OutOfMemory }!void {
    const T = std.meta.Child(@TypeOf(msg));

    if (try tryReadWkt(msg, json_value, allocator)) return;

    const obj = switch (json_value) {
        .object => |o| o,
        else => return error.InvalidJson,
    };

    var it = obj.iterator();
    while (it.next()) |entry| {
        const val = entry.value_ptr.*;

        inline for (T._metadata.fields) |field_meta| {
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

    try readMessage(msg, parsed.value, allocator);
}
