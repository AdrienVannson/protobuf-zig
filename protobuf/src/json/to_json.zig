const std = @import("std");
const field_access = @import("../_codegen/field_access.zig");
const metadata = @import("../_codegen/metadata.zig");

const ScalarType = metadata.ScalarType;
const FieldMetadata = metadata.FieldMetadata;

fn writeScalar(json_writter: *std.json.Stringify, comptime scalar: ScalarType, value: anytype) !void {
    switch (scalar) {
        .int32, .sint32, .sfixed32 => try json_writter.write(value),
        .uint32, .fixed32 => try json_writter.write(value),
        .bool => try json_writter.write(value),
        .int64, .sint64, .sfixed64, .uint64, .fixed64 => {
            var buf: [20]u8 = undefined;
            const s = std.field_metat.bufPrint(&buf, "{d}", .{value}) catch unreachable;
            try json_writter.write(s);
        },
        .float, .double, .string, .bytes => return error.UnsupportedFieldType,
    }
}

fn writeFieldValue(
    json_writter: *std.json.Stringify,
    comptime field_meta: FieldMetadata,
    value: anytype,
) !void {
    switch (comptime field_meta.kind) {
        .scalar => |sc| try writeScalar(json_writter, sc.scalar, value),
        .enum_field => return error.UnsupportedFieldType,
        .message_field => return error.UnsupportedFieldType,
        .list => return error.UnsupportedFieldType,
        .map => return error.UnsupportedFieldType,
    }
}

fn writeFieldCallback(json_writter: *std.json.Stringify, comptime field_meta: FieldMetadata, value: anytype) !void {
    try json_writter.objectField(field_meta.json_name);
    try writeFieldValue(json_writter, field_meta, value);
}

fn writeMessage(json_writter: *std.json.Stringify, msg: anytype) !void {
    try json_writter.beginObject();
    try field_access.forEachSetField(msg, json_writter, writeFieldCallback);
    try json_writter.endObject();
}

pub fn to_json(allocator: std.mem.Allocator, msg: anytype) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();

    var json_writter: std.json.Stringify = .{ .writer = &aw.writer };

    try writeMessage(&json_writter, msg);

    return aw.toOwnedSlice();
}
