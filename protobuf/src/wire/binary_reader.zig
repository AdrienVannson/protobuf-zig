const std = @import("std");
const tag_mod = @import("tag.zig");

const WireType = tag_mod.WireType;
const Tag = tag_mod.Tag;

/// Decodes a base-128 varint from data starting at pos.*. On success, advances
/// pos.* past the varint and returns the decoded value. On failure, pos.* is
/// not modified.
fn decodeVarint(data: []const u8, pos: *usize, end: usize) !u64 {
    var result: u64 = 0;
    var shift: u6 = 0;
    var i: usize = pos.*;
    var bytes_read: usize = 0;
    while (bytes_read < 10) : (bytes_read += 1) {
        if (i >= end) return error.UnexpectedEof;
        const byte = data[i];
        i += 1;
        if (bytes_read == 9) {
            // The 10th byte may only contribute 1 bit (9*7 + 1 = 64).
            if ((byte & 0x7F) > 0x01) return error.InvalidVarint;
            result |= @as(u64, byte & 0x7F) << shift;
            if ((byte & 0x80) != 0) return error.InvalidVarint;
            pos.* = i;
            return result;
        }
        result |= @as(u64, byte & 0x7F) << shift;
        if ((byte & 0x80) == 0) {
            pos.* = i;
            return result;
        }
        shift += 7;
    }
    return error.InvalidVarint;
}

/// A reader for deserializing Protocol Buffer wire format.
///
/// Length-delimited message fields are handled with fork()/join() pairs.
/// Each fork() reads a length prefix, narrows the visible end of the buffer
/// to the sub-message's last byte, and saves the enclosing scope's end on a
/// stack. Each join() verifies the sub-message was fully consumed and
/// restores the enclosing scope.
///
/// The reader operates on an external []const u8 buffer that it does not own.
/// Scalar reads do not allocate. bytes() and string() return caller-owned
/// copies allocated with the reader's allocator; the caller is responsible
/// for freeing them.
pub const BinaryReader = struct {
    allocator: std.mem.Allocator,
    data: []const u8,
    /// Current read cursor.
    pos: usize,
    /// Upper bound (exclusive) of the current scope. Reads past this are EOF.
    end: usize,
    /// Stack of saved end values: pushed by fork(), popped by join().
    stack: std.ArrayList(usize),

    pub fn init(allocator: std.mem.Allocator, data: []const u8) BinaryReader {
        return .{
            .allocator = allocator,
            .data = data,
            .pos = 0,
            .end = data.len,
            .stack = .{},
        };
    }

    pub fn deinit(self: *BinaryReader) void {
        self.stack.deinit(self.allocator);
    }

    /// Returns true when the cursor has reached the end of the current scope.
    pub fn eof(self: *const BinaryReader) bool {
        return self.pos == self.end;
    }

    /// Open a length-delimited sub-message scope.
    ///
    /// Reads a varint length prefix, saves the current scope's end on the
    /// stack, and narrows end to the sub-message boundary. Subsequent reads
    /// are confined to the sub-message until join() is called.
    pub fn fork(self: *BinaryReader) !void {
        const len = try decodeVarint(self.data, &self.pos, self.end);
        const len_usize = std.math.cast(usize, len) orelse return error.LengthExceedsBuffer;
        if (len_usize > self.end - self.pos) return error.LengthExceedsBuffer;
        try self.stack.append(self.allocator, self.end);
        self.end = self.pos + len_usize;
    }

    /// Close the current sub-message scope.
    ///
    /// Verifies the sub-message was fully consumed and restores the enclosing
    /// scope's end.
    pub fn join(self: *BinaryReader) !void {
        if (self.stack.items.len == 0) return error.JoinWithoutFork;
        if (self.pos != self.end) return error.UnconsumedBytes;
        self.end = self.stack.pop().?;
    }

    /// Verify the reader has fully consumed its input with no open forks.
    pub fn finish(self: *const BinaryReader) !void {
        if (self.stack.items.len != 0) return error.UnclosedFork;
        if (self.pos != self.end) return error.UnconsumedBytes;
    }

    /// Consume one field's payload after its tag has been read.
    pub fn skipField(self: *BinaryReader, wire_type: WireType) !void {
        switch (wire_type) {
            .varint => _ = try self.varint(),
            .bit32 => {
                if (self.end - self.pos < 4) return error.UnexpectedEof;
                self.pos += 4;
            },
            .bit64 => {
                if (self.end - self.pos < 8) return error.UnexpectedEof;
                self.pos += 8;
            },
            .length_delimited => {
                const len = try self.varint();
                const n = std.math.cast(usize, len) orelse return error.LengthExceedsBuffer;
                if (n > self.end - self.pos) return error.LengthExceedsBuffer;
                self.pos += n;
            },
            .sgroup, .egroup => return error.UnsupportedWireType,
        }
    }

    /// Read an unsigned integer encoded as a varint.
    pub fn varint(self: *BinaryReader) !u64 {
        return decodeVarint(self.data, &self.pos, self.end);
    }

    /// Read a field tag (field number + wire type).
    pub fn tag(self: *BinaryReader) !Tag {
        const v = try self.varint();
        const number = std.math.cast(u32, v >> 3) orelse return error.InvalidVarint;
        const wire_raw: u3 = @intCast(v & 0x07);
        return .{
            .number = number,
            .wire_type = @enumFromInt(wire_raw),
        };
    }

    pub fn int32(self: *BinaryReader) !i32 {
        const v = try self.varint();
        return @truncate(@as(i64, @bitCast(v)));
    }

    pub fn int64(self: *BinaryReader) !i64 {
        const v = try self.varint();
        return @bitCast(v);
    }

    pub fn uint32(self: *BinaryReader) !u32 {
        const v = try self.varint();
        return std.math.cast(u32, v) orelse return error.InvalidVarint;
    }

    pub fn uint64(self: *BinaryReader) !u64 {
        return self.varint();
    }

    pub fn sint32(self: *BinaryReader) !i32 {
        const v = try self.varint();
        const u: u32 = std.math.cast(u32, v) orelse return error.InvalidVarint;
        return @bitCast((u >> 1) ^ (0 -% (u & 1)));
    }

    pub fn sint64(self: *BinaryReader) !i64 {
        const v = try self.varint();
        return @bitCast((v >> 1) ^ (0 -% (v & 1)));
    }

    fn readFixed(self: *BinaryReader, comptime T: type) !T {
        const size = @sizeOf(T);
        if (self.end - self.pos < size) return error.UnexpectedEof;
        const value = std.mem.readInt(T, self.data[self.pos..][0..size], .little);
        self.pos += size;
        return value;
    }

    pub fn fixed32(self: *BinaryReader) !u32 {
        return self.readFixed(u32);
    }

    pub fn fixed64(self: *BinaryReader) !u64 {
        return self.readFixed(u64);
    }

    pub fn sfixed32(self: *BinaryReader) !i32 {
        return @bitCast(try self.fixed32());
    }

    pub fn sfixed64(self: *BinaryReader) !i64 {
        return @bitCast(try self.fixed64());
    }

    pub fn bool_(self: *BinaryReader) !bool {
        const v = try self.varint();
        return v != 0;
    }

    pub fn float_(self: *BinaryReader) !f32 {
        return @bitCast(try self.fixed32());
    }

    pub fn double(self: *BinaryReader) !f64 {
        return @bitCast(try self.fixed64());
    }

    /// Read a length-delimited byte sequence. Returns a caller-owned copy
    /// allocated with the reader's allocator; free with the same allocator.
    pub fn bytes(self: *BinaryReader) ![]u8 {
        const len = try self.varint();
        const len_usize = std.math.cast(usize, len) orelse return error.LengthExceedsBuffer;
        if (len_usize > self.end - self.pos) return error.LengthExceedsBuffer;
        const owned = try self.allocator.dupe(u8, self.data[self.pos..][0..len_usize]);
        self.pos += len_usize;
        return owned;
    }

    pub fn string(self: *BinaryReader) ![]u8 {
        return self.bytes();
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const BinaryWriter = @import("binary_writer.zig").BinaryWriter;

fn writerToOwnedSlice(w: *BinaryWriter) ![]u8 {
    defer w.deinit();
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);
    try w.finish(buf.writer(testing.allocator));
    return testing.allocator.dupe(u8, buf.items);
}

fn expectReaderConsumed(r: *BinaryReader) !void {
    defer r.deinit();
    try r.finish();
}

// varint

test "varint zero" {
    var r = BinaryReader.init(testing.allocator, &.{0x00});
    try testing.expectEqual(@as(u64, 0), try r.varint());
    try expectReaderConsumed(&r);
}

test "varint 127" {
    var r = BinaryReader.init(testing.allocator, &.{0x7f});
    try testing.expectEqual(@as(u64, 127), try r.varint());
    try expectReaderConsumed(&r);
}

test "varint 128" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x80, 0x01 });
    try testing.expectEqual(@as(u64, 128), try r.varint());
    try expectReaderConsumed(&r);
}

test "varint 150" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x96, 0x01 });
    try testing.expectEqual(@as(u64, 150), try r.varint());
    try expectReaderConsumed(&r);
}

test "varint max u64" {
    var r = BinaryReader.init(testing.allocator, &.{
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01,
    });
    try testing.expectEqual(std.math.maxInt(u64), try r.varint());
    try expectReaderConsumed(&r);
}

test "varint truncated" {
    var r = BinaryReader.init(testing.allocator, &.{0x80});
    defer r.deinit();
    try testing.expectError(error.UnexpectedEof, r.varint());
}

test "varint 11 bytes" {
    var r = BinaryReader.init(testing.allocator, &.{
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01,
    });
    defer r.deinit();
    try testing.expectError(error.InvalidVarint, r.varint());
}

test "varint 10th byte overflow" {
    // 10th byte's value bits exceed 1 → would overflow u64.
    var r = BinaryReader.init(testing.allocator, &.{
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x02,
    });
    defer r.deinit();
    try testing.expectError(error.InvalidVarint, r.varint());
}

// tag

test "tag field 1 varint" {
    var r = BinaryReader.init(testing.allocator, &.{0x08});
    const t = try r.tag();
    try testing.expectEqual(@as(u32, 1), t.number);
    try testing.expectEqual(WireType.varint, t.wire_type);
    try expectReaderConsumed(&r);
}

test "tag field 2 length_delimited" {
    var r = BinaryReader.init(testing.allocator, &.{0x12});
    const t = try r.tag();
    try testing.expectEqual(@as(u32, 2), t.number);
    try testing.expectEqual(WireType.length_delimited, t.wire_type);
    try expectReaderConsumed(&r);
}

test "tag large field number" {
    var r = BinaryReader.init(testing.allocator, &.{ 0xf8, 0xff, 0xff, 0xff, 0x0f });
    const t = try r.tag();
    try testing.expectEqual(@as(u32, 536870911), t.number);
    try testing.expectEqual(WireType.varint, t.wire_type);
    try expectReaderConsumed(&r);
}

// scalar types (round-trip via writer)

test "int32 -123" {
    var w = BinaryWriter.init(testing.allocator);
    try w.int32(-123);
    const buf = try writerToOwnedSlice(&w);
    defer testing.allocator.free(buf);

    var r = BinaryReader.init(testing.allocator, buf);
    try testing.expectEqual(@as(i32, -123), try r.int32());
    try expectReaderConsumed(&r);
}

test "int64 -9876543210" {
    var w = BinaryWriter.init(testing.allocator);
    try w.int64(-9876543210);
    const buf = try writerToOwnedSlice(&w);
    defer testing.allocator.free(buf);

    var r = BinaryReader.init(testing.allocator, buf);
    try testing.expectEqual(@as(i64, -9876543210), try r.int64());
    try expectReaderConsumed(&r);
}

test "uint32 123" {
    var r = BinaryReader.init(testing.allocator, &.{0x7b});
    try testing.expectEqual(@as(u32, 123), try r.uint32());
    try expectReaderConsumed(&r);
}

test "uint64 9876543210" {
    var r = BinaryReader.init(testing.allocator, &.{ 0xea, 0xad, 0xc0, 0xe5, 0x24 });
    try testing.expectEqual(@as(u64, 9876543210), try r.uint64());
    try expectReaderConsumed(&r);
}

test "sint32 -123" {
    var r = BinaryReader.init(testing.allocator, &.{ 0xf5, 0x01 });
    try testing.expectEqual(@as(i32, -123), try r.sint32());
    try expectReaderConsumed(&r);
}

test "sint64 -9876543210" {
    var r = BinaryReader.init(testing.allocator, &.{ 0xd3, 0xdb, 0x80, 0xcb, 0x49 });
    try testing.expectEqual(@as(i64, -9876543210), try r.sint64());
    try expectReaderConsumed(&r);
}

test "fixed32 123" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x7b, 0x00, 0x00, 0x00 });
    try testing.expectEqual(@as(u32, 123), try r.fixed32());
    try expectReaderConsumed(&r);
}

test "fixed64 9876543210" {
    var r = BinaryReader.init(testing.allocator, &.{ 0xea, 0x16, 0xb0, 0x4c, 0x02, 0x00, 0x00, 0x00 });
    try testing.expectEqual(@as(u64, 9876543210), try r.fixed64());
    try expectReaderConsumed(&r);
}

test "sfixed32 -123" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x85, 0xff, 0xff, 0xff });
    try testing.expectEqual(@as(i32, -123), try r.sfixed32());
    try expectReaderConsumed(&r);
}

test "sfixed64 -9876543210" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x16, 0xe9, 0x4f, 0xb3, 0xfd, 0xff, 0xff, 0xff });
    try testing.expectEqual(@as(i64, -9876543210), try r.sfixed64());
    try expectReaderConsumed(&r);
}

test "bool_ true" {
    var r = BinaryReader.init(testing.allocator, &.{0x01});
    try testing.expectEqual(true, try r.bool_());
    try expectReaderConsumed(&r);
}

test "bool_ false" {
    var r = BinaryReader.init(testing.allocator, &.{0x00});
    try testing.expectEqual(false, try r.bool_());
    try expectReaderConsumed(&r);
}

test "float_ 123.0" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x00, 0x00, 0xf6, 0x42 });
    try testing.expectEqual(@as(f32, 123.0), try r.float_());
    try expectReaderConsumed(&r);
}

test "double 9876543210.0" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x00, 0x00, 0x50, 0xb7, 0x80, 0x65, 0x02, 0x42 });
    try testing.expectEqual(@as(f64, 9876543210.0), try r.double());
    try expectReaderConsumed(&r);
}

test "fixed32 truncated" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x01, 0x02 });
    defer r.deinit();
    try testing.expectError(error.UnexpectedEof, r.fixed32());
}

test "fixed64 truncated" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x01, 0x02, 0x03 });
    defer r.deinit();
    try testing.expectError(error.UnexpectedEof, r.fixed64());
}

// bytes / string

test "bytes empty" {
    var r = BinaryReader.init(testing.allocator, &.{0x00});
    const out = try r.bytes();
    defer testing.allocator.free(out);
    try testing.expectEqualSlices(u8, &.{}, out);
    try expectReaderConsumed(&r);
}

test "bytes simple" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x05, 'h', 'e', 'l', 'l', 'o' });
    const out = try r.bytes();
    defer testing.allocator.free(out);
    try testing.expectEqualSlices(u8, "hello", out);
    try expectReaderConsumed(&r);
}

test "string simple" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x05, 'h', 'e', 'l', 'l', 'o' });
    const out = try r.string();
    defer testing.allocator.free(out);
    try testing.expectEqualSlices(u8, "hello", out);
    try expectReaderConsumed(&r);
}

test "bytes length exceeds buffer" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x05, 'h', 'i' });
    defer r.deinit();
    try testing.expectError(error.LengthExceedsBuffer, r.bytes());
}

test "bytes truncated payload after valid length" {
    // length=2 but only 1 byte of payload available
    var r = BinaryReader.init(testing.allocator, &.{ 0x02, 'a' });
    defer r.deinit();
    try testing.expectError(error.LengthExceedsBuffer, r.bytes());
}

// fork / join

test "fork join simple sub-message" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x01, 0x2a });
    try r.fork();
    try testing.expectEqual(@as(u64, 42), try r.varint());
    try r.join();
    try expectReaderConsumed(&r);
}

test "fork join with tag" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x0a, 0x01, 0x0c });
    const t = try r.tag();
    try testing.expectEqual(@as(u32, 1), t.number);
    try testing.expectEqual(WireType.length_delimited, t.wire_type);
    try r.fork();
    try testing.expectEqual(@as(u64, 12), try r.varint());
    try r.join();
    try expectReaderConsumed(&r);
}

test "fork join nested" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x0a, 0x03, 0x0a, 0x01, 0x07 });
    const outer = try r.tag();
    try testing.expectEqual(@as(u32, 1), outer.number);
    try r.fork();
    const inner = try r.tag();
    try testing.expectEqual(@as(u32, 1), inner.number);
    try r.fork();
    try testing.expectEqual(@as(u64, 7), try r.varint());
    try r.join();
    try r.join();
    try expectReaderConsumed(&r);
}

test "fork eof terminates field loop" {
    // Two fields inside a sub-message: tag(1, varint)+varint(1), tag(2, varint)+varint(2).
    // Outer payload length = 4 bytes.
    var r = BinaryReader.init(testing.allocator, &.{ 0x04, 0x08, 0x01, 0x10, 0x02 });
    try r.fork();
    var seen: u32 = 0;
    while (!r.eof()) {
        const t = try r.tag();
        const v = try r.varint();
        seen += 1;
        try testing.expectEqual(@as(u64, t.number), v);
    }
    try testing.expectEqual(@as(u32, 2), seen);
    try r.join();
    try expectReaderConsumed(&r);
}

test "fork length exceeds parent scope" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x05, 0x01, 0x02 });
    defer r.deinit();
    try testing.expectError(error.LengthExceedsBuffer, r.fork());
}

test "join without fork returns error" {
    var r = BinaryReader.init(testing.allocator, &.{});
    defer r.deinit();
    try testing.expectError(error.JoinWithoutFork, r.join());
}

test "join with unconsumed bytes returns error" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x02, 0x01, 0x02 });
    defer r.deinit();
    try r.fork();
    // Read only one of the two payload bytes.
    _ = try r.varint();
    try testing.expectError(error.UnconsumedBytes, r.join());
}

test "finish with unclosed fork returns error" {
    var r = BinaryReader.init(testing.allocator, &.{0x00});
    defer r.deinit();
    try r.fork();
    try testing.expectError(error.UnclosedFork, r.finish());
    try r.join();
}

test "finish with unconsumed bytes returns error" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x01, 0x02 });
    defer r.deinit();
    _ = try r.varint();
    try testing.expectError(error.UnconsumedBytes, r.finish());
}

test "finish empty reader" {
    var r = BinaryReader.init(testing.allocator, &.{});
    try expectReaderConsumed(&r);
}

// skipField

test "skipField varint" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x2a, 0x08 });
    try r.skipField(.varint);
    try testing.expectEqual(@as(u64, 8), try r.varint());
    try expectReaderConsumed(&r);
}

test "skipField bit32" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x01, 0x02, 0x03, 0x04, 0x2a });
    try r.skipField(.bit32);
    try testing.expectEqual(@as(u64, 42), try r.varint());
    try expectReaderConsumed(&r);
}

test "skipField bit64" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x2a });
    try r.skipField(.bit64);
    try testing.expectEqual(@as(u64, 42), try r.varint());
    try expectReaderConsumed(&r);
}

test "skipField length_delimited" {
    // length=3, payload "abc", then varint 42
    var r = BinaryReader.init(testing.allocator, &.{ 0x03, 'a', 'b', 'c', 0x2a });
    try r.skipField(.length_delimited);
    try testing.expectEqual(@as(u64, 42), try r.varint());
    try expectReaderConsumed(&r);
}

test "skipField sgroup returns error" {
    var r = BinaryReader.init(testing.allocator, &.{});
    defer r.deinit();
    try testing.expectError(error.UnsupportedWireType, r.skipField(.sgroup));
}

test "skipField egroup returns error" {
    var r = BinaryReader.init(testing.allocator, &.{});
    defer r.deinit();
    try testing.expectError(error.UnsupportedWireType, r.skipField(.egroup));
}

test "skipField varint truncated" {
    var r = BinaryReader.init(testing.allocator, &.{0x80});
    defer r.deinit();
    try testing.expectError(error.UnexpectedEof, r.skipField(.varint));
}

test "skipField bit32 truncated" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x01, 0x02 });
    defer r.deinit();
    try testing.expectError(error.UnexpectedEof, r.skipField(.bit32));
}

test "skipField bit64 truncated" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x01, 0x02, 0x03 });
    defer r.deinit();
    try testing.expectError(error.UnexpectedEof, r.skipField(.bit64));
}

test "skipField length_delimited truncated" {
    var r = BinaryReader.init(testing.allocator, &.{ 0x05, 'a', 'b' });
    defer r.deinit();
    try testing.expectError(error.LengthExceedsBuffer, r.skipField(.length_delimited));
}

test "unknown field in tag stream is skipped" {
    // tag(99, varint) value=7, tag(1, varint) value=3
    // tag(99, varint): (99 << 3) | 0 = 0x318 → 0x98 0x06
    // tag(1, varint):  (1 << 3) | 0 = 0x08
    var r = BinaryReader.init(testing.allocator, &.{ 0x98, 0x06, 0x07, 0x08, 0x03 });
    const t1 = try r.tag();
    try r.skipField(t1.wire_type);
    const t2 = try r.tag();
    try testing.expectEqual(@as(u32, 1), t2.number);
    try testing.expectEqual(@as(u64, 3), try r.varint());
    try expectReaderConsumed(&r);
}
