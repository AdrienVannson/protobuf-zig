/// Wire types as defined in the Protocol Buffers encoding specification.
pub const WireType = enum(u3) {
    /// Used for int32, int64, uint32, uint64, sint32, sint64, bool, enum.
    varint = 0,
    /// Used for fixed64, sfixed64, double. Always 8 bytes, little-endian.
    bit64 = 1,
    /// Used for string, bytes, embedded messages, packed repeated fields.
    length_delimited = 2,
    /// Group start.
    sgroup = 3,
    /// Group end.
    egroup = 4,
    /// Used for fixed32, sfixed32, float. Always 4 bytes, little-endian.
    bit32 = 5,
};
