const std = @import("std");
const proto3_pb = @import("generated_old_lib/protobuf_test_messages/proto3.pb.zig");
const gen_proto3 = @import("gen_proto3");

const Ext = proto3_pb.TestAllTypesProto3;
const Our = gen_proto3.TestAllTypesProto3;

/// Converts an external (zig-protobuf generated) TestAllTypesProto3 into our
/// generated representation. Only scalar and string/bytes fields are handled;
/// other fields are not yet generated.
///
/// The external type uses implicit presence (default value = absent), while our
/// generated type uses explicit presence (?T). Conversion: default value → null,
/// non-default → Some(value).
pub fn fromExternal(src: Ext, alloc: std.mem.Allocator) error{OutOfMemory}!Our {
    _ = alloc;
    var result = Our{};

    result.optional_int32 = if (src.optional_int32 != 0) src.optional_int32 else null;
    result.optional_int64 = if (src.optional_int64 != 0) src.optional_int64 else null;
    result.optional_uint32 = if (src.optional_uint32 != 0) src.optional_uint32 else null;
    result.optional_uint64 = if (src.optional_uint64 != 0) src.optional_uint64 else null;
    result.optional_sint32 = if (src.optional_sint32 != 0) src.optional_sint32 else null;
    result.optional_sint64 = if (src.optional_sint64 != 0) src.optional_sint64 else null;
    result.optional_fixed32 = if (src.optional_fixed32 != 0) src.optional_fixed32 else null;
    result.optional_fixed64 = if (src.optional_fixed64 != 0) src.optional_fixed64 else null;
    result.optional_sfixed32 = if (src.optional_sfixed32 != 0) src.optional_sfixed32 else null;
    result.optional_sfixed64 = if (src.optional_sfixed64 != 0) src.optional_sfixed64 else null;
    result.optional_float = if (src.optional_float != 0.0) src.optional_float else null;
    result.optional_double = if (src.optional_double != 0.0) src.optional_double else null;
    result.optional_bool = if (src.optional_bool) true else null;

    // String/bytes slices live in the same arena; no dupe needed.
    result.optional_string = if (src.optional_string.len > 0) src.optional_string else null;
    result.optional_bytes = if (src.optional_bytes.len > 0) src.optional_bytes else null;
    result.optional_string_piece = if (src.optional_string_piece.len > 0) src.optional_string_piece else null;
    result.optional_cord = if (src.optional_cord.len > 0) src.optional_cord else null;

    result.fieldname1 = if (src.fieldname1 != 0) src.fieldname1 else null;
    result.field_name2 = if (src.field_name2 != 0) src.field_name2 else null;
    result._field_name3 = if (src._field_name3 != 0) src._field_name3 else null;
    result.field__name4_ = if (src.field__name4_ != 0) src.field__name4_ else null;
    result.field0name5 = if (src.field0name5 != 0) src.field0name5 else null;
    result.field_0_name6 = if (src.field_0_name6 != 0) src.field_0_name6 else null;
    result.fieldName7 = if (src.fieldName7 != 0) src.fieldName7 else null;
    result.FieldName8 = if (src.FieldName8 != 0) src.FieldName8 else null;
    result.field_Name9 = if (src.field_Name9 != 0) src.field_Name9 else null;
    result.Field_Name10 = if (src.Field_Name10 != 0) src.Field_Name10 else null;
    result.FIELD_NAME11 = if (src.FIELD_NAME11 != 0) src.FIELD_NAME11 else null;
    result.FIELD_name12 = if (src.FIELD_name12 != 0) src.FIELD_name12 else null;
    result.__field_name13 = if (src.__field_name13 != 0) src.__field_name13 else null;
    result.__Field_name14 = if (src.__Field_name14 != 0) src.__Field_name14 else null;
    result.field__name15 = if (src.field__name15 != 0) src.field__name15 else null;
    result.field__Name16 = if (src.field__Name16 != 0) src.field__Name16 else null;
    result.field_name17__ = if (src.field_name17__ != 0) src.field_name17__ else null;
    result.Field_name18__ = if (src.Field_name18__ != 0) src.Field_name18__ else null;

    return result;
}

test "fromExternal zero-value roundtrip" {
    const alloc = std.testing.allocator;
    var src = Ext{};
    defer src.deinit(alloc);
    var result = try fromExternal(src, alloc);
    _ = &result;
    try std.testing.expectEqual(@as(?i32, null), result.optional_int32);
    try std.testing.expectEqual(@as(?u64, null), result.optional_uint64);
    try std.testing.expectEqual(@as(?bool, null), result.optional_bool);
    try std.testing.expectEqual(@as(?[]const u8, null), result.optional_string);
}
