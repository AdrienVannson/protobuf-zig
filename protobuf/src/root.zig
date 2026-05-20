const binary_writer = @import("wire/binary_writer.zig");
const binary_reader = @import("wire/binary_reader.zig");
const tag = @import("wire/tag.zig");
const descriptor = @import("descriptor.zig");
const to_binary_mod = @import("wire/to_binary.zig");
const from_binary_mod = @import("wire/from_binary.zig");

pub const WireType = tag.WireType;
pub const Tag = tag.Tag;
pub const ScalarType = descriptor.ScalarType;
pub const FieldPresence = descriptor.FieldPresence;
pub const DefaultValue = descriptor.DefaultValue;
pub const DescMember = descriptor.DescMember;
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

pub const to_binary = to_binary_mod.to_binary;
pub const from_binary = from_binary_mod.from_binary;

/// Internal contract between `protoc-gen-zig` and the runtime codec.
/// Not intended for direct use by end users.
pub const _metadata = @import("metadata.zig");

test {
    _ = @import("wire/binary_writer.zig");
    _ = @import("wire/binary_reader.zig");
    _ = @import("wire/tag.zig");
    _ = @import("descriptor.zig");
    _ = @import("metadata.zig");
    _ = @import("wire/to_binary.zig");
    _ = @import("wire/from_binary.zig");
    _ = @import("test/fake_message_foo.zig");
    _ = @import("test/descriptor_roundtrip_test.zig");
}
