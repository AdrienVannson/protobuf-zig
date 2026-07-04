const std = @import("std");
const field_access = @import("../_codegen/field_access.zig");
const metadata = @import("../_codegen/metadata.zig");
const Registry = @import("../registry.zig").Registry;

const ScalarType = metadata.ScalarType;
const FieldMetadata = metadata.FieldMetadata;

const JsonContext = struct {
    json_writter: *std.json.Stringify,
    allocator: std.mem.Allocator,
    registry: *const Registry,
};

fn writeScalar(ctx: *const JsonContext, comptime scalar: ScalarType, value: anytype) !void {
    switch (scalar) {
        .int32, .sint32, .sfixed32 => try ctx.json_writter.write(value),
        .uint32, .fixed32 => try ctx.json_writter.write(value),
        .bool => try ctx.json_writter.write(value),
        .int64, .sint64, .sfixed64, .uint64, .fixed64 => {
            var buf: [20]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
            try ctx.json_writter.write(s);
        },
        .float, .double => {
            if (std.math.isNan(value)) {
                try ctx.json_writter.write("NaN");
            } else if (std.math.isInf(value)) {
                if (value > 0) {
                    try ctx.json_writter.write("Infinity");
                } else {
                    try ctx.json_writter.write("-Infinity");
                }
            } else {
                try ctx.json_writter.write(value);
            }
        },
        .string => try ctx.json_writter.write(value),
        .bytes => {
            const encoded_len = std.base64.standard.Encoder.calcSize(value.len);
            const buf = try ctx.allocator.alloc(u8, encoded_len);
            defer ctx.allocator.free(buf);
            const encoded = std.base64.standard.Encoder.encode(buf, value);
            try ctx.json_writter.write(encoded);
        },
    }
}

fn writeEnum(ctx: *const JsonContext, value: anytype) !void {
    const int_val = @intFromEnum(value);
    inline for (@typeInfo(@TypeOf(value)).@"enum".fields) |f| {
        if (int_val == f.value) {
            // TODO: the proto name may be different from the local name
            try ctx.json_writter.write(f.name);
            return;
        }
    }
    try ctx.json_writter.write(int_val);
}

fn writeList(ctx: *const JsonContext, comptime list_meta: anytype, list: anytype) !void {
    try ctx.json_writter.beginArray();
    for (list.items) |item| {
        switch (comptime list_meta.element) {
            .scalar => |sc| try writeScalar(ctx, sc, item),
            .message => try writeMessage(ctx, item.*),
            .enum_type => try writeEnum(ctx, item),
        }
    }
    try ctx.json_writter.endArray();
}

fn writeMap(ctx: *const JsonContext, comptime map_meta: anytype, map: anytype) !void {
    try ctx.json_writter.beginObject();
    var it = map.iterator();
    while (it.next()) |entry| {
        switch (comptime map_meta.key) {
            .string => try ctx.json_writter.objectField(entry.key_ptr.*),
            .bool => try ctx.json_writter.objectField(if (entry.key_ptr.*) "true" else "false"),
            else => {
                var buf: [20]u8 = undefined;
                const s = std.fmt.bufPrint(&buf, "{d}", .{entry.key_ptr.*}) catch unreachable;
                try ctx.json_writter.objectField(s);
            },
        }
        switch (comptime map_meta.value) {
            .scalar => |sc| try writeScalar(ctx, sc, entry.value_ptr.*),
            .message => try writeMessage(ctx, entry.value_ptr.*.*),
            .enum_type => try writeEnum(ctx, entry.value_ptr.*),
        }
    }
    try ctx.json_writter.endObject();
}

fn writeFieldValue(
    ctx: *const JsonContext,
    comptime field_meta: FieldMetadata,
    value: anytype,
) !void {
    switch (comptime field_meta.kind) {
        .scalar => |sc| try writeScalar(ctx, sc.scalar, value),
        .enum_field => try writeEnum(ctx, value),
        .message_field => try writeMessage(ctx, value.*),
        .list => |list_meta| try writeList(ctx, list_meta, value),
        .map => |map_meta| try writeMap(ctx, map_meta, value),
    }
}

fn writeFieldCallback(ctx: *const JsonContext, comptime field_meta: FieldMetadata, value: anytype) !void {
    try ctx.json_writter.objectField(field_meta.json_name);
    try writeFieldValue(ctx, field_meta, value);
}

fn writeWktValue(ctx: *const JsonContext, msg: anytype) error{ OutOfMemory, WriteFailed }!void {
    if (msg.kind) |kind| {
        switch (kind) {
            .null_value => try ctx.json_writter.write(null),
            .bool_value => |v| try writeScalar(ctx, .bool, v),
            .number_value => |v| try writeScalar(ctx, .double, v),
            .string_value => |v| try writeScalar(ctx, .string, v),
            .struct_value => |v| try writeWktStruct(ctx, v.*),
            .list_value => |v| try writeWktListValue(ctx, v.*),
        }
    } else {
        // TODO: check, add parameter to control
        try ctx.json_writter.write(null);
    }
}

fn writeWktStruct(ctx: *const JsonContext, msg: anytype) !void {
    try ctx.json_writter.beginObject();
    var it = msg.fields.iterator();
    while (it.next()) |entry| {
        try ctx.json_writter.objectField(entry.key_ptr.*);
        try writeWktValue(ctx, entry.value_ptr.*.*);
    }
    try ctx.json_writter.endObject();
}

fn writeWktListValue(ctx: *const JsonContext, msg: anytype) !void {
    try ctx.json_writter.beginArray();
    for (msg.values.items) |item| {
        try writeWktValue(ctx, item.*);
    }
    try ctx.json_writter.endArray();
}

fn writeWktAny(ctx: *const JsonContext, msg: anytype) anyerror!void {
    const w = ctx.json_writter;

    // An empty Any (no type) serializes to `{}`.
    if (msg.type_url.len == 0) {
        try w.beginObject();
        try w.endObject();
        return;
    }

    const type_name = blk: {
        const i = std.mem.lastIndexOfScalar(u8, msg.type_url, '/') orelse break :blk msg.type_url;
        break :blk msg.type_url[i + 1 ..];
    };
    const mt = ctx.registry._getMessageType(type_name) orelse return error.UnknownAnyType;

    const ptr = try mt.create(ctx.allocator);
    defer mt.destroy(ptr, ctx.allocator);
    try mt.fromBinary(ptr, msg.value, ctx.allocator);
    defer mt.deinit(ptr, ctx.allocator);

    const inner = try mt.toJson(ptr, ctx.allocator, ctx.registry);
    defer ctx.allocator.free(inner);

    // Emit `{"@type":<type_url>, ...}` as a single raw value so the
    // surrounding writer keeps its punctuation state correct.
    try w.beginWriteRaw();
    const out = w.writer;
    try out.writeAll("{\"@type\":");
    try std.json.Stringify.encodeJsonString(msg.type_url, .{}, out);
    if (mt.has_custom_json_encoding) {
        // The packed type has its own non-flattened JSON form (a string for
        // wrappers, an object for Struct/Value/ListValue/Any, ...), so it's
        // nested under a `value` member rather than spliced into this object.
        try out.writeAll(",\"value\":");
        try out.writeAll(inner);
        try out.writeByte('}');
    } else if (std.mem.eql(u8, inner, "{}")) {
        try out.writeByte('}');
    } else {
        // The regular Any form requires the packed message to render as an object.
        if (inner.len == 0 or inner[0] != '{') return error.UnsupportedAnyType;
        try out.writeByte(',');
        // inner[1..] drops the opening `{`, keeping `<fields>}`.
        try out.writeAll(inner[1..]);
    }
    w.endWriteRaw();
}

fn tryWriteWkt(ctx: *const JsonContext, msg: anytype) !bool {
    const name = comptime @TypeOf(msg)._metadata.fully_qualified_proto_name;
    if (comptime std.mem.eql(u8, name, "google.protobuf.DoubleValue")) {
        try writeScalar(ctx, .double, msg.value);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.FloatValue")) {
        try writeScalar(ctx, .float, msg.value);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.Int64Value")) {
        try writeScalar(ctx, .int64, msg.value);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.UInt64Value")) {
        try writeScalar(ctx, .uint64, msg.value);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.Int32Value")) {
        try writeScalar(ctx, .int32, msg.value);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.UInt32Value")) {
        try writeScalar(ctx, .uint32, msg.value);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.BoolValue")) {
        try writeScalar(ctx, .bool, msg.value);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.StringValue")) {
        try writeScalar(ctx, .string, msg.value);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.BytesValue")) {
        try writeScalar(ctx, .bytes, msg.value);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.Value")) {
        try writeWktValue(ctx, msg);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.Struct")) {
        try writeWktStruct(ctx, msg);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.ListValue")) {
        try writeWktListValue(ctx, msg);
        return true;
    }
    if (comptime std.mem.eql(u8, name, "google.protobuf.Any")) {
        try writeWktAny(ctx, msg);
        return true;
    }
    return false;
}

fn writeMessage(ctx: *const JsonContext, msg: anytype) anyerror!void {
    if (try tryWriteWkt(ctx, msg)) return;
    try ctx.json_writter.beginObject();
    try field_access.forEachSetField(msg, ctx, writeFieldCallback);
    try ctx.json_writter.endObject();
}

pub fn to_json(allocator: std.mem.Allocator, msg: anytype, registry: *const Registry) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();

    var json_writter: std.json.Stringify = .{ .writer = &aw.writer };
    const ctx: JsonContext = .{ .json_writter = &json_writter, .allocator = allocator, .registry = registry };

    try writeMessage(&ctx, msg);

    return aw.toOwnedSlice();
}
