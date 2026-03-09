const std = @import("std");
const descriptor = @import("../descriptor.zig");

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

    pub const _desc = &[_]descriptor.DescField{
        .{ .name = "explicit_field", .number = 1, .json_name = "explicitField", .deprecated = false, .presence = .explicit, .kind = .{ .scalar = .{ .oneof = null, .scalar = .int32, .default_value = null } } },
        .{ .name = "implicit_field", .number = 2, .json_name = "implicitField", .deprecated = false, .presence = .implicit, .kind = .{ .scalar = .{ .oneof = null, .scalar = .int32, .default_value = null } } },
        .{ .name = "legacy_required_field", .number = 3, .json_name = "legacyRequiredField", .deprecated = false, .presence = .legacy_required, .kind = .{ .scalar = .{ .oneof = null, .scalar = .string, .default_value = null } } },
        .{ .name = "repeated_field", .number = 4, .json_name = "repeatedField", .deprecated = false, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .string }, .is_packed = false, .delimited_encoding = false } } },
        .{ .name = "message_field", .number = 5, .json_name = "messageField", .deprecated = false, .presence = .explicit, .kind = .{ .message_field = .{ .oneof = null, .message = null, .delimited_encoding = false } } },
        .{ .name = "field_with_default", .number = 6, .json_name = "fieldWithDefault", .deprecated = false, .presence = .explicit, .kind = .{ .scalar = .{ .oneof = null, .scalar = .int32, .default_value = .{ .integer = 42 } } } },
        .{ .name = "color_field", .number = 10, .json_name = "colorField", .deprecated = false, .presence = .explicit, .kind = .{ .enum_field = .{ .oneof = null, .enum_type = null, .default_value = null } } },
        .{ .name = "float_field", .number = 11, .json_name = "floatField", .deprecated = false, .presence = .explicit, .kind = .{ .scalar = .{ .oneof = null, .scalar = .float, .default_value = null } } },
        .{ .name = "repeated_float_field", .number = 12, .json_name = "repeatedFloatField", .deprecated = false, .presence = .implicit, .kind = .{ .list = .{ .element = .{ .scalar = .float }, .is_packed = true, .delimited_encoding = false } } },
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

        pub const _desc = &[_]descriptor.DescField{
            .{ .name = "value", .number = 1, .json_name = "value", .deprecated = false, .presence = .explicit, .kind = .{ .scalar = .{ .oneof = null, .scalar = .string, .default_value = null } } },
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
