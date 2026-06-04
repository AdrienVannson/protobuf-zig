const binary_writer = @import("wire/binary_writer.zig");
const binary_reader = @import("wire/binary_reader.zig");
const tag = @import("wire/tag.zig");
const descriptor = @import("descriptor.zig");

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

pub const to_binary = @import("wire/to_binary.zig").to_binary;
pub const from_binary = @import("wire/from_binary.zig").from_binary;

pub const wkt = @import("wkt.zig");

/// Code-generation helpers called by generated `.pb.zig` files.
/// Not intended for direct use by end users.
pub const _codegen = struct {
    pub const deinit_message = @import("_codegen/message_deinit.zig").deinit_message;
    pub const metadata = @import("_codegen/metadata.zig");
    pub const field_access = @import("_codegen/field_access.zig");
};

test {
    _ = @import("wire/binary_writer.zig");
    _ = @import("wire/binary_reader.zig");
    _ = @import("wire/tag.zig");
    _ = @import("descriptor.zig");
    _ = @import("_codegen/metadata.zig");
    _ = @import("_codegen/field_access.zig");
    _ = @import("wire/to_binary.zig");
    _ = @import("wire/from_binary.zig");
    _ = @import("_codegen/message_deinit.zig");
    _ = @import("wkt.zig");
    _ = @import("test/descriptor_roundtrip_test.zig");
}
