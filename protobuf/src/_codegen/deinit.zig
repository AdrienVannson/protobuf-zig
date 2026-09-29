const std = @import("std");
const field_access = @import("field_access.zig");

/// Frees all allocator-owned fields in a decoded message.
///
/// Called by the generated `deinit` method on every message struct.
/// `msg` must be a pointer to a message struct.
///
/// TODO make it work for constant messages as well, and update plugin accordingly.
pub fn deinitMessage(msg: anytype, allocator: std.mem.Allocator) void {
    const T = std.meta.Child(@TypeOf(msg));
    inline for (T._metadata.fields) |field_meta| {
        field_access.clearField(msg, allocator, field_meta);
    }

    // Clear unknown fields
    var it = msg._unknown_fields.iterator();
    while (it.next()) |entry| {
        for (entry.value_ptr.items) |uf| allocator.free(uf.data);
        entry.value_ptr.deinit(allocator);
    }
    msg._unknown_fields.deinit(allocator);
}

/// Frees any heap memory owned by a single field value.
pub fn deinitElement(value: anytype, allocator: std.mem.Allocator) void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .optional => if (value) |v| deinitElement(v, allocator),
        .pointer => |ptr| switch (ptr.size) {
            .slice => { // string / bytes
                if (ptr.child != u8) @compileError("unexpected slice field type");
                allocator.free(value);
            },
            .one => { // message pointer
                if (@typeInfo(ptr.child) != .@"struct") @compileError("unexpected pointer field type");
                value.deinit(allocator);
                allocator.destroy(value);
            },
            else => @compileError("unexpected pointer field type"),
        },
        .@"struct" => {
            if (comptime @hasField(T, "items")) {
                // std.ArrayList
                for (value.items) |item| deinitElement(item, allocator);
                var list = value;
                list.deinit(allocator);
            } else {
                // Hash map (AutoHashMapUnmanaged / StringHashMapUnmanaged)
                var it = value.iterator();
                while (it.next()) |entry| {
                    deinitElement(entry.key_ptr.*, allocator);
                    deinitElement(entry.value_ptr.*, allocator);
                }
                var m = value;
                m.deinit(allocator);
            }
        },
        .int, .float, .bool, .@"enum" => {}, // scalars / enums own no heap memory
        else => @compileError("unexpected field type: " ++ @typeName(T)),
    }
}

test "deinitMessage string" {
    const TestAllTypesProto3 = @import("../testgen/test_messages/test_messages_proto3.pb.zig").TestAllTypesProto3;
    var allocator = std.testing.allocator;

    var msg = TestAllTypesProto3{
        .optional_string = try allocator.dupe(u8, "hello"),
    };
    deinitMessage(&msg, allocator);
}

test "deinitMessage bytes" {
    const TestAllTypesProto3 = @import("../testgen/test_messages/test_messages_proto3.pb.zig").TestAllTypesProto3;
    var allocator = std.testing.allocator;

    var msg = TestAllTypesProto3{
        .optional_bytes = try allocator.dupe(u8, "hello"),
    };
    deinitMessage(&msg, allocator);
}

test "deinitMessage oneof string" {
    const TestAllTypesProto3 = @import("../testgen/test_messages/test_messages_proto3.pb.zig").TestAllTypesProto3;
    var allocator = std.testing.allocator;

    var msg = TestAllTypesProto3{
        .oneof_field = .{ .oneof_string = try allocator.dupe(u8, "hello") },
    };
    deinitMessage(&msg, allocator);
}

test "deinitMessage oneof bytes" {
    const TestAllTypesProto3 = @import("../testgen/test_messages/test_messages_proto3.pb.zig").TestAllTypesProto3;
    var allocator = std.testing.allocator;

    var msg = TestAllTypesProto3{
        .oneof_field = .{ .oneof_bytes = try allocator.dupe(u8, "hello") },
    };
    deinitMessage(&msg, allocator);
}
