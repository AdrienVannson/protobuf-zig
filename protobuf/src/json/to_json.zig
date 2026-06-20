const std = @import("std");
const field_access = @import("../_codegen/field_access.zig");
const metadata = @import("../_codegen/metadata.zig");

const ScalarType = metadata.ScalarType;
const FieldMetadata = metadata.FieldMetadata;

pub fn to_json(allocator: std.mem.Allocator, msg: anytype) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();

    var ws: std.json.Stringify = .{ .writer = &aw.writer };

    try writeMessage(&ws, msg);

    return aw.toOwnedSlice();
}

fn writeMessage(ws: *std.json.Stringify, msg: anytype) !void {
    const T = @TypeOf(msg);

    try ws.beginObject();

    inline for (T._desc.fields) |field_meta| {
        if (field_access.hasField(msg, field_meta)) {
            const value = field_access.getSetField(msg, field_meta) catch unreachable;
            try ws.objectField(field_meta.json_name);
            try writeValue(ws, field_meta, value);
        }
    }

    try ws.endObject();
}

fn writeValue(
    ws: *std.json.Stringify,
    comptime field_meta: FieldMetadata,
    value: anytype,
) !void {
    switch (comptime field_meta.kind) {
        .scalar => |sc| try writeScalar(ws, sc.scalar, value),
        .enum_field => return error.UnsupportedFieldType,
        .message_field => return error.UnsupportedFieldType,
        .list => return error.UnsupportedFieldType,
        .map => return error.UnsupportedFieldType,
    }
}

fn writeScalar(ws: *std.json.Stringify, comptime scalar: ScalarType, value: anytype) !void {
    switch (scalar) {
        .int32, .sint32, .sfixed32 => try ws.write(value),
        .uint32, .fixed32 => try ws.write(value),
        .bool => try ws.write(value),
        .int64, .sint64, .sfixed64, .uint64, .fixed64 => {
            var buf: [20]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
            try ws.write(s);
        },
        .float, .double, .string, .bytes => return error.UnsupportedFieldType,
    }
}
