const tag = @import("wire/tag.zig");

pub const UnknownField = struct {
    tag: tag.Tag,
    /// Owned bytes: raw wire representation after the tag
    data: []u8,
};
