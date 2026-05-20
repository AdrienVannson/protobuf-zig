const std = @import("std");
const ScalarType = @import("../metadata.zig").ScalarType;

/// Frees all allocator-owned fields in a decoded message.
///
/// Called by the generated `deinit` method on every message struct.
/// `msg` must be a pointer to a message struct.
///
/// TODO: check the memory model. How does it work for non-optional allocated fields?
pub fn deinit_message(msg: anytype, allocator: std.mem.Allocator) void {
    const T = std.meta.Child(@TypeOf(msg));
    const fields = std.meta.fields(T);

    inline for (T._desc.fields) |field_meta| {
        const fi = comptime field_meta.field_index;
        const field_name = comptime fields[fi].name;

        if (comptime field_meta.oneof_variant) |variant_name| {
            if (@field(msg, field_name)) |active| {
                switch (active) {
                    inline else => |payload, tag| {
                        if (comptime std.mem.eql(u8, @tagName(tag), variant_name)) {
                            switch (field_meta.kind) {
                                .scalar => |kind| {
                                    if (comptime kind.scalar == .string or kind.scalar == .bytes) {
                                        allocator.free(payload);
                                    }
                                },
                                else => {},
                            }
                        }
                    },
                }
            }
        } else {
            switch (field_meta.kind) {
                .scalar => |kind| {
                    if (comptime (kind.scalar == .string or kind.scalar == .bytes)) {
                        if (@field(msg, field_name)) |s| allocator.free(s);
                    }
                },
                else => {},
            }
        }
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
