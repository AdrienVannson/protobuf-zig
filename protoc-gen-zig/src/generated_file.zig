const std = @import("std");

const INDENT_UNIT = "    ";

/// In-memory builder for a single generated `.zig` file.
///
/// Tracks an indentation level managed via `indent()` / `unindent()`. The
/// current indentation is automatically emitted before the first piece of
/// content on each new line, so successive `write` / `writeLine` calls
/// produce correctly indented output without manual prefixing.
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

    /// Append `value` to the buffer. If positioned at the start of a line,
    /// the current indentation is written first.
    ///
    /// `value` may be a single piece (string or integer) or a tuple of such
    /// pieces, in which case each element is written in order. This lets a
    /// logical line be assembled in one call:
    ///
    /// ```
    /// try f.writeLine(.{ "const x = ", 42, ";" });
    /// ```
    pub fn write(self: *GeneratedFile, value: anytype) !void {
        try self.maybeEmitIndent();

        const T = @TypeOf(value);
        const info = @typeInfo(T);
        if (info == .@"struct" and info.@"struct".is_tuple) {
            inline for (value) |elem| try self.writeOne(elem);
        } else {
            try self.writeOne(value);
        }
    }

    /// Same as `write`, then appends a newline and marks the buffer as being
    /// at the start of a new line.
    pub fn writeLine(self: *GeneratedFile, value: anytype) !void {
        try self.write(value);
        try self.buffer.append(self.alloc, '\n');
        self.at_line_start = true;
    }

    /// Append a bare newline. No indentation is emitted, regardless of the
    /// current `indent_level`.
    pub fn emptyLine(self: *GeneratedFile) !void {
        try self.buffer.append(self.alloc, '\n');
        self.at_line_start = true;
    }

    pub fn indent(self: *GeneratedFile) void {
        self.indent_level += 1;
    }

    pub fn unindent(self: *GeneratedFile) void {
        self.indent_level -= 1;
    }

    /// Transfers ownership of the underlying bytes to the caller.
    pub fn toOwnedSlice(self: *GeneratedFile) ![]u8 {
        return self.buffer.toOwnedSlice(self.alloc);
    }

    fn writeOne(self: *GeneratedFile, value: anytype) !void {
        const T = @TypeOf(value);
        switch (@typeInfo(T)) {
            .int, .comptime_int => {
                try self.buffer.writer(self.alloc).print("{d}", .{value});
            },
            .pointer => {
                try self.buffer.appendSlice(self.alloc, value);
            },
            else => @compileError(
                "GeneratedFile.write: unsupported type " ++ @typeName(T),
            ),
        }
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

test "tuple of string and integer at indent zero" {
    var f = GeneratedFile.init(testing.allocator);
    try f.writeLine(.{ "foo", @as(u32, 42), ";" });
    try expectContents(&f, "foo42;\n");
}

test "writeLine prefixes current indentation" {
    var f = GeneratedFile.init(testing.allocator);
    f.indent();
    f.indent();
    try f.writeLine("a;");
    try expectContents(&f, "        a;\n");
}

test "tuple writeLine indents once at the start of the line" {
    var f = GeneratedFile.init(testing.allocator);
    f.indent();
    f.indent();
    try f.writeLine(.{ "const x = ", @as(u32, 42), ";" });
    try expectContents(&f, "        const x = 42;\n");
}

test "indent and unindent across multiple lines" {
    var f = GeneratedFile.init(testing.allocator);
    f.indent();
    try f.writeLine("x");
    f.unindent();
    try f.writeLine("y");
    try expectContents(&f, "    x\ny\n");
}

test "mid-line indent does not retroactively indent current line" {
    var f = GeneratedFile.init(testing.allocator);
    try f.write("abc");
    f.indent();
    try f.writeLine("def");
    try f.writeLine("ghi");
    try expectContents(&f, "abcdef\n    ghi\n");
}

test "empty string write does not emit indentation" {
    var f = GeneratedFile.init(testing.allocator);
    f.indent();
    try f.write("");
    try f.writeLine("x");
    try expectContents(&f, "    x\n");
}

test "empty tuple is a no-op" {
    var f = GeneratedFile.init(testing.allocator);
    f.indent();
    try f.write(.{});
    try f.writeLine("x");
    try expectContents(&f, "    x\n");
}

test "slice with runtime length" {
    var f = GeneratedFile.init(testing.allocator);
    const arr = [_]u8{ 'h', 'i' };
    const s: []const u8 = &arr;
    try f.write(s);
    try expectContents(&f, "hi");
}

test "emptyLine does not emit indentation" {
    var f = GeneratedFile.init(testing.allocator);
    f.indent();
    try f.writeLine("a");
    try f.emptyLine();
    try f.writeLine("b");
    try expectContents(&f, "    a\n\n    b\n");
}
