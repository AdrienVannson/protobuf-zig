const binary_writer = @import("wire/binary_writer.zig");
const tag = @import("wire/tag.zig");
const descriptor = @import("descriptor.zig");

pub const BinaryWriter = binary_writer.BinaryWriter;
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

test {
    _ = @import("wire/binary_writer.zig");
    _ = @import("wire/tag.zig");
    _ = @import("descriptor.zig");
}
