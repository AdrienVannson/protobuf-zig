const descriptor = @import("descriptor.zig");

pub const ScalarType = descriptor.ScalarType;
pub const DefaultValue = descriptor.DefaultValue;
pub const FieldPresence = descriptor.FieldPresence;

/// Simplified element type for list/map fields.
/// Drops full descriptor pointers since actual Zig types are resolved at comptime.
pub const FieldMetadataElementType = union(enum) {
    scalar: ScalarType,
    message: void,
    enum_type: void,
};

/// Kind-specific data for encoding/decoding.
/// Drops oneof fields (transparent on the binary wire) and rich descriptor pointers.
pub const FieldMetadataKind = union(enum) {
    scalar: struct {
        scalar: ScalarType,
        default_value: ?DefaultValue,
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

/// Lean field descriptor carrying only what encoding/decoding needs.
pub const FieldMetadata = struct {
    number: i32,
    presence: FieldPresence = .explicit,
    kind: FieldMetadataKind,
};

/// Lean message descriptor: a list of field metadata entries, one per field.
pub const MessageMetadata = struct {
    fields: []const FieldMetadata,
};
