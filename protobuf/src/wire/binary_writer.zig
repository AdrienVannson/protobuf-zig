const std = @import("std");
const tag = @import("tag.zig");

const WireType = tag.WireType;

/// Encodes a u64 as a base-128 varint into buf and returns the used slice.
fn encodeVarint(value: u64, buf: *[10]u8) []const u8 {
    var v = value;
    var i: usize = 0;
    while (v > 0x7F) {
        buf[i] = @intCast((v & 0x7F) | 0x80);
        v >>= 7;
        i += 1;
    }
    buf[i] = @intCast(v & 0x7F);
    return buf[0 .. i + 1];
}

/// A writer for serializing Protocol Buffer wire format.
///
/// Length-delimited message fields are handled with fork()/join() pairs.
/// Each fork() opens a new scope and reserves a placeholder for the length
/// varint whose value is not yet known. Each join() closes the scope, fills
/// in the placeholder with the actual byte count, and returns to the
/// enclosing scope.
///
/// All scopes share a single flat chunk list. Each chunk is appended exactly
/// once and never moved or copied, giving O(n) total work where n is the
/// number of bytes serialized.
///
/// All chunks stored in the list are allocator-owned. Call deinit() to free
/// them. Call finish(writer) to flush all chunks to a std.io writer.
pub const BinaryWriter = struct {
    allocator: std.mem.Allocator,
    chunks: std.ArrayList([]u8),
    /// Number of bytes written in the current scope (resets to 0 on fork()).
    size: usize,
    /// Stack of (placeholder_idx, parent_size): pushed by fork(), popped by join().
    stack: std.ArrayList(StackEntry),

    const StackEntry = struct {
        placeholder_idx: usize,
        parent_size: usize,
    };

    pub fn init(allocator: std.mem.Allocator) BinaryWriter {
        return .{
            .allocator = allocator,
            .chunks = .{},
            .size = 0,
            .stack = .{},
        };
    }

    pub fn deinit(self: *BinaryWriter) void {
        for (self.chunks.items) |chunk| {
            self.allocator.free(chunk);
        }
        self.chunks.deinit(self.allocator);
        self.stack.deinit(self.allocator);
    }

    fn write(self: *BinaryWriter, owned: []u8) !void {
        try self.chunks.append(self.allocator, owned);
        self.size += owned.len;
    }

    /// Open a new scope for a length-delimited sub-message field.
    ///
    /// Reserves a placeholder for the length varint and saves the current
    /// scope on the stack. Subsequent writes accumulate into the new scope.
    /// Must be paired with a call to join().
    pub fn fork(self: *BinaryWriter) !void {
        const placeholder_idx = self.chunks.items.len;
        const placeholder = try self.allocator.alloc(u8, 0);
        try self.chunks.append(self.allocator, placeholder);
        try self.stack.append(self.allocator, .{
            .placeholder_idx = placeholder_idx,
            .parent_size = self.size,
        });
        self.size = 0;
    }

    /// Close the current scope and finalize the sub-message length.
    ///
    /// Fills the placeholder reserved by fork() with the actual byte count of
    /// the scope, then restores the enclosing scope.
    pub fn join(self: *BinaryWriter) !void {
        if (self.stack.items.len == 0) return error.JoinWithoutFork;
        const entry = self.stack.pop().?;
        const sub_size = self.size;

        var buf: [10]u8 = undefined;
        const length_slice = encodeVarint(sub_size, &buf);
        const length_owned = try self.allocator.dupe(u8, length_slice);

        self.allocator.free(self.chunks.items[entry.placeholder_idx]);
        self.chunks.items[entry.placeholder_idx] = length_owned;

        self.size = entry.parent_size + length_owned.len + sub_size;
    }

    /// Write the serialized bytes to writer, calling writeAll for each chunk.
    /// Returns error.UnclosedFork if any fork() calls have not been joined.
    pub fn finish(self: *BinaryWriter, writer: anytype) !void {
        if (self.stack.items.len != 0) return error.UnclosedFork;
        for (self.chunks.items) |chunk| {
            try writer.writeAll(chunk);
        }
    }

    /// Write an unsigned integer as a varint.
    pub fn varint(self: *BinaryWriter, value: u64) !void {
        var buf: [10]u8 = undefined;
        const encoded = encodeVarint(value, &buf);
        const owned = try self.allocator.dupe(u8, encoded);
        try self.write(owned);
    }

    /// Write a field tag (field number + wire type).
    pub fn tag(self: *BinaryWriter, number: u32, wire_type: WireType) !void {
        try self.varint((@as(u64, number) << 3) | @intFromEnum(wire_type));
    }

    /// Write a length-delimited byte sequence.
    pub fn bytes(self: *BinaryWriter, value: []const u8) !void {
        try self.varint(value.len);
        const owned = try self.allocator.dupe(u8, value);
        try self.write(owned);
    }

    pub fn uint32(self: *BinaryWriter, value: u32) !void {
        try self.varint(value);
    }

    pub fn int32(self: *BinaryWriter, value: i32) !void {
        try self.varint(@bitCast(@as(i64, value)));
    }

    pub fn int64(self: *BinaryWriter, value: i64) !void {
        try self.varint(@bitCast(value));
    }

    pub fn bool_(self: *BinaryWriter, value: bool) !void {
        try self.varint(if (value) 1 else 0);
    }

    pub fn sint32(self: *BinaryWriter, value: i32) !void {
        const zz = @as(u32, @bitCast((value << 1) ^ (value >> 31)));
        try self.varint(zz);
    }

    pub fn sint64(self: *BinaryWriter, value: i64) !void {
        const zz = @as(u64, @bitCast((value << 1) ^ (value >> 63)));
        try self.varint(zz);
    }

    pub fn fixed32(self: *BinaryWriter, value: u32) !void {
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &buf, value, .little);
        const owned = try self.allocator.dupe(u8, &buf);
        try self.write(owned);
    }

    pub fn sfixed32(self: *BinaryWriter, value: i32) !void {
        try self.fixed32(@bitCast(value));
    }

    pub fn float_(self: *BinaryWriter, value: f32) !void {
        try self.fixed32(@bitCast(value));
    }

    pub fn fixed64(self: *BinaryWriter, value: u64) !void {
        var buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &buf, value, .little);
        const owned = try self.allocator.dupe(u8, &buf);
        try self.write(owned);
    }

    pub fn sfixed64(self: *BinaryWriter, value: i64) !void {
        try self.fixed64(@bitCast(value));
    }

    pub fn double(self: *BinaryWriter, value: f64) !void {
        try self.fixed64(@bitCast(value));
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

// varint

test "varint zero" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.varint(0);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{0x00}, buf.items);
}

test "varint one" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.varint(1);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{0x01}, buf.items);
}

test "varint 127" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.varint(127);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{0x7f}, buf.items);
}

test "varint 128" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.varint(128);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{ 0x80, 0x01 }, buf.items);
}

test "varint 150" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.varint(150);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{ 0x96, 0x01 }, buf.items);
}

test "varint max u64" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.varint(std.math.maxInt(u64));
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01,
    }, buf.items);
}

test "varint multiple" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.varint(1);
    try w.varint(150);
    try w.varint(0);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{ 0x01, 0x96, 0x01, 0x00 }, buf.items);
}

// tag

test "tag field 1 varint" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.tag(1, .varint);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{0x08}, buf.items);
}

test "tag field 2 length_delimited" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.tag(2, .length_delimited);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{0x12}, buf.items);
}

test "tag large field number" {
    // Max field number for protobuf is 536870911 = (1<<29)-1.
    // tag = (536870911 << 3) | 0 = 4294967288, encoded as 5-byte varint.
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.tag(536870911, .varint);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    // (536870911 << 3) = 4294967288 = 0xFFFFFFF8
    // varint: f8 ff ff ff 0f
    try testing.expectEqualSlices(u8, &.{ 0xf8, 0xff, 0xff, 0xff, 0x0f }, buf.items);
}

// bytes

test "bytes empty" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.bytes(&.{});
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{0x00}, buf.items);
}

test "bytes simple" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.bytes("hello");
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{ 0x05, 'h', 'e', 'l', 'l', 'o' }, buf.items);
}

// fork / join

test "fork join empty sub-message" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.fork();
    try w.join();
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{0x00}, buf.items);
}

test "fork join simple sub-message" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.fork();
    try w.varint(42);
    try w.join();
    // varint(42) = 0x2a (1 byte), so length prefix is 0x01
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{ 0x01, 0x2a }, buf.items);
}

test "fork join matches bytes encoding" {
    const payload: []const u8 = &.{ 0x08, 0x0c };

    var fw = BinaryWriter.init(testing.allocator);
    defer fw.deinit();
    try fw.fork();
    const owned = try testing.allocator.dupe(u8, payload);
    try fw.write(owned);
    try fw.join();
    var fw_buf = std.ArrayList(u8){};
    defer fw_buf.deinit(testing.allocator);
    try fw.finish(fw_buf.writer(testing.allocator));

    var bw = BinaryWriter.init(testing.allocator);
    defer bw.deinit();
    try bw.bytes(payload);
    var bw_buf = std.ArrayList(u8){};
    defer bw_buf.deinit(testing.allocator);
    try bw.finish(bw_buf.writer(testing.allocator));

    try testing.expectEqualSlices(u8, bw_buf.items, fw_buf.items);
}

test "fork join with tag" {
    // tag(1, LENGTH_DELIMITED) + fork + varint(12) + join
    // Expected: 0x0a 0x01 0x0c
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.tag(1, .length_delimited);
    try w.fork();
    try w.varint(12);
    try w.join();
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{ 0x0a, 0x01, 0x0c }, buf.items);
}

test "fork join nested" {
    // Outer: tag(1, LD) + [ Inner: tag(1, LD) + [ varint(7) ] ]
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.tag(1, .length_delimited);
    try w.fork();
    try w.tag(1, .length_delimited);
    try w.fork();
    try w.varint(7);
    try w.join();
    try w.join();
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    // inner content: varint(7) = 0x07 (1 byte)
    // inner field:   tag(1,LD)=0x0a, length=0x01, value=0x07  → 3 bytes
    // outer field:   tag(1,LD)=0x0a, length=0x03, 3 bytes
    try testing.expectEqualSlices(u8, &.{ 0x0a, 0x03, 0x0a, 0x01, 0x07 }, buf.items);
}

test "fork join wide nesting" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    for (0..5) |i| {
        try w.tag(@intCast(i + 1), .length_delimited);
        try w.fork();
        try w.varint(@intCast(i * 10));
        try w.join();
    }
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));

    // Verify each field manually: tag(n, LD), length=1, varint(n*10)
    var offset: usize = 0;
    for (0..5) |i| {
        const expected_tag: u8 = @intCast(((i + 1) << 3) | 2);
        try testing.expectEqual(expected_tag, buf.items[offset]);
        offset += 1;
        try testing.expectEqual(@as(u8, 1), buf.items[offset]); // length = 1
        offset += 1;
        try testing.expectEqual(@as(u8, @intCast(i * 10)), buf.items[offset]);
        offset += 1;
    }
    try testing.expectEqual(buf.items.len, offset);
}

// finish

test "finish empty writer" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{}, buf.items);
}

test "finish complete message" {
    // Field 1, VARINT, value 12: tag=0x08, value=0x0c
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.tag(1, .varint);
    try w.varint(12);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{ 0x08, 0x0c }, buf.items);
}

test "join without fork returns error" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try testing.expectError(error.JoinWithoutFork, w.join());
}

test "finish with unclosed fork returns error" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.fork();
    try testing.expectError(error.UnclosedFork, w.finish(std.io.null_writer));
    // Clean up the unclosed fork so deinit works cleanly.
    try w.join();
}

test "uint32 300" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.uint32(300);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{ 0xac, 0x02 }, buf.items);
}

test "int32 -1" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.int32(-1);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01,
    }, buf.items);
}

test "int64 -1" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.int64(-1);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01,
    }, buf.items);
}

test "bool_ true" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.bool_(true);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{0x01}, buf.items);
}

test "sint32 -1" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.sint32(-1);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{0x01}, buf.items);
}

test "sint64 -1" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.sint64(-1);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{0x01}, buf.items);
}

test "fixed32 1" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.fixed32(1);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{ 0x01, 0x00, 0x00, 0x00 }, buf.items);
}

test "sfixed32 -1" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.sfixed32(-1);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{ 0xff, 0xff, 0xff, 0xff }, buf.items);
}

test "float_ 1.0" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.float_(1.0);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{ 0x00, 0x00, 0x80, 0x3f }, buf.items);
}

test "fixed64 1" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.fixed64(1);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{ 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, buf.items);
}

test "sfixed64 -1" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.sfixed64(-1);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, buf.items);
}

test "double 1.0" {
    var w = BinaryWriter.init(testing.allocator);
    defer w.deinit();
    try w.double(1.0);
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    try testing.expectEqualSlices(u8, &.{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xf0, 0x3f }, buf.items);
}
