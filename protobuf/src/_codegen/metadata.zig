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
        // Declared default value, if any. Defaults to null (no explicit default).
        default_value: ?DefaultValue = null,
    },
    message_field: struct {
        delimited_encoding: bool = false,
    },
    enum_field: struct {
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
    presence: SupportedFieldPresence = .explicit,
    kind: FieldMetadataKind,
};

pub const MessageMetadata = struct {
    fields: []const FieldMetadata,
};
