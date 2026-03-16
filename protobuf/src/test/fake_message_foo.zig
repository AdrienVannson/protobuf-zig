const std = @import("std");
const metadata = @import("../metadata.zig");

pub const FakeMessageFoo = struct {
    explicit_field: ?i32 = null,
    implicit_field: i32 = 0,
    legacy_required_field: ?[]const u8 = null,
    repeated_field: std.ArrayListUnmanaged([]const u8) = .{},
    message_field: ?*Bar = null,
    field_with_default: ?i32 = null,
    color_field: ?Color = null,
    float_field: ?f32 = null,
    repeated_float_field: std.ArrayListUnmanaged(f32) = .{},

    pub const _desc = metadata.MessageMetadata{
        .fields = &[_]metadata.FieldMetadata{
            .{ .number = 1, .field_index = 0, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // explicit_field
            .{ .number = 2, .field_index = 1, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } }, // implicit_field
            .{ .number = 3, .field_index = 2, .presence = .legacy_required, .kind = .{ .scalar = .{ .scalar = .string } } }, // legacy_required_field
            .{ .number = 4, .field_index = 3, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .string } } } }, // repeated_field
            .{ .number = 5, .field_index = 4, .kind = .{ .message_field = .{} } }, // message_field
            .{ .number = 6, .field_index = 5, .kind = .{ .scalar = .{ .scalar = .int32, .default_value = .{ .integer = 42 } } } }, // field_with_default
            .{ .number = 10, .field_index = 6, .kind = .{ .enum_field = .{} } }, // color_field
            .{ .number = 11, .field_index = 7, .kind = .{ .scalar = .{ .scalar = .float } } }, // float_field
            .{ .number = 12, .field_index = 8, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .float }, .is_packed = true } } }, // repeated_float_field
        },
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

        pub const _desc = metadata.MessageMetadata{
            .fields = &[_]metadata.FieldMetadata{
                .{ .number = 1, .field_index = 0, .kind = .{ .scalar = .{ .scalar = .string } } }, // value
            },
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

pub const FakeOneofMessage = struct {
    pub const MyOneof = union(enum) {
        a_uint32: u32,
        a_string: []const u8,
    };

    some_field: i32 = 0,
    my_oneof: ?MyOneof = null,

    pub const _desc = metadata.MessageMetadata{
        .fields = &[_]metadata.FieldMetadata{
            .{ .number = 1, .field_index = 0, .presence = .implicit, .kind = .{ .scalar = .{ .scalar = .int32 } } },
            .{ .number = 2, .field_index = 1, .oneof_variant = "a_uint32", .kind = .{ .scalar = .{ .scalar = .uint32 } } },
            .{ .number = 3, .field_index = 1, .oneof_variant = "a_string", .kind = .{ .scalar = .{ .scalar = .string } } },
        },
    };
};
