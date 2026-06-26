const std = @import("std");
const field_access = @import("../_codegen/field_access.zig");
const metadata = @import("../_codegen/metadata.zig");
const descriptor = @import("../descriptor.zig");

const ScalarType = metadata.ScalarType;
const FieldMetadata = metadata.FieldMetadata;
const DescMessage = descriptor.DescMessage;

const JsonContext = struct {
    json_writter: *std.json.Stringify,
    allocator: std.mem.Allocator,
    desc: *const DescMessage,
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
            .message => try writeMessage(item.*, ctx.json_writter, ctx.allocator),
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
            .message => try writeMessage(entry.value_ptr.*.*, ctx.json_writter, ctx.allocator),
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
        .message_field => try writeMessage(value.*, ctx.json_writter, ctx.allocator),
        .list => |list_meta| try writeList(ctx, list_meta, value),
        .map => |map_meta| try writeMap(ctx, map_meta, value),
    }
}

fn writeFieldCallback(ctx: *const JsonContext, comptime field_meta: FieldMetadata, value: anytype) !void {
    const json_name = blk: {
        for (ctx.desc.fields) |df| {
            if (df.number == field_meta.number) break :blk df.json_name;
        }
        unreachable;
    };
    try ctx.json_writter.objectField(json_name);
    try writeFieldValue(ctx, field_meta, value);
}

fn writeMessage(msg: anytype, json_writter: *std.json.Stringify, allocator: std.mem.Allocator) anyerror!void {
    const T = @TypeOf(msg);
    const desc = try T._desc();
    const msg_ctx: JsonContext = .{
        .json_writter = json_writter,
        .allocator = allocator,
        .desc = desc,
    };
    try json_writter.beginObject();
    try field_access.forEachSetField(msg, &msg_ctx, writeFieldCallback);
    try json_writter.endObject();
}

pub fn to_json(allocator: std.mem.Allocator, msg: anytype) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();

    var json_writter: std.json.Stringify = .{ .writer = &aw.writer };

    try writeMessage(msg, &json_writter, allocator);

    return aw.toOwnedSlice();
}
