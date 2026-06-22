const std = @import("std");
const field_access = @import("../_codegen/field_access.zig");
const metadata = @import("../_codegen/metadata.zig");

const ScalarType = metadata.ScalarType;
const FieldMetadata = metadata.FieldMetadata;

const JsonContext = struct {
    json_writter: *std.json.Stringify,
    allocator: std.mem.Allocator,
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

fn writeFieldValue(
    ctx: *const JsonContext,
    comptime field_meta: FieldMetadata,
    value: anytype,
) !void {
    switch (comptime field_meta.kind) {
        .scalar => |sc| try writeScalar(ctx, sc.scalar, value),
        .enum_field => return error.UnsupportedFieldType,
        .message_field => return error.UnsupportedFieldType,
        .list => return error.UnsupportedFieldType,
        .map => return error.UnsupportedFieldType,
    }
}

fn writeFieldCallback(ctx: *const JsonContext, comptime field_meta: FieldMetadata, value: anytype) !void {
    try ctx.json_writter.objectField(field_meta.json_name);
    try writeFieldValue(ctx, field_meta, value);
}

fn writeMessage(ctx: *const JsonContext, msg: anytype) !void {
    try ctx.json_writter.beginObject();
    try field_access.forEachSetField(msg, ctx, writeFieldCallback);
    try ctx.json_writter.endObject();
}

pub fn to_json(allocator: std.mem.Allocator, msg: anytype) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();

    var json_writter: std.json.Stringify = .{ .writer = &aw.writer };
    const ctx: JsonContext = .{ .json_writter = &json_writter, .allocator = allocator };

    try writeMessage(&ctx, msg);

    return aw.toOwnedSlice();
}
