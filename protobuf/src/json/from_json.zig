const std = @import("std");
const field_access = @import("../_codegen/field_access.zig");
const metadata = @import("../_codegen/metadata.zig");

const ScalarType = metadata.ScalarType;
const FieldMetadata = metadata.FieldMetadata;

pub fn from_json(msg: anytype, json: []const u8, allocator: std.mem.Allocator) !void {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const obj = switch (parsed.value) {
        .object => |o| o,
        else => return error.InvalidJson,
    };

    try readMessage(msg, &obj, allocator);
}

fn readMessage(
    msg: anytype,
    obj: *const std.json.ObjectMap,
    allocator: std.mem.Allocator,
) !void {
    const T = std.meta.Child(@TypeOf(msg));

    var it = obj.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        const val = entry.value_ptr.*;

        inline for (T._desc.fields) |field_meta| {
            if (std.mem.eql(u8, key, field_meta.json_name)) {
                try setFieldFromJson(msg, field_meta, val, allocator);
                break;
            }
        }
        // Unknown keys are silently ignored for forward compatibility.
    }
}

fn setFieldFromJson(
    msg: anytype,
    comptime field_meta: FieldMetadata,
    val: std.json.Value,
    allocator: std.mem.Allocator,
) !void {
    switch (comptime field_meta.kind) {
        .scalar => |sc| {
            const v = try parseScalar(sc.scalar, val);
            field_access.setField(msg, field_meta, v, allocator);
        },
        .enum_field => return error.UnsupportedFieldType,
        .message_field => return error.UnsupportedFieldType,
        .list => return error.UnsupportedFieldType,
        .map => return error.UnsupportedFieldType,
    }
}

fn parseScalar(comptime scalar: ScalarType, val: std.json.Value) !metadata.scalarZigType(scalar) {
    switch (scalar) {
        .int32, .sint32, .sfixed32 => {
            const n = switch (val) {
                .integer => |i| i,
                .float => |f| @as(i64, @intFromFloat(f)),
                else => return error.InvalidJson,
            };
            return std.math.cast(i32, n) orelse error.IntegerOverflow;
        },
        .uint32, .fixed32 => {
            const n = switch (val) {
                .integer => |i| i,
                .float => |f| @as(i64, @intFromFloat(f)),
                else => return error.InvalidJson,
            };
            return std.math.cast(u32, n) orelse error.IntegerOverflow;
        },
        .int64, .sint64, .sfixed64 => {
            return switch (val) {
                .integer => |i| i,
                .string => |s| std.fmt.parseInt(i64, s, 10) catch error.InvalidJson,
                .number_string => |s| std.fmt.parseInt(i64, s, 10) catch error.InvalidJson,
                .float => |f| @as(i64, @intFromFloat(f)),
                else => error.InvalidJson,
            };
        },
        .uint64, .fixed64 => {
            return switch (val) {
                .integer => |i| std.math.cast(u64, i) orelse error.IntegerOverflow,
                .string => |s| std.fmt.parseInt(u64, s, 10) catch error.InvalidJson,
                .number_string => |s| std.fmt.parseInt(u64, s, 10) catch error.InvalidJson,
                .float => |f| @as(u64, @intFromFloat(f)),
                else => error.InvalidJson,
            };
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
