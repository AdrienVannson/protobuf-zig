const descriptor = @import("../descriptor.zig");

pub const ScalarType = descriptor.ScalarType;
pub const DefaultValue = descriptor.DefaultValue;
pub const SupportedFieldPresence = descriptor.SupportedFieldPresence;

pub const FieldMetadataElementType = union(enum) {
    scalar: ScalarType,
    message: void,
    enum_type: void,
};

pub const FieldMetadataKind = union(enum) {
    scalar: struct {
        scalar: ScalarType,
        presence: SupportedFieldPresence = .explicit,
        // Declared default value, if any. Defaults to null (no explicit default).
        default_value: ?DefaultValue = null,
    },
    message_field: struct {
        delimited_encoding: bool = false,
        presence: SupportedFieldPresence = .explicit,
    },
    enum_field: struct {
        presence: SupportedFieldPresence = .explicit,
        default_value: i32 = 0,
    },
    list: struct {
        element: FieldMetadataElementType,
        is_packed: bool = false,
        delimited_encoding: bool = false,
    },
    map: struct {
        key: ScalarType,
        value: FieldMetadataElementType,
    },
};

pub const FieldMetadata = struct {
    number: u32,
    field_index: u16,
    oneof_variant: ?[]const u8 = null,
    kind: FieldMetadataKind,
};

pub const MessageMetadata = struct {
    fields: []const FieldMetadata,
};

pub fn scalarZigType(comptime scalar: ScalarType) type {
    return switch (scalar) {
        .int32, .sint32, .sfixed32 => i32,
        .int64, .sint64, .sfixed64 => i64,
        .uint32, .fixed32 => u32,
        .uint64, .fixed64 => u64,
        .bool => bool,
        .float => f32,
        .double => f64,
        .string, .bytes => []const u8,
    };
}
