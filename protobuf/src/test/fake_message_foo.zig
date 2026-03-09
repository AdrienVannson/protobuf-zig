const std = @import("std");
const field = @import("../field.zig");

pub const FakeMessageFoo = struct {
    explicit_field: ?i32 = null,
    implicit_field: ?i32 = null,
    legacy_required_field: ?[]const u8 = null,
    repeated_field: std.ArrayListUnmanaged([]const u8) = .{},
    message_field: ?*Bar = null,
    field_with_default: ?i32 = null,
    color_field: ?Color = null,
    float_field: ?f32 = null,
    repeated_float_field: std.ArrayListUnmanaged(f32) = .{},

    pub const _desc = &[_]field.FieldMetadata{
        .{ .number = 1, .presence = .explicit, .kind = .{ .scalar = .{ .scalar = .int32 } } },
        .{ .number = 2, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } },
        .{ .number = 3, .presence = .legacy_required, .kind = .{ .scalar = .{ .scalar = .string } } },
        .{ .number = 4, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .string }, .is_packed = false, .delimited_encoding = false } } },
        .{ .number = 5, .presence = .explicit, .kind = .{ .message_field = .{ .delimited_encoding = false } } },
        .{ .number = 6, .presence = .explicit, .kind = .{ .scalar = .{ .scalar = .int32, .default_value = .{ .integer = 42 } } } },
        .{ .number = 10, .presence = .explicit, .kind = .{ .enum_field = .{ .default_value = null } } },
        .{ .number = 11, .presence = .explicit, .kind = .{ .scalar = .{ .scalar = .float } } },
        .{ .number = 12, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .float }, .is_packed = true, .delimited_encoding = false } } },
    };

    pub fn deinit(self: *FakeMessageFoo, allocator: std.mem.Allocator) void {
        for (self.repeated_field.items) |s| allocator.free(s);
        self.repeated_field.deinit(allocator);
        if (self.message_field) |m| {
            m.deinit(allocator);
            allocator.destroy(m);
        }
        self.repeated_float_field.deinit(allocator);
    }

    pub const Bar = struct {
        value: ?[]const u8 = null,

        pub const _desc = &[_]field.FieldMetadata{
            .{ .number = 1, .presence = .explicit, .kind = .{ .scalar = .{ .scalar = .string } } },
        };

        pub fn deinit(self: *Bar, allocator: std.mem.Allocator) void {
            if (self.value) |v| allocator.free(v);
        }
    };

    pub const Color = enum(i32) {
        color_unknown = 0,
        color_red = 1,
        color_green = 2,
    };
};
