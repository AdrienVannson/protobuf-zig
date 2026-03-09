const descriptor = @import("descriptor.zig");

pub const ScalarType = descriptor.ScalarType;
pub const DefaultValue = descriptor.DefaultValue;
pub const FieldPresence = descriptor.FieldPresence;

pub const FieldMetadataElementType = union(enum) {
    scalar: ScalarType,
    message: *const MessageMetadata,
    enum_type: void,
};

pub const FieldMetadataKind = union(enum) {
    scalar: struct {
        scalar: ScalarType,
        default_value: ?DefaultValue,
    },
    message_field: struct {
        delimited_encoding: bool = false,
        message_metadata: *const MessageMetadata,
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
    number: i32,
    presence: FieldPresence = .explicit,
    kind: FieldMetadataKind,
};

pub const MessageMetadata = struct {
    fields: []const FieldMetadata,
};
