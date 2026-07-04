// TODO: fix leaks when updating / setting fields that already exist and need to be freed

const std = @import("std");
const field_access = @import("../_codegen/field_access.zig");
const metadata = @import("../_codegen/metadata.zig");
const Registry = @import("../registry.zig").Registry;

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
    if (isResetSentinelNullValue(msg, field_meta, val)) {
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
    msg: anytype,
    comptime field_meta: FieldMetadata,
    val: std.json.Value,
) bool {
    if (val != .null) return false;
    return switch (comptime field_meta.kind) {
        .message_field => blk: {
            const MsgType = std.meta.Child(@TypeOf(msg));
            const MsgFieldType = std.meta.Child(@typeInfo(field_access.FieldPayloadType(MsgType, field_meta)).optional.child);
            break :blk !comptime std.mem.eql(u8, MsgFieldType._metadata.fully_qualified_proto_name, "google.protobuf.Value");
        },
        // TODO: return false when enum type is google.protobuf.NullValue.
        .enum_field => true,
        else => true,
    };
}

fn readWktValue(msg: anytype, val: std.json.Value, allocator: std.mem.Allocator, registry: *const Registry) !void {
    const KindUnion = @typeInfo(@TypeOf(msg.kind)).optional.child;
    const StructType = std.meta.Child(@FieldType(KindUnion, "struct_value"));
    const ListValueType = std.meta.Child(@FieldType(KindUnion, "list_value"));
    switch (val) {
        .null => msg.kind = .{ .null_value = .NULL_VALUE },
        .bool => |b| msg.kind = .{ .bool_value = b },
        .number_string => |s| msg.kind = .{
            .number_value = std.fmt.parseFloat(f64, s) catch return error.InvalidJson,
        },
        .string => |s| msg.kind = .{ .string_value = try allocator.dupe(u8, s) },
        .array => {
            const lv = try allocator.create(ListValueType);
            lv.* = .{};
            try readWktListValue(lv, val, allocator, registry);
            msg.kind = .{ .list_value = lv };
        },
        .object => {
            const sv = try allocator.create(StructType);
            sv.* = .{};
            try readWktStruct(sv, val, allocator, registry);
            msg.kind = .{ .struct_value = sv };
        },
        else => return error.InvalidJson,
    }
}

fn readWktStruct(msg: anytype, val: std.json.Value, allocator: std.mem.Allocator, registry: *const Registry) !void {
    const obj = switch (val) {
        .object => |o| o,
        else => return error.InvalidJson,
    };
    const ValueType = std.meta.Child(@FieldType(@TypeOf(msg.fields).KV, "value"));
    var it = obj.iterator();
    while (it.next()) |entry| {
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        const v = try allocator.create(ValueType);
        v.* = .{};
        try readMessage(v, entry.value_ptr.*, allocator, registry);
        try msg.fields.put(allocator, key, v);
    }
}

fn readWktListValue(msg: anytype, val: std.json.Value, allocator: std.mem.Allocator, registry: *const Registry) !void {
    const arr = switch (val) {
        .array => |a| a,
        else => return error.InvalidJson,
    };
    const ValueType = std.meta.Child(std.meta.Child(@TypeOf(msg.values.items)));
    for (arr.items) |item| {
        const v = try allocator.create(ValueType);
        v.* = .{};
        try readMessage(v, item, allocator, registry);
        try msg.values.append(allocator, v);
    }
}

fn readWktAny(msg: anytype, val: std.json.Value, allocator: std.mem.Allocator, registry: *const Registry) !void {
    const obj = switch (val) {
        .object => |o| o,
        else => return error.InvalidJson,
    };

    if (obj.count() == 0) return;

    const type_entry = obj.get("@type") orelse {
        return error.InvalidJson;
    };
    const type_url = switch (type_entry) {
        .string => |s| s,
        else => return error.InvalidJson,
    };

    const type_name = blk: {
        const i = std.mem.lastIndexOfScalar(u8, type_url, '/') orelse break :blk type_url;
        break :blk type_url[i + 1 ..];
    };
    const mt = registry._getMessageType(type_name) orelse return error.UnknownAnyType;

    const ptr = try mt.create(allocator);
    defer {
        mt.deinit(ptr, allocator);
        mt.destroy(ptr, allocator);
    }

    var inner_json: []const u8 = undefined;

    if (mt.has_custom_json_encoding) {
        const value_entry = obj.get("value") orelse return error.InvalidJson;
        inner_json = try std.json.Stringify.valueAlloc(allocator, value_entry, .{});
    } else {
        var inner_obj = try obj.clone(allocator);
        defer inner_obj.deinit(allocator);
        _ = inner_obj.orderedRemove("@type");

        inner_json = try std.json.Stringify.valueAlloc(
            allocator,
            std.json.Value{ .object = inner_obj },
            .{},
        );
    }

    // TODO: see if we can avoid going back to string values
    defer allocator.free(inner_json);
    try mt.fromJson(ptr, inner_json, allocator, registry);

    msg.type_url = try allocator.dupe(u8, type_url);
    msg.value = try mt.toBinary(ptr, allocator);
}

fn tryReadWktValue(msg: anytype, val: std.json.Value, allocator: std.mem.Allocator, registry: *const Registry) !bool {
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
    if (comptime std.mem.eql(u8, name, "google.protobuf.Value")) {
        try readWktValue(msg, val, allocator, registry);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.Struct")) {
        try readWktStruct(msg, val, allocator, registry);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.ListValue")) {
        try readWktListValue(msg, val, allocator, registry);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.Any")) {
        try readWktAny(msg, val, allocator, registry);
        return true;
    }
    return false;
}

fn tryReadWkt(msg: anytype, val: std.json.Value, allocator: std.mem.Allocator, registry: *const Registry) !bool {
    return try tryReadWktValue(msg, val, allocator, registry);
}

fn readMessageField(
    msg: anytype,
    comptime field_meta: FieldMetadata,
    val: std.json.Value,
    allocator: std.mem.Allocator,
    registry: *const Registry,
) !void {
    if (isResetSentinelNullValue(msg, field_meta, val)) {
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

    try readMessage(child_ptr, val, allocator, registry);
}

fn readListField(
    msg: anytype,
    comptime field_meta: FieldMetadata,
    val: std.json.Value,
    allocator: std.mem.Allocator,
    registry: *const Registry,
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
                try readMessage(p, item, allocator, registry);
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
    registry: *const Registry,
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
                try readMessage(p, entry.value_ptr.*, allocator, registry);
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
    registry: *const Registry,
) !void {
    switch (comptime field_meta.kind) {
        .scalar => try readScalarField(msg, field_meta, val, allocator),
        .enum_field => try readEnumField(msg, field_meta, val, allocator),
        .message_field => try readMessageField(msg, field_meta, val, allocator, registry),
        .list => try readListField(msg, field_meta, val, allocator, registry),
        .map => try readMapField(msg, field_meta, val, allocator, registry),
    }
}

fn readMessage(
    msg: anytype,
    json_value: std.json.Value,
    allocator: std.mem.Allocator,
    registry: *const Registry,
) anyerror!void {
    const T = std.meta.Child(@TypeOf(msg));

    if (try tryReadWkt(msg, json_value, allocator, registry)) return;

    const obj = switch (json_value) {
        .object => |o| o,
        else => return error.InvalidJson,
    };

    var it = obj.iterator();
    while (it.next()) |entry| {
        const val = entry.value_ptr.*;

        inline for (T._metadata.fields) |field_meta| {
            if (std.mem.eql(u8, entry.key_ptr.*, field_meta.json_name)) {
                try readField(msg, field_meta, val, allocator, registry);
            }
        }

        // TODO unknown fields
    }
}

pub fn from_json(msg: anytype, json: []const u8, allocator: std.mem.Allocator, registry: *const Registry) !void {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{
        .parse_numbers = false,
    });
    defer parsed.deinit();

    try readMessage(msg, parsed.value, allocator, registry);
}
