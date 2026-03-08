const std = @import("std");

/// Scalar types supported by Protocol Buffers.
/// Values match the FieldDescriptorProto.Type numbering from descriptor.proto.
pub const ScalarType = enum(u5) {
    int32 = 5,
    int64 = 3,
    uint32 = 13,
    uint64 = 4,
    sint32 = 17,
    sint64 = 18,
    fixed32 = 7,
    fixed64 = 6,
    sfixed32 = 15,
    sfixed64 = 16,
    bool = 8,
    float = 2,
    double = 1,
    string = 9,
    bytes = 12,
};

/// Field presence semantics.
pub const FieldPresence = enum {
    explicit,
    implicit,
    legacy_required,
};

/// RPC method streaming kind.
pub const MethodKind = enum {
    unary,
    server_streaming,
    client_streaming,
    bidi_streaming,
};

/// Idempotency level for an RPC method.
pub const IdempotencyLevel = enum {
    idempotency_unknown,
    no_side_effects,
    idempotent,
};

/// Default value for a scalar field.
pub const DefaultValue = union(enum) {
    string: []const u8,
    boolean: bool,
    integer: i64,
    float_val: f64,
    bytes_val: []const u8,
};

/// A member of a message in source order: either a regular field or a oneof group.
pub const DescMember = union(enum) {
    field: *const DescField,
    oneof: *const DescOneof,
};

/// The type carried by a repeated field element or a map field value.
pub const DescElementType = union(enum) {
    scalar: ScalarType,
    message: *const DescMessage,
    enum_type: *const DescEnum,
};

/// Comments attached to a source element.
pub const DescComments = struct {
    /// Paragraphs that appear before but are not directly connected to the element.
    leading_detached: []const []const u8,
    /// Comment directly before the element, or null if absent.
    leading: ?[]const u8,
    /// Comment directly after the element, or null if absent.
    trailing: ?[]const u8,
    /// Source code info path that identifies the element in the file descriptor.
    source_path: []const i32,
};

/// Describes a protobuf source file.
pub const DescFile = struct {
    /// Numeric edition of this file (e.g. 2023 for editions syntax, 2 for proto2, 3 for proto3).
    edition: u32,
    /// File path as declared in the package (e.g. "foo/bar.proto").
    name: []const u8,
    /// Directly imported files, in import-statement order.
    dependencies: []const *const DescFile,
    /// Top-level enumerations declared in this file.
    enums: []const DescEnum,
    /// Top-level messages declared in this file.
    messages: []const DescMessage,
    /// Top-level extensions declared in this file.
    extensions: []const DescExtension,
    /// Services declared in this file.
    services: []const DescService,
    /// Whether this file is marked deprecated.
    deprecated: bool,
};

/// Describes an enumeration.
pub const DescEnum = struct {
    /// Fully-qualified name without a leading dot (e.g. "foo.bar.MyEnum").
    type_name: []const u8,
    /// Simple name as declared in source.
    name: []const u8,
    /// File in which this enum is declared.
    file: *const DescFile,
    /// Enclosing message, or null if this is a top-level enum.
    parent: ?*const DescMessage,
    /// Whether this is an open enum (accepts unknown numeric values).
    open: bool,
    /// All declared values in source order.
    values: []const DescEnumValue,
    /// Map from numeric value to the index of the first DescEnumValue with that number.
    value: std.AutoHashMapUnmanaged(i32, usize),
    /// Shared prefix stripped from value names in generated code, if any.
    shared_prefix: ?[]const u8,
    /// Whether this enum is marked deprecated.
    deprecated: bool,
};

/// Describes a single enumeration value.
pub const DescEnumValue = struct {
    /// Name exactly as declared in source.
    name: []const u8,
    /// Numeric value.
    number: i32,
    /// Whether this value is marked deprecated.
    deprecated: bool,
};

/// Describes a message declaration.
pub const DescMessage = struct {
    /// Fully-qualified name without a leading dot (e.g. "foo.bar.MyMessage").
    type_name: []const u8,
    /// Simple name as declared in source.
    name: []const u8,
    /// File in which this message is declared.
    file: *const DescFile,
    /// Enclosing message, or null if this is a top-level message.
    parent: ?*const DescMessage,
    /// All fields including those inside oneof groups, in field-number order.
    fields: []const DescField,
    /// Map from field local_name to index in fields.
    field: std.StringHashMapUnmanaged(usize),
    /// Oneof groups, excluding synthetic proto3 optional oneofs.
    oneofs: []const DescOneof,
    /// Fields and oneof groups in source declaration order.
    members: []const DescMember,
    /// Nested enumerations.
    nested_enums: []const DescEnum,
    /// Nested messages, excluding synthetic map-entry messages.
    nested_messages: []const DescMessage,
    /// Nested extensions.
    nested_extensions: []const DescExtension,
    /// Whether this message is marked deprecated.
    deprecated: bool,
};

/// Describes a oneof group inside a message.
pub const DescOneof = struct {
    /// Name as declared in source.
    name: []const u8,
    /// Enclosing message.
    parent: *const DescMessage,
    /// The fields that belong to this oneof, in source order.
    fields: []const *const DescField,
};

/// Kind-specific data for a field declared inside a message.
pub const DescFieldKind = union(enum) {
    /// A scalar-typed singular (non-repeated) field.
    scalar: struct {
        /// Oneof group this field belongs to, or null.
        oneof: ?*const DescOneof,
        /// The scalar type.
        scalar: ScalarType,
        /// Declared default value, if any.
        default_value: ?DefaultValue,
    },
    /// A message-typed singular field.
    message_field: struct {
        /// Oneof group this field belongs to, or null.
        oneof: ?*const DescOneof,
        /// The referenced message type.
        message: *const DescMessage,
        /// True when using proto2 group (delimited) encoding instead of length-prefixed.
        delimited_encoding: bool,
    },
    /// An enum-typed singular field.
    enum_field: struct {
        /// Oneof group this field belongs to, or null.
        oneof: ?*const DescOneof,
        /// The referenced enum type.
        enum_type: *const DescEnum,
        /// Declared default value as an enum number, if any.
        default_value: ?i32,
    },
    /// A repeated field.
    list: struct {
        /// Element type.
        element: DescElementType,
        /// Whether packed encoding is used (only valid for numeric scalars and enums).
        is_packed: bool,
        /// True when using proto2 group (delimited) encoding.
        delimited_encoding: bool,
    },
    /// A map field (syntactic sugar over a repeated synthetic-entry message).
    map: struct {
        /// Key scalar type (integral scalars and string; never float, bytes, message, or enum).
        key: ScalarType,
        /// Value type.
        value: DescElementType,
    },
};

/// Describes a field declared inside a message.
pub const DescField = struct {
    /// Name as declared in source.
    name: []const u8,
    /// Name safe for use in generated code (may be renamed to avoid keyword conflicts).
    local_name: []const u8,
    /// Enclosing message.
    parent: *const DescMessage,
    /// Field number.
    number: i32,
    /// JSON name (camelCase by default, overridable in source).
    json_name: []const u8,
    /// Whether this field is marked deprecated.
    deprecated: bool,
    /// Field presence semantics.
    presence: FieldPresence,
    /// Kind and kind-specific data for this field.
    kind: DescFieldKind,
};

/// Kind-specific data for an extension field.
pub const DescExtensionKind = union(enum) {
    /// A scalar-typed extension.
    scalar: struct {
        scalar: ScalarType,
        default_value: ?DefaultValue,
    },
    /// A message-typed extension.
    message_ext: struct {
        message: *const DescMessage,
        delimited_encoding: bool,
    },
    /// An enum-typed extension.
    enum_ext: struct {
        enum_type: *const DescEnum,
        default_value: ?i32,
    },
    /// A repeated extension.
    list: struct {
        element: DescElementType,
        is_packed: bool,
        delimited_encoding: bool,
    },
};

/// Describes an extension field.
pub const DescExtension = struct {
    /// Name as declared in source.
    name: []const u8,
    /// Fully-qualified name without a leading dot.
    type_name: []const u8,
    /// File in which this extension is declared.
    file: *const DescFile,
    /// Enclosing message, or null if this is a top-level extension.
    parent: ?*const DescMessage,
    /// The message type that this extension extends.
    extendee: *const DescMessage,
    /// Field number.
    number: i32,
    /// JSON name.
    json_name: []const u8,
    /// Whether this extension is marked deprecated.
    deprecated: bool,
    /// Field presence semantics.
    presence: FieldPresence,
    /// Kind and kind-specific data for this extension.
    kind: DescExtensionKind,
};

/// Describes a service declaration.
pub const DescService = struct {
    /// Fully-qualified name without a leading dot.
    type_name: []const u8,
    /// Simple name as declared in source.
    name: []const u8,
    /// File in which this service is declared.
    file: *const DescFile,
    /// RPC methods in declaration order.
    methods: []const DescMethod,
    /// Map from method local_name to index in methods.
    method: std.StringHashMapUnmanaged(usize),
    /// Whether this service is marked deprecated.
    deprecated: bool,
};

/// Describes an RPC method declaration.
pub const DescMethod = struct {
    /// Name as declared in source.
    name: []const u8,
    /// Name safe for use in generated code.
    local_name: []const u8,
    /// Enclosing service.
    parent: *const DescService,
    /// Streaming classification of this method.
    method_kind: MethodKind,
    /// Request message type.
    input: *const DescMessage,
    /// Response message type.
    output: *const DescMessage,
    /// Idempotency level declared on this method.
    idempotency: IdempotencyLevel,
    /// Whether this method is marked deprecated.
    deprecated: bool,
};
