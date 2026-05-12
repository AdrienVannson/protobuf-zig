const std = @import("std");

const INDENT_UNIT = "    ";

/// In-memory builder for a single generated `.zig` file.
///
/// Tracks an indentation level managed via `indent()` / `unindent()`. The
/// current indentation is automatically emitted before the first piece of
/// content on each new line, so chained `write` / `writeLine` calls produce
/// correctly indented output without manual prefixing.
pub const GeneratedFile = struct {
    alloc: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    indent_level: usize,
    at_line_start: bool,

    pub fn init(alloc: std.mem.Allocator) GeneratedFile {
        return .{
            .alloc = alloc,
            .buffer = .{},
            .indent_level = 0,
            .at_line_start = true,
        };
    }

    pub fn deinit(self: *GeneratedFile) void {
        self.buffer.deinit(self.alloc);
    }

    /// Append `value` to the buffer. If positioned at the start of a line,
    /// the current indentation is written first. Accepts `[]const u8`,
    /// string literals, and any integer type. Returns `self` for chaining.
    pub fn write(self: *GeneratedFile, value: anytype) !*GeneratedFile {
        const T = @TypeOf(value);
        switch (@typeInfo(T)) {
            .int, .comptime_int => {
                try self.maybeEmitIndent();
                try self.buffer.writer(self.alloc).print("{d}", .{value});
            },
            .pointer => {
                const s: []const u8 = value;
                if (s.len == 0) return self;
                try self.maybeEmitIndent();
                try self.buffer.appendSlice(self.alloc, s);
            },
            else => @compileError(
                "GeneratedFile.write: unsupported type " ++ @typeName(T),
            ),
        }
        return self;
    }

    /// Same as `write`, then appends a newline and marks the buffer as being
    /// at the start of a new line. Returns `self` for chaining.
    pub fn writeLine(self: *GeneratedFile, value: anytype) !*GeneratedFile {
        _ = try self.write(value);
        try self.buffer.append(self.alloc, '\n');
        self.at_line_start = true;
        return self;
    }

    pub fn indent(self: *GeneratedFile) *GeneratedFile {
        self.indent_level += 1;
        return self;
    }

    pub fn unindent(self: *GeneratedFile) *GeneratedFile {
        self.indent_level -= 1;
        return self;
    }

    /// Transfers ownership of the underlying bytes to the caller. The
    /// `GeneratedFile` is left in an empty state and must still be `deinit`ed.
    pub fn toOwnedSlice(self: *GeneratedFile) ![]u8 {
        return self.buffer.toOwnedSlice(self.alloc);
    }

    fn maybeEmitIndent(self: *GeneratedFile) !void {
        if (!self.at_line_start) return;
        self.at_line_start = false;
        for (0..self.indent_level) |_| {
            try self.buffer.appendSlice(self.alloc, INDENT_UNIT);
        }
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

fn expectContents(f: *GeneratedFile, expected: []const u8) !void {
    const out = try f.toOwnedSlice();
    defer testing.allocator.free(out);
    try testing.expectEqualSlices(u8, expected, out);
}

test "chained string and integer at indent zero" {
    var f = GeneratedFile.init(testing.allocator);
    defer f.deinit();
    _ = try (try (try f.write("foo")).write(@as(u32, 42))).writeLine(";");
    try expectContents(&f, "foo42;\n");
}

test "writeLine prefixes current indentation" {
    var f = GeneratedFile.init(testing.allocator);
    defer f.deinit();
    _ = f.indent().indent();
    _ = try f.writeLine("a;");
    try expectContents(&f, "        a;\n");
}

test "indent applies once at the start of a line for chained writes" {
    var f = GeneratedFile.init(testing.allocator);
    defer f.deinit();
    _ = f.indent().indent();
    _ = try (try (try f.write("const x = ")).write(@as(u32, 42))).writeLine(";");
    try expectContents(&f, "        const x = 42;\n");
}

test "indent and unindent across multiple lines" {
    var f = GeneratedFile.init(testing.allocator);
    defer f.deinit();
    _ = f.indent();
    _ = try f.writeLine("x");
    _ = f.unindent();
    _ = try f.writeLine("y");
    try expectContents(&f, "    x\ny\n");
}

test "mid-line indent does not retroactively indent current line" {
    var f = GeneratedFile.init(testing.allocator);
    defer f.deinit();
    _ = try f.write("abc");
    _ = f.indent();
    _ = try f.writeLine("def");
    _ = try f.writeLine("ghi");
    try expectContents(&f, "abcdef\n    ghi\n");
}

test "empty string write does not emit indentation" {
    var f = GeneratedFile.init(testing.allocator);
    defer f.deinit();
    _ = f.indent();
    _ = try f.write("");
    _ = try f.writeLine("x");
    try expectContents(&f, "    x\n");
}

test "writeLine with empty string produces blank line without indentation" {
    var f = GeneratedFile.init(testing.allocator);
    defer f.deinit();
    _ = f.indent();
    _ = try f.writeLine("a");
    _ = try f.writeLine("");
    _ = try f.writeLine("b");
    try expectContents(&f, "    a\n\n    b\n");
}

test "negative integer is written with sign" {
    var f = GeneratedFile.init(testing.allocator);
    defer f.deinit();
    _ = try f.write(@as(i32, -7));
    try expectContents(&f, "-7");
}

test "slice with runtime length" {
    var f = GeneratedFile.init(testing.allocator);
    defer f.deinit();
    const arr = [_]u8{ 'h', 'i' };
    const s: []const u8 = &arr;
    _ = try f.write(s);
    try expectContents(&f, "hi");
}
