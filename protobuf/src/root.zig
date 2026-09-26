const binary_writer = @import("wire/binary_writer.zig");
const binary_reader = @import("wire/binary_reader.zig");
const descriptor = @import("descriptor.zig");
const registry = @import("registry.zig");
const tag = @import("wire/tag.zig");

// TODO move under `descriptor`?
pub const WireType = tag.WireType;
pub const Tag = tag.Tag;
pub const ScalarType = descriptor.ScalarType;
pub const SupportedEdition = descriptor.SupportedEdition;
pub const SupportedFieldPresence = descriptor.SupportedFieldPresence;
pub const DefaultValue = descriptor.DefaultValue;
pub const DescMessageMember = descriptor.DescMessageMember;
pub const DescElementType = descriptor.DescElementType;
pub const DescComments = descriptor.DescComments;
pub const DescFile = descriptor.DescFile;
pub const DescEnum = descriptor.DescEnum;
pub const DescEnumValue = descriptor.DescEnumValue;
pub const DescMessage = descriptor.DescMessage;
pub const DescOneof = descriptor.DescOneof;
pub const DescFieldKind = descriptor.DescFieldKind;
pub const DescField = descriptor.DescField;
pub const DescExtensionKind = descriptor.DescExtensionKind;
pub const DescExtension = descriptor.DescExtension;

pub const toBinary = @import("wire/to_binary.zig").toBinary;
pub const fromBinary = @import("wire/from_binary.zig").fromBinary;
pub const toJson = @import("json/to_json.zig").toJson;
pub const fromJson = @import("json/from_json.zig").fromJson;

pub const UnknownField = @import("unknown_field.zig").UnknownField;

pub const Registry = registry.Registry;
pub const MessageOps = registry.MessageOps;

pub const wkt = @import("wkt.zig");

/// Code-generation helpers called by generated `.pb.zig` files.
/// Not intended for direct use by end users.
pub const _codegen = struct {
    pub const deinitMessage = @import("_codegen/message_deinit.zig").deinitMessage;
    pub const any = @import("_codegen/wkt/any.zig");
    pub const metadata = @import("_codegen/metadata.zig");
    pub const field_access = @import("_codegen/field_access.zig");
    pub const readMessageMetadata = @import("_codegen/read_metadata.zig").readMessageMetadata;
    pub const descFileFromProto = @import("_codegen/desc_file_from_proto.zig").descFileFromProto;
    pub const OwnedDescFile = @import("_codegen/desc_file_from_proto.zig").OwnedDescFile;
    pub const FileDescFn = @import("_codegen/file_desc.zig").FileDescFn;
    pub const fileDesc = @import("_codegen/file_desc.zig").fileDesc;
    pub const messageDescAt = @import("_codegen/file_desc.zig").messageDescAt;
};

test {
    _ = @import("wire/binary_writer.zig");
    _ = @import("wire/binary_reader.zig");
    _ = @import("unknown_field.zig");
    _ = @import("wire/tag.zig");
    _ = @import("descriptor.zig");
    _ = @import("_codegen/metadata.zig");
    _ = @import("_codegen/read_metadata.zig");
    _ = @import("_codegen/field_access.zig");
    _ = @import("wire/to_binary.zig");
    _ = @import("wire/from_binary.zig");
    _ = @import("json/to_json.zig");
    _ = @import("json/from_json.zig");
    _ = @import("json/wkt_time.zig");
    _ = @import("_codegen/message_deinit.zig");
    _ = @import("_codegen/wkt/any.zig");
    _ = @import("_codegen/desc_file_from_proto.zig");
    _ = @import("_codegen/file_desc.zig");
    _ = @import("wkt.zig");
    _ = @import("registry.zig");
    _ = @import("test/descriptor_roundtrip_test.zig");
    _ = @import("test/test_desc.zig");
}
