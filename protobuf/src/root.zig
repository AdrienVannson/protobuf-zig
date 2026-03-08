const binary_writer = @import("wire/binary_writer.zig");
const tag = @import("wire/tag.zig");

pub const BinaryWriter = binary_writer.BinaryWriter;
pub const WireType = tag.WireType;
