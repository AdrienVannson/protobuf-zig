const std = @import("std");
const field_access = @import("field_access.zig");

/// Frees all allocator-owned fields in a decoded message.
///
/// Called by the generated `deinit` method on every message struct.
/// `msg` must be a pointer to a message struct.
pub fn deinit_message(msg: anytype, allocator: std.mem.Allocator) void {
    const T = std.meta.Child(@TypeOf(msg));
    inline for (T._desc.fields) |field_meta| {
        field_access.clearField(msg, field_meta, allocator);
    }
}

test "deinit_message string" {
    const TestAllTypesProto3 = @import("../testgen/test_messages/test_messages_proto3.pb.zig").TestAllTypesProto3;
    var alloc = std.testing.allocator;

    var msg = TestAllTypesProto3{
        .optional_string = try alloc.dupe(u8, "hello"),
    };
    deinit_message(&msg, alloc);
}

test "deinit_message bytes" {
    const TestAllTypesProto3 = @import("../testgen/test_messages/test_messages_proto3.pb.zig").TestAllTypesProto3;
    var alloc = std.testing.allocator;

    var msg = TestAllTypesProto3{
        .optional_bytes = try alloc.dupe(u8, "hello"),
    };
    deinit_message(&msg, alloc);
}

test "deinit_message oneof string" {
    const TestAllTypesProto3 = @import("../testgen/test_messages/test_messages_proto3.pb.zig").TestAllTypesProto3;
    var alloc = std.testing.allocator;

    var msg = TestAllTypesProto3{
        .oneof_field = .{ .oneof_string = try alloc.dupe(u8, "hello") },
    };
    deinit_message(&msg, alloc);
}

test "deinit_message oneof bytes" {
    const TestAllTypesProto3 = @import("../testgen/test_messages/test_messages_proto3.pb.zig").TestAllTypesProto3;
    var alloc = std.testing.allocator;

    var msg = TestAllTypesProto3{
        .oneof_field = .{ .oneof_bytes = try alloc.dupe(u8, "hello") },
    };
    deinit_message(&msg, alloc);
}
