const binary_writer = @import("wire/binary_writer.zig");
const tag = @import("wire/tag.zig");
const descriptor = @import("descriptor.zig");
const to_binary_mod = @import("wire/to_binary.zig");
const from_binary_mod = @import("wire/from_binary.zig");
const field_access_mod = @import("field_access.zig");

pub const WireType = tag.WireType;
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

pub const BinaryWriter = binary_writer.BinaryWriter;
pub const to_binary = to_binary_mod.to_binary;
pub const from_binary = from_binary_mod.from_binary;
pub const hasField = field_access_mod.hasField;
pub const getField = field_access_mod.getField;
pub const setField = field_access_mod.setField;

pub const test_types = @import("test/test_all_types_proto3.zig");

test {
    _ = @import("wire/binary_writer.zig");
    _ = @import("wire/tag.zig");
    _ = @import("descriptor.zig");
    _ = @import("metadata.zig");
    _ = @import("wire/to_binary.zig");
    _ = @import("wire/from_binary.zig");
    _ = @import("field_access.zig");
    _ = @import("test/fake_message_foo.zig");
    _ = @import("test/test_all_types_proto3.zig");
}
