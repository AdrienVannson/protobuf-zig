const binary_writer = @import("wire/binary_writer.zig");
const tag = @import("wire/tag.zig");
const message = @import("message.zig");

pub const BinaryWriter = binary_writer.BinaryWriter;
pub const WireType = tag.WireType;
pub const to_binary = message.to_binary;
pub const from_binary = message.from_binary;

test {
    _ = @import("wire/binary_writer.zig");
    _ = @import("wire/tag.zig");
    _ = @import("message.zig");
}
