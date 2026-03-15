const std = @import("std");
const metadata = @import("../metadata.zig");

pub const TestAllTypesProto3 = struct {
    pub const NestedMessage = struct {
        a: i32 = 0,
        corecursive: ?*TestAllTypesProto3 = null,

        pub const _desc = metadata.MessageMetadata{
            .fields = &[_]metadata.FieldMetadata{
                .{ .number = 1, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // a
                .{ .number = 2, .kind = .{ .message_field = .{} } }, // corecursive
            },
        };

        pub fn deinit(self: *NestedMessage, allocator: std.mem.Allocator) void {
            if (self.corecursive) |c| {
                c.deinit(allocator);
                allocator.destroy(c);
            }
        }
    };

    pub const ForeignMessage = struct {
        c: i32 = 0,

        pub const _desc = metadata.MessageMetadata{
            .fields = &[_]metadata.FieldMetadata{
                .{ .number = 1, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // c
            },
        };

        pub fn deinit(self: *ForeignMessage, allocator: std.mem.Allocator) void {
            _ = self;
            _ = allocator;
        }
    };

    pub const NestedEnum = enum(i32) {
        FOO = 0,
        BAR = 1,
        BAZ = 2,
        NEG = -1,
    };

    pub const ForeignEnum = enum(i32) {
        FOREIGN_FOO = 0,
        FOREIGN_BAR = 1,
        FOREIGN_BAZ = 2,
    };

    pub const AliasedEnum = enum(i32) {
        ALIAS_FOO = 0,
        ALIAS_BAR = 1,
        ALIAS_BAZ = 2,
        // MOO=2, moo=2, bAz=2 deduplicated (allow_alias=true, keep first per numeric value)
    };

    pub const NullValue = enum(i32) {
        NULL_VALUE = 0,
    };

    pub const OneofField = union(enum) {
        oneof_uint32: u32,
        oneof_nested_message: *NestedMessage,
        oneof_string: []const u8,
        oneof_bytes: []const u8,
        oneof_bool: bool,
        oneof_uint64: u64,
        oneof_float: f32,
        oneof_double: f64,
        oneof_enum: NestedEnum,
        oneof_null_value: NullValue,
    };

    // Singular scalar fields (implicit presence in proto3)
    optional_int32: i32 = 0,
    optional_int64: i64 = 0,
    optional_uint32: u32 = 0,
    optional_uint64: u64 = 0,
    optional_sint32: i32 = 0,
    optional_sint64: i64 = 0,
    optional_fixed32: u32 = 0,
    optional_fixed64: u64 = 0,
    optional_sfixed32: i32 = 0,
    optional_sfixed64: i64 = 0,
    optional_float: f32 = 0,
    optional_double: f64 = 0,
    optional_bool: bool = false,
    optional_string: []const u8 = "",
    optional_bytes: []const u8 = "",

    // Message fields (explicit presence)
    optional_nested_message: ?*NestedMessage = null,
    optional_foreign_message: ?*ForeignMessage = null,

    // Enum fields (implicit presence)
    optional_nested_enum: NestedEnum = .FOO,
    optional_foreign_enum: ForeignEnum = .FOREIGN_FOO,
    optional_aliased_enum: AliasedEnum = .ALIAS_FOO,

    // String fields with ctype annotations (implicit presence)
    optional_string_piece: []const u8 = "",
    optional_cord: []const u8 = "",

    // Recursive self-reference (explicit presence)
    recursive_message: ?*TestAllTypesProto3 = null,

    // Repeated scalar fields
    repeated_int32: std.ArrayListUnmanaged(i32) = .{},
    repeated_int64: std.ArrayListUnmanaged(i64) = .{},
    repeated_uint32: std.ArrayListUnmanaged(u32) = .{},
    repeated_uint64: std.ArrayListUnmanaged(u64) = .{},
    repeated_sint32: std.ArrayListUnmanaged(i32) = .{},
    repeated_sint64: std.ArrayListUnmanaged(i64) = .{},
    repeated_fixed32: std.ArrayListUnmanaged(u32) = .{},
    repeated_fixed64: std.ArrayListUnmanaged(u64) = .{},
    repeated_sfixed32: std.ArrayListUnmanaged(i32) = .{},
    repeated_sfixed64: std.ArrayListUnmanaged(i64) = .{},
    repeated_float: std.ArrayListUnmanaged(f32) = .{},
    repeated_double: std.ArrayListUnmanaged(f64) = .{},
    repeated_bool: std.ArrayListUnmanaged(bool) = .{},
    repeated_string: std.ArrayListUnmanaged([]const u8) = .{},
    repeated_bytes: std.ArrayListUnmanaged([]const u8) = .{},

    // Repeated message fields
    repeated_nested_message: std.ArrayListUnmanaged(NestedMessage) = .{},
    repeated_foreign_message: std.ArrayListUnmanaged(ForeignMessage) = .{},

    // Repeated enum fields
    repeated_nested_enum: std.ArrayListUnmanaged(NestedEnum) = .{},
    repeated_foreign_enum: std.ArrayListUnmanaged(ForeignEnum) = .{},

    // Repeated string fields (ctype annotations)
    repeated_string_piece: std.ArrayListUnmanaged([]const u8) = .{},
    repeated_cord: std.ArrayListUnmanaged([]const u8) = .{},

    // Packed repeated fields
    packed_int32: std.ArrayListUnmanaged(i32) = .{},
    packed_int64: std.ArrayListUnmanaged(i64) = .{},
    packed_uint32: std.ArrayListUnmanaged(u32) = .{},
    packed_uint64: std.ArrayListUnmanaged(u64) = .{},
    packed_sint32: std.ArrayListUnmanaged(i32) = .{},
    packed_sint64: std.ArrayListUnmanaged(i64) = .{},
    packed_fixed32: std.ArrayListUnmanaged(u32) = .{},
    packed_fixed64: std.ArrayListUnmanaged(u64) = .{},
    packed_sfixed32: std.ArrayListUnmanaged(i32) = .{},
    packed_sfixed64: std.ArrayListUnmanaged(i64) = .{},
    packed_float: std.ArrayListUnmanaged(f32) = .{},
    packed_double: std.ArrayListUnmanaged(f64) = .{},
    packed_bool: std.ArrayListUnmanaged(bool) = .{},
    packed_nested_enum: std.ArrayListUnmanaged(NestedEnum) = .{},

    // Unpacked repeated fields
    unpacked_int32: std.ArrayListUnmanaged(i32) = .{},
    unpacked_int64: std.ArrayListUnmanaged(i64) = .{},
    unpacked_uint32: std.ArrayListUnmanaged(u32) = .{},
    unpacked_uint64: std.ArrayListUnmanaged(u64) = .{},
    unpacked_sint32: std.ArrayListUnmanaged(i32) = .{},
    unpacked_sint64: std.ArrayListUnmanaged(i64) = .{},
    unpacked_fixed32: std.ArrayListUnmanaged(u32) = .{},
    unpacked_fixed64: std.ArrayListUnmanaged(u64) = .{},
    unpacked_sfixed32: std.ArrayListUnmanaged(i32) = .{},
    unpacked_sfixed64: std.ArrayListUnmanaged(i64) = .{},
    unpacked_float: std.ArrayListUnmanaged(f32) = .{},
    unpacked_double: std.ArrayListUnmanaged(f64) = .{},
    unpacked_bool: std.ArrayListUnmanaged(bool) = .{},
    unpacked_nested_enum: std.ArrayListUnmanaged(NestedEnum) = .{},

    // Map fields
    map_int32_int32: std.AutoHashMapUnmanaged(i32, i32) = .{},
    map_int64_int64: std.AutoHashMapUnmanaged(i64, i64) = .{},
    map_uint32_uint32: std.AutoHashMapUnmanaged(u32, u32) = .{},
    map_uint64_uint64: std.AutoHashMapUnmanaged(u64, u64) = .{},
    map_sint32_sint32: std.AutoHashMapUnmanaged(i32, i32) = .{},
    map_sint64_sint64: std.AutoHashMapUnmanaged(i64, i64) = .{},
    map_fixed32_fixed32: std.AutoHashMapUnmanaged(u32, u32) = .{},
    map_fixed64_fixed64: std.AutoHashMapUnmanaged(u64, u64) = .{},
    map_sfixed32_sfixed32: std.AutoHashMapUnmanaged(i32, i32) = .{},
    map_sfixed64_sfixed64: std.AutoHashMapUnmanaged(i64, i64) = .{},
    map_int32_float: std.AutoHashMapUnmanaged(i32, f32) = .{},
    map_int32_double: std.AutoHashMapUnmanaged(i32, f64) = .{},
    map_bool_bool: std.AutoHashMapUnmanaged(bool, bool) = .{},
    map_string_string: std.StringHashMapUnmanaged([]const u8) = .{},
    map_string_bytes: std.StringHashMapUnmanaged([]const u8) = .{},
    map_string_nested_message: std.StringHashMapUnmanaged(NestedMessage) = .{},
    map_string_foreign_message: std.StringHashMapUnmanaged(ForeignMessage) = .{},
    map_string_nested_enum: std.StringHashMapUnmanaged(NestedEnum) = .{},
    map_string_foreign_enum: std.StringHashMapUnmanaged(ForeignEnum) = .{},

    // Oneof field (tagged union)
    oneof_field: ?OneofField = null,

    // Field-name-to-JSON-name convention tests
    fieldname1: i32 = 0,
    field_name2: i32 = 0,
    _field_name3: i32 = 0,
    field__name4_: i32 = 0,
    field0name5: i32 = 0,
    field_0_name6: i32 = 0,
    fieldName7: i32 = 0,
    FieldName8: i32 = 0,
    field_Name9: i32 = 0,
    Field_Name10: i32 = 0,
    FIELD_NAME11: i32 = 0,
    FIELD_name12: i32 = 0,
    __field_name13: i32 = 0,
    __Field_name14: i32 = 0,
    field__name15: i32 = 0,
    field__Name16: i32 = 0,
    field_name17__: i32 = 0,
    Field_name18__: i32 = 0,

    pub const _desc = metadata.MessageMetadata{
        .fields = &[_]metadata.FieldMetadata{
            // Singular scalar fields (implicit presence in proto3)
            .{ .number = 1, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // optional_int32
            .{ .number = 2, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int64 } } }, // optional_int64
            .{ .number = 3, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .uint32 } } }, // optional_uint32
            .{ .number = 4, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .uint64 } } }, // optional_uint64
            .{ .number = 5, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .sint32 } } }, // optional_sint32
            .{ .number = 6, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .sint64 } } }, // optional_sint64
            .{ .number = 7, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .fixed32 } } }, // optional_fixed32
            .{ .number = 8, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .fixed64 } } }, // optional_fixed64
            .{ .number = 9, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .sfixed32 } } }, // optional_sfixed32
            .{ .number = 10, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .sfixed64 } } }, // optional_sfixed64
            .{ .number = 11, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .float } } }, // optional_float
            .{ .number = 12, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .double } } }, // optional_double
            .{ .number = 13, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .bool } } }, // optional_bool
            .{ .number = 14, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .string } } }, // optional_string
            .{ .number = 15, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .bytes } } }, // optional_bytes
            // Message fields (explicit presence, default)
            .{ .number = 18, .kind = .{ .message_field = .{} } }, // optional_nested_message
            .{ .number = 19, .kind = .{ .message_field = .{} } }, // optional_foreign_message
            // Enum fields (implicit presence)
            .{ .number = 21, .presence = .implicit, .kind = .{ .enum_field = .{} } }, // optional_nested_enum
            .{ .number = 22, .presence = .implicit, .kind = .{ .enum_field = .{} } }, // optional_foreign_enum
            .{ .number = 23, .presence = .implicit, .kind = .{ .enum_field = .{} } }, // optional_aliased_enum
            // String fields with ctype annotations (implicit presence)
            .{ .number = 24, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .string } } }, // optional_string_piece
            .{ .number = 25, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .string } } }, // optional_cord
            .{ .number = 27, .kind = .{ .message_field = .{} } }, // recursive_message
            // Repeated scalar fields
            .{ .number = 31, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .int32 } } } }, // repeated_int32
            .{ .number = 32, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .int64 } } } }, // repeated_int64
            .{ .number = 33, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .uint32 } } } }, // repeated_uint32
            .{ .number = 34, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .uint64 } } } }, // repeated_uint64
            .{ .number = 35, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .sint32 } } } }, // repeated_sint32
            .{ .number = 36, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .sint64 } } } }, // repeated_sint64
            .{ .number = 37, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .fixed32 } } } }, // repeated_fixed32
            .{ .number = 38, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .fixed64 } } } }, // repeated_fixed64
            .{ .number = 39, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .sfixed32 } } } }, // repeated_sfixed32
            .{ .number = 40, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .sfixed64 } } } }, // repeated_sfixed64
            .{ .number = 41, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .float } } } }, // repeated_float
            .{ .number = 42, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .double } } } }, // repeated_double
            .{ .number = 43, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .bool } } } }, // repeated_bool
            .{ .number = 44, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .string } } } }, // repeated_string
            .{ .number = 45, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .bytes } } } }, // repeated_bytes
            // Repeated message fields
            .{ .number = 48, .presence = .implicit, .kind = .{ .list = .{ .element = .message } } }, // repeated_nested_message
            .{ .number = 49, .presence = .implicit, .kind = .{ .list = .{ .element = .message } } }, // repeated_foreign_message
            // Repeated enum fields
            .{ .number = 51, .presence = .implicit, .kind = .{ .list = .{ .element = .enum_type } } }, // repeated_nested_enum
            .{ .number = 52, .presence = .implicit, .kind = .{ .list = .{ .element = .enum_type } } }, // repeated_foreign_enum
            // Repeated string fields (ctype annotations)
            .{ .number = 54, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .string } } } }, // repeated_string_piece
            .{ .number = 55, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .string } } } }, // repeated_cord
            // Map fields
            .{ .number = 56, .presence = .implicit, .kind = .{ .map = .{ .key = .int32, .value = .{ .scalar = .int32 } } } }, // map_int32_int32
            .{ .number = 57, .presence = .implicit, .kind = .{ .map = .{ .key = .int64, .value = .{ .scalar = .int64 } } } }, // map_int64_int64
            .{ .number = 58, .presence = .implicit, .kind = .{ .map = .{ .key = .uint32, .value = .{ .scalar = .uint32 } } } }, // map_uint32_uint32
            .{ .number = 59, .presence = .implicit, .kind = .{ .map = .{ .key = .uint64, .value = .{ .scalar = .uint64 } } } }, // map_uint64_uint64
            .{ .number = 60, .presence = .implicit, .kind = .{ .map = .{ .key = .sint32, .value = .{ .scalar = .sint32 } } } }, // map_sint32_sint32
            .{ .number = 61, .presence = .implicit, .kind = .{ .map = .{ .key = .sint64, .value = .{ .scalar = .sint64 } } } }, // map_sint64_sint64
            .{ .number = 62, .presence = .implicit, .kind = .{ .map = .{ .key = .fixed32, .value = .{ .scalar = .fixed32 } } } }, // map_fixed32_fixed32
            .{ .number = 63, .presence = .implicit, .kind = .{ .map = .{ .key = .fixed64, .value = .{ .scalar = .fixed64 } } } }, // map_fixed64_fixed64
            .{ .number = 64, .presence = .implicit, .kind = .{ .map = .{ .key = .sfixed32, .value = .{ .scalar = .sfixed32 } } } }, // map_sfixed32_sfixed32
            .{ .number = 65, .presence = .implicit, .kind = .{ .map = .{ .key = .sfixed64, .value = .{ .scalar = .sfixed64 } } } }, // map_sfixed64_sfixed64
            .{ .number = 66, .presence = .implicit, .kind = .{ .map = .{ .key = .int32, .value = .{ .scalar = .float } } } }, // map_int32_float
            .{ .number = 67, .presence = .implicit, .kind = .{ .map = .{ .key = .int32, .value = .{ .scalar = .double } } } }, // map_int32_double
            .{ .number = 68, .presence = .implicit, .kind = .{ .map = .{ .key = .bool, .value = .{ .scalar = .bool } } } }, // map_bool_bool
            .{ .number = 69, .presence = .implicit, .kind = .{ .map = .{ .key = .string, .value = .{ .scalar = .string } } } }, // map_string_string
            .{ .number = 70, .presence = .implicit, .kind = .{ .map = .{ .key = .string, .value = .{ .scalar = .bytes } } } }, // map_string_bytes
            .{ .number = 71, .presence = .implicit, .kind = .{ .map = .{ .key = .string, .value = .message } } }, // map_string_nested_message
            .{ .number = 72, .presence = .implicit, .kind = .{ .map = .{ .key = .string, .value = .message } } }, // map_string_foreign_message
            .{ .number = 73, .presence = .implicit, .kind = .{ .map = .{ .key = .string, .value = .enum_type } } }, // map_string_nested_enum
            .{ .number = 74, .presence = .implicit, .kind = .{ .map = .{ .key = .string, .value = .enum_type } } }, // map_string_foreign_enum
            // Packed repeated fields
            .{ .number = 75, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .int32 }, .is_packed = true } } }, // packed_int32
            .{ .number = 76, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .int64 }, .is_packed = true } } }, // packed_int64
            .{ .number = 77, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .uint32 }, .is_packed = true } } }, // packed_uint32
            .{ .number = 78, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .uint64 }, .is_packed = true } } }, // packed_uint64
            .{ .number = 79, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .sint32 }, .is_packed = true } } }, // packed_sint32
            .{ .number = 80, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .sint64 }, .is_packed = true } } }, // packed_sint64
            .{ .number = 81, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .fixed32 }, .is_packed = true } } }, // packed_fixed32
            .{ .number = 82, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .fixed64 }, .is_packed = true } } }, // packed_fixed64
            .{ .number = 83, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .sfixed32 }, .is_packed = true } } }, // packed_sfixed32
            .{ .number = 84, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .sfixed64 }, .is_packed = true } } }, // packed_sfixed64
            .{ .number = 85, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .float }, .is_packed = true } } }, // packed_float
            .{ .number = 86, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .double }, .is_packed = true } } }, // packed_double
            .{ .number = 87, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .bool }, .is_packed = true } } }, // packed_bool
            .{ .number = 88, .presence = .implicit, .kind = .{ .list = .{ .element = .enum_type, .is_packed = true } } }, // packed_nested_enum
            // Unpacked repeated fields
            .{ .number = 89, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .int32 } } } }, // unpacked_int32
            .{ .number = 90, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .int64 } } } }, // unpacked_int64
            .{ .number = 91, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .uint32 } } } }, // unpacked_uint32
            .{ .number = 92, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .uint64 } } } }, // unpacked_uint64
            .{ .number = 93, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .sint32 } } } }, // unpacked_sint32
            .{ .number = 94, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .sint64 } } } }, // unpacked_sint64
            .{ .number = 95, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .fixed32 } } } }, // unpacked_fixed32
            .{ .number = 96, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .fixed64 } } } }, // unpacked_fixed64
            .{ .number = 97, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .sfixed32 } } } }, // unpacked_sfixed32
            .{ .number = 98, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .sfixed64 } } } }, // unpacked_sfixed64
            .{ .number = 99, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .float } } } }, // unpacked_float
            .{ .number = 100, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .double } } } }, // unpacked_double
            .{ .number = 101, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .bool } } } }, // unpacked_bool
            .{ .number = 102, .presence = .implicit, .kind = .{ .list = .{ .element = .enum_type } } }, // unpacked_nested_enum
            // Oneof fields (individual FieldMetadata entries; wire format treats them as regular fields)
            .{ .number = 111, .kind = .{ .scalar = .{ .scalar = .uint32 } } }, // oneof_uint32
            .{ .number = 112, .kind = .{ .message_field = .{} } }, // oneof_nested_message
            .{ .number = 113, .kind = .{ .scalar = .{ .scalar = .string } } }, // oneof_string
            .{ .number = 114, .kind = .{ .scalar = .{ .scalar = .bytes } } }, // oneof_bytes
            .{ .number = 115, .kind = .{ .scalar = .{ .scalar = .bool } } }, // oneof_bool
            .{ .number = 116, .kind = .{ .scalar = .{ .scalar = .uint64 } } }, // oneof_uint64
            .{ .number = 117, .kind = .{ .scalar = .{ .scalar = .float } } }, // oneof_float
            .{ .number = 118, .kind = .{ .scalar = .{ .scalar = .double } } }, // oneof_double
            .{ .number = 119, .kind = .{ .enum_field = .{} } }, // oneof_enum
            .{ .number = 120, .kind = .{ .enum_field = .{} } }, // oneof_null_value
            // Well-known type fields (201–219, 301–317) omitted
            // Field-name-to-JSON-name convention tests
            .{ .number = 401, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // fieldname1
            .{ .number = 402, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // field_name2
            .{ .number = 403, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // _field_name3
            .{ .number = 404, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // field__name4_
            .{ .number = 405, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // field0name5
            .{ .number = 406, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // field_0_name6
            .{ .number = 407, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // fieldName7
            .{ .number = 408, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // FieldName8
            .{ .number = 409, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // field_Name9
            .{ .number = 410, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // Field_Name10
            .{ .number = 411, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // FIELD_NAME11
            .{ .number = 412, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // FIELD_name12
            .{ .number = 413, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // __field_name13
            .{ .number = 414, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // __Field_name14
            .{ .number = 415, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // field__name15
            .{ .number = 416, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // field__Name16
            .{ .number = 417, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // field_name17__
            .{ .number = 418, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // Field_name18__
        },
    };

    pub fn deinit(self: *TestAllTypesProto3, allocator: std.mem.Allocator) void {
        // Singular message fields
        if (self.optional_nested_message) |m| {
            m.deinit(allocator);
            allocator.destroy(m);
        }
        if (self.optional_foreign_message) |m| {
            m.deinit(allocator);
            allocator.destroy(m);
        }
        if (self.recursive_message) |m| {
            m.deinit(allocator);
            allocator.destroy(m);
        }

        // Repeated scalar fields
        self.repeated_int32.deinit(allocator);
        self.repeated_int64.deinit(allocator);
        self.repeated_uint32.deinit(allocator);
        self.repeated_uint64.deinit(allocator);
        self.repeated_sint32.deinit(allocator);
        self.repeated_sint64.deinit(allocator);
        self.repeated_fixed32.deinit(allocator);
        self.repeated_fixed64.deinit(allocator);
        self.repeated_sfixed32.deinit(allocator);
        self.repeated_sfixed64.deinit(allocator);
        self.repeated_float.deinit(allocator);
        self.repeated_double.deinit(allocator);
        self.repeated_bool.deinit(allocator);

        // Repeated string/bytes fields (free elements)
        for (self.repeated_string.items) |s| allocator.free(s);
        self.repeated_string.deinit(allocator);
        for (self.repeated_bytes.items) |s| allocator.free(s);
        self.repeated_bytes.deinit(allocator);

        // Repeated message fields (deinit elements, stored by value)
        for (self.repeated_nested_message.items) |*m| m.deinit(allocator);
        self.repeated_nested_message.deinit(allocator);
        for (self.repeated_foreign_message.items) |*m| m.deinit(allocator);
        self.repeated_foreign_message.deinit(allocator);

        // Repeated enum fields
        self.repeated_nested_enum.deinit(allocator);
        self.repeated_foreign_enum.deinit(allocator);

        // Repeated string fields (ctype)
        for (self.repeated_string_piece.items) |s| allocator.free(s);
        self.repeated_string_piece.deinit(allocator);
        for (self.repeated_cord.items) |s| allocator.free(s);
        self.repeated_cord.deinit(allocator);

        // Packed repeated fields
        self.packed_int32.deinit(allocator);
        self.packed_int64.deinit(allocator);
        self.packed_uint32.deinit(allocator);
        self.packed_uint64.deinit(allocator);
        self.packed_sint32.deinit(allocator);
        self.packed_sint64.deinit(allocator);
        self.packed_fixed32.deinit(allocator);
        self.packed_fixed64.deinit(allocator);
        self.packed_sfixed32.deinit(allocator);
        self.packed_sfixed64.deinit(allocator);
        self.packed_float.deinit(allocator);
        self.packed_double.deinit(allocator);
        self.packed_bool.deinit(allocator);
        self.packed_nested_enum.deinit(allocator);

        // Unpacked repeated fields
        self.unpacked_int32.deinit(allocator);
        self.unpacked_int64.deinit(allocator);
        self.unpacked_uint32.deinit(allocator);
        self.unpacked_uint64.deinit(allocator);
        self.unpacked_sint32.deinit(allocator);
        self.unpacked_sint64.deinit(allocator);
        self.unpacked_fixed32.deinit(allocator);
        self.unpacked_fixed64.deinit(allocator);
        self.unpacked_sfixed32.deinit(allocator);
        self.unpacked_sfixed64.deinit(allocator);
        self.unpacked_float.deinit(allocator);
        self.unpacked_double.deinit(allocator);
        self.unpacked_bool.deinit(allocator);
        self.unpacked_nested_enum.deinit(allocator);

        // Map fields with primitive keys/values
        self.map_int32_int32.deinit(allocator);
        self.map_int64_int64.deinit(allocator);
        self.map_uint32_uint32.deinit(allocator);
        self.map_uint64_uint64.deinit(allocator);
        self.map_sint32_sint32.deinit(allocator);
        self.map_sint64_sint64.deinit(allocator);
        self.map_fixed32_fixed32.deinit(allocator);
        self.map_fixed64_fixed64.deinit(allocator);
        self.map_sfixed32_sfixed32.deinit(allocator);
        self.map_sfixed64_sfixed64.deinit(allocator);
        self.map_int32_float.deinit(allocator);
        self.map_int32_double.deinit(allocator);
        self.map_bool_bool.deinit(allocator);

        // Map fields with string keys (free keys, and values where needed)
        {
            var it = self.map_string_string.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            self.map_string_string.deinit(allocator);
        }
        {
            var it = self.map_string_bytes.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            self.map_string_bytes.deinit(allocator);
        }
        {
            var it = self.map_string_nested_message.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            self.map_string_nested_message.deinit(allocator);
        }
        {
            var it = self.map_string_foreign_message.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(allocator);
            }
            self.map_string_foreign_message.deinit(allocator);
        }
        {
            var it = self.map_string_nested_enum.iterator();
            while (it.next()) |entry| allocator.free(entry.key_ptr.*);
            self.map_string_nested_enum.deinit(allocator);
        }
        {
            var it = self.map_string_foreign_enum.iterator();
            while (it.next()) |entry| allocator.free(entry.key_ptr.*);
            self.map_string_foreign_enum.deinit(allocator);
        }

        // Oneof field
        if (self.oneof_field) |oneof| {
            switch (oneof) {
                .oneof_nested_message => |m| {
                    m.deinit(allocator);
                    allocator.destroy(m);
                },
                .oneof_string => |s| allocator.free(s),
                .oneof_bytes => |b| allocator.free(b),
                else => {},
            }
        }
    }
};

test "TestAllTypesProto3 default init and deinit" {
    const allocator = std.testing.allocator;
    var msg = TestAllTypesProto3{};
    msg.deinit(allocator);
}

test "TestAllTypesProto3 with scalar and repeated fields" {
    const allocator = std.testing.allocator;
    var msg = TestAllTypesProto3{};
    defer msg.deinit(allocator);

    msg.optional_int32 = 42;
    msg.optional_bool = true;
    msg.optional_nested_enum = .BAR;
    try msg.repeated_int32.append(allocator, 1);
    try msg.repeated_int32.append(allocator, 2);
    try msg.repeated_string.append(allocator, try allocator.dupe(u8, "hello"));
    try msg.packed_float.append(allocator, 3.14);
}

test "TestAllTypesProto3 with message fields" {
    const allocator = std.testing.allocator;
    var msg = TestAllTypesProto3{};
    defer msg.deinit(allocator);

    const nested = try allocator.create(TestAllTypesProto3.NestedMessage);
    nested.* = .{ .a = 10 };
    msg.optional_nested_message = nested;

    const foreign = try allocator.create(TestAllTypesProto3.ForeignMessage);
    foreign.* = .{ .c = 99 };
    msg.optional_foreign_message = foreign;
}

test "TestAllTypesProto3 with oneof field" {
    const allocator = std.testing.allocator;
    {
        var msg = TestAllTypesProto3{};
        defer msg.deinit(allocator);
        msg.oneof_field = .{ .oneof_uint32 = 42 };
    }
    {
        var msg = TestAllTypesProto3{};
        defer msg.deinit(allocator);
        msg.oneof_field = .{ .oneof_string = try allocator.dupe(u8, "test") };
    }
    {
        var msg = TestAllTypesProto3{};
        defer msg.deinit(allocator);
        const m = try allocator.create(TestAllTypesProto3.NestedMessage);
        m.* = .{ .a = 7 };
        msg.oneof_field = .{ .oneof_nested_message = m };
    }
}
