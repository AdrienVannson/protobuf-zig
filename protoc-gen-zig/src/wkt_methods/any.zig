const std = @import("std");
const _codegen = @import("protobuf")._codegen;

const Any = struct {
    type_url: []const u8 = "",
    value: []const u8 = "",

    // <!-- include -->
    pub fn pack(allocator: std.mem.Allocator, msg: anytype) !@This() {
        return _codegen.any.pack(@This(), allocator, msg);
    }

    pub fn is(self: @This(), comptime T: type) bool {
        return _codegen.any.is(self, T);
    }

    pub fn unpack(self: @This(), comptime T: type, allocator: std.mem.Allocator) !T {
        return _codegen.any.unpack(self, T, allocator);
    }
    // <!-- /include -->
};
