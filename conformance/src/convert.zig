const std = @import("std");
const proto3_pb = @import("generated_old_lib/protobuf_test_messages/proto3.pb.zig");
const our_types = @import("protobuf").test_types;

const Ext = proto3_pb.TestAllTypesProto3;
const Our = our_types.TestAllTypesProto3;

/// Converts an external (zig-protobuf generated) TestAllTypesProto3 into our
/// internal representation.  On allocation failure, a partially constructed
/// result may have been allocated; the caller must call deinit on error.
/// Typical usage:
///
///   var result = fromExternal(src, alloc) catch |err| {
///       result.deinit(alloc);  // safe even if partial
///       return err;
///   };
pub fn fromExternal(src: Ext, alloc: std.mem.Allocator) !Our {
    var result = Our{};
    errdefer result.deinit(alloc);

    // --- Singular scalar fields (direct copy) ---
    result.optional_int32 = src.optional_int32;
    result.optional_int64 = src.optional_int64;
    result.optional_uint32 = src.optional_uint32;
    result.optional_uint64 = src.optional_uint64;
    result.optional_sint32 = src.optional_sint32;
    result.optional_sint64 = src.optional_sint64;
    result.optional_fixed32 = src.optional_fixed32;
    result.optional_fixed64 = src.optional_fixed64;
    result.optional_sfixed32 = src.optional_sfixed32;
    result.optional_sfixed64 = src.optional_sfixed64;
    result.optional_float = src.optional_float;
    result.optional_double = src.optional_double;
    result.optional_bool = src.optional_bool;

    // --- Singular string/bytes fields (duped) ---
    result.optional_string = try alloc.dupe(u8, src.optional_string);
    result.optional_bytes = try alloc.dupe(u8, src.optional_bytes);
    result.optional_string_piece = try alloc.dupe(u8, src.optional_string_piece);
    result.optional_cord = try alloc.dupe(u8, src.optional_cord);

    // --- Optional message fields (heap-allocated) ---
    if (src.optional_nested_message) |nm| {
        const p = try alloc.create(Our.NestedMessage);
        p.* = try convertNestedMessage(nm, alloc);
        result.optional_nested_message = p;
    }
    if (src.optional_foreign_message) |fm| {
        const p = try alloc.create(Our.ForeignMessage);
        p.* = .{ .c = fm.c };
        result.optional_foreign_message = p;
    }

    // --- Enum fields ---
    result.optional_nested_enum = @enumFromInt(@intFromEnum(src.optional_nested_enum));
    result.optional_foreign_enum = @enumFromInt(@intFromEnum(src.optional_foreign_enum));
    result.optional_aliased_enum = @enumFromInt(@intFromEnum(src.optional_aliased_enum));

    // --- Recursive message ---
    if (src.recursive_message) |rm| {
        const p = try alloc.create(Our);
        p.* = try fromExternal(rm.*, alloc);
        result.recursive_message = p;
    }

    // --- Repeated scalar fields ---
    try result.repeated_int32.appendSlice(alloc, src.repeated_int32.items);
    try result.repeated_int64.appendSlice(alloc, src.repeated_int64.items);
    try result.repeated_uint32.appendSlice(alloc, src.repeated_uint32.items);
    try result.repeated_uint64.appendSlice(alloc, src.repeated_uint64.items);
    try result.repeated_sint32.appendSlice(alloc, src.repeated_sint32.items);
    try result.repeated_sint64.appendSlice(alloc, src.repeated_sint64.items);
    try result.repeated_fixed32.appendSlice(alloc, src.repeated_fixed32.items);
    try result.repeated_fixed64.appendSlice(alloc, src.repeated_fixed64.items);
    try result.repeated_sfixed32.appendSlice(alloc, src.repeated_sfixed32.items);
    try result.repeated_sfixed64.appendSlice(alloc, src.repeated_sfixed64.items);
    try result.repeated_float.appendSlice(alloc, src.repeated_float.items);
    try result.repeated_double.appendSlice(alloc, src.repeated_double.items);
    try result.repeated_bool.appendSlice(alloc, src.repeated_bool.items);

    // --- Repeated string/bytes fields ---
    for (src.repeated_string.items) |s|
        try result.repeated_string.append(alloc, try alloc.dupe(u8, s));
    for (src.repeated_bytes.items) |s|
        try result.repeated_bytes.append(alloc, try alloc.dupe(u8, s));

    // --- Repeated message fields ---
    for (src.repeated_nested_message.items) |nm|
        try result.repeated_nested_message.append(alloc, try convertNestedMessage(nm, alloc));
    for (src.repeated_foreign_message.items) |fm|
        try result.repeated_foreign_message.append(alloc, .{ .c = fm.c });

    // --- Repeated enum fields ---
    for (src.repeated_nested_enum.items) |e|
        try result.repeated_nested_enum.append(alloc, @enumFromInt(@intFromEnum(e)));
    for (src.repeated_foreign_enum.items) |e|
        try result.repeated_foreign_enum.append(alloc, @enumFromInt(@intFromEnum(e)));

    // --- Repeated string fields (ctype) ---
    for (src.repeated_string_piece.items) |s|
        try result.repeated_string_piece.append(alloc, try alloc.dupe(u8, s));
    for (src.repeated_cord.items) |s|
        try result.repeated_cord.append(alloc, try alloc.dupe(u8, s));

    // --- Packed repeated fields ---
    try result.packed_int32.appendSlice(alloc, src.packed_int32.items);
    try result.packed_int64.appendSlice(alloc, src.packed_int64.items);
    try result.packed_uint32.appendSlice(alloc, src.packed_uint32.items);
    try result.packed_uint64.appendSlice(alloc, src.packed_uint64.items);
    try result.packed_sint32.appendSlice(alloc, src.packed_sint32.items);
    try result.packed_sint64.appendSlice(alloc, src.packed_sint64.items);
    try result.packed_fixed32.appendSlice(alloc, src.packed_fixed32.items);
    try result.packed_fixed64.appendSlice(alloc, src.packed_fixed64.items);
    try result.packed_sfixed32.appendSlice(alloc, src.packed_sfixed32.items);
    try result.packed_sfixed64.appendSlice(alloc, src.packed_sfixed64.items);
    try result.packed_float.appendSlice(alloc, src.packed_float.items);
    try result.packed_double.appendSlice(alloc, src.packed_double.items);
    try result.packed_bool.appendSlice(alloc, src.packed_bool.items);
    for (src.packed_nested_enum.items) |e|
        try result.packed_nested_enum.append(alloc, @enumFromInt(@intFromEnum(e)));

    // --- Unpacked repeated fields ---
    try result.unpacked_int32.appendSlice(alloc, src.unpacked_int32.items);
    try result.unpacked_int64.appendSlice(alloc, src.unpacked_int64.items);
    try result.unpacked_uint32.appendSlice(alloc, src.unpacked_uint32.items);
    try result.unpacked_uint64.appendSlice(alloc, src.unpacked_uint64.items);
    try result.unpacked_sint32.appendSlice(alloc, src.unpacked_sint32.items);
    try result.unpacked_sint64.appendSlice(alloc, src.unpacked_sint64.items);
    try result.unpacked_fixed32.appendSlice(alloc, src.unpacked_fixed32.items);
    try result.unpacked_fixed64.appendSlice(alloc, src.unpacked_fixed64.items);
    try result.unpacked_sfixed32.appendSlice(alloc, src.unpacked_sfixed32.items);
    try result.unpacked_sfixed64.appendSlice(alloc, src.unpacked_sfixed64.items);
    try result.unpacked_float.appendSlice(alloc, src.unpacked_float.items);
    try result.unpacked_double.appendSlice(alloc, src.unpacked_double.items);
    try result.unpacked_bool.appendSlice(alloc, src.unpacked_bool.items);
    for (src.unpacked_nested_enum.items) |e|
        try result.unpacked_nested_enum.append(alloc, @enumFromInt(@intFromEnum(e)));

    // --- Map fields (list-of-entries → hash map) ---
    for (src.map_int32_int32.items) |e|
        try result.map_int32_int32.put(alloc, e.key, e.value);
    for (src.map_int64_int64.items) |e|
        try result.map_int64_int64.put(alloc, e.key, e.value);
    for (src.map_uint32_uint32.items) |e|
        try result.map_uint32_uint32.put(alloc, e.key, e.value);
    for (src.map_uint64_uint64.items) |e|
        try result.map_uint64_uint64.put(alloc, e.key, e.value);
    for (src.map_sint32_sint32.items) |e|
        try result.map_sint32_sint32.put(alloc, e.key, e.value);
    for (src.map_sint64_sint64.items) |e|
        try result.map_sint64_sint64.put(alloc, e.key, e.value);
    for (src.map_fixed32_fixed32.items) |e|
        try result.map_fixed32_fixed32.put(alloc, e.key, e.value);
    for (src.map_fixed64_fixed64.items) |e|
        try result.map_fixed64_fixed64.put(alloc, e.key, e.value);
    for (src.map_sfixed32_sfixed32.items) |e|
        try result.map_sfixed32_sfixed32.put(alloc, e.key, e.value);
    for (src.map_sfixed64_sfixed64.items) |e|
        try result.map_sfixed64_sfixed64.put(alloc, e.key, e.value);
    for (src.map_int32_float.items) |e|
        try result.map_int32_float.put(alloc, e.key, e.value);
    for (src.map_int32_double.items) |e|
        try result.map_int32_double.put(alloc, e.key, e.value);
    for (src.map_bool_bool.items) |e|
        try result.map_bool_bool.put(alloc, e.key, e.value);

    // String-keyed maps (dupe key; dupe/convert value as needed)
    for (src.map_string_string.items) |e|
        try result.map_string_string.put(
            alloc,
            try alloc.dupe(u8, e.key),
            try alloc.dupe(u8, e.value),
        );
    for (src.map_string_bytes.items) |e|
        try result.map_string_bytes.put(
            alloc,
            try alloc.dupe(u8, e.key),
            try alloc.dupe(u8, e.value),
        );
    for (src.map_string_nested_message.items) |e|
        try result.map_string_nested_message.put(
            alloc,
            try alloc.dupe(u8, e.key),
            try convertNestedMessage(e.value, alloc),
        );
    for (src.map_string_foreign_message.items) |e|
        try result.map_string_foreign_message.put(
            alloc,
            try alloc.dupe(u8, e.key),
            .{ .c = e.value.c },
        );
    for (src.map_string_nested_enum.items) |e|
        try result.map_string_nested_enum.put(
            alloc,
            try alloc.dupe(u8, e.key),
            @enumFromInt(@intFromEnum(e.value)),
        );
    for (src.map_string_foreign_enum.items) |e|
        try result.map_string_foreign_enum.put(
            alloc,
            try alloc.dupe(u8, e.key),
            @enumFromInt(@intFromEnum(e.value)),
        );

    // --- Oneof field ---
    if (src.oneof_field) |oneof| {
        result.oneof_field = switch (oneof) {
            .oneof_uint32 => |v| .{ .oneof_uint32 = v },
            .oneof_nested_message => |nm| blk: {
                const p = try alloc.create(Our.NestedMessage);
                p.* = try convertNestedMessage(nm, alloc);
                break :blk .{ .oneof_nested_message = p };
            },
            .oneof_string => |s| .{ .oneof_string = try alloc.dupe(u8, s) },
            .oneof_bytes => |b| .{ .oneof_bytes = try alloc.dupe(u8, b) },
            .oneof_bool => |v| .{ .oneof_bool = v },
            .oneof_uint64 => |v| .{ .oneof_uint64 = v },
            .oneof_float => |v| .{ .oneof_float = v },
            .oneof_double => |v| .{ .oneof_double = v },
            .oneof_enum => |e| .{ .oneof_enum = @enumFromInt(@intFromEnum(e)) },
            .oneof_null_value => |e| .{ .oneof_null_value = @enumFromInt(@intFromEnum(e)) },
        };
    }

    // --- Field-name-to-JSON-name convention tests (direct copy) ---
    result.fieldname1 = src.fieldname1;
    result.field_name2 = src.field_name2;
    result._field_name3 = src._field_name3;
    result.field__name4_ = src.field__name4_;
    result.field0name5 = src.field0name5;
    result.field_0_name6 = src.field_0_name6;
    result.fieldName7 = src.fieldName7;
    result.FieldName8 = src.FieldName8;
    result.field_Name9 = src.field_Name9;
    result.Field_Name10 = src.Field_Name10;
    result.FIELD_NAME11 = src.FIELD_NAME11;
    result.FIELD_name12 = src.FIELD_name12;
    result.__field_name13 = src.__field_name13;
    result.__Field_name14 = src.__Field_name14;
    result.field__name15 = src.field__name15;
    result.field__Name16 = src.field__Name16;
    result.field_name17__ = src.field_name17__;
    result.Field_name18__ = src.Field_name18__;

    return result;
}

fn convertNestedMessage(
    src: Ext.NestedMessage,
    alloc: std.mem.Allocator,
) !Our.NestedMessage {
    var result = Our.NestedMessage{ .a = src.a };
    if (src.corecursive) |c| {
        const p = try alloc.create(Our);
        errdefer alloc.destroy(p);
        p.* = try fromExternal(c.*, alloc);
        result.corecursive = p;
    }
    return result;
}

test "fromExternal zero-value roundtrip" {
    const alloc = std.testing.allocator;
    var src = Ext{};
    defer src.deinit(alloc);
    var result = try fromExternal(src, alloc);
    defer result.deinit(alloc);
    try std.testing.expectEqual(@as(i32, 0), result.optional_int32);
    try std.testing.expectEqual(@as(u64, 0), result.optional_uint64);
    try std.testing.expectEqual(false, result.optional_bool);
    try std.testing.expectEqualStrings("", result.optional_string);
}
