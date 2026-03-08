const binary_writer = @import("wire/binary_writer.zig");
const tag = @import("wire/tag.zig");
const to_binary_mod = @import("wire/to_binary.zig");
const from_binary_mod = @import("wire/from_binary.zig");

pub const BinaryWriter = binary_writer.BinaryWriter;
pub const WireType = tag.WireType;
pub const to_binary = to_binary_mod.to_binary;
pub const from_binary = from_binary_mod.from_binary;

test {
    _ = @import("wire/binary_writer.zig");
    _ = @import("wire/tag.zig");
    _ = @import("wire/to_binary.zig");
    _ = @import("wire/from_binary.zig");
}
