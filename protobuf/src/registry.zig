//! Runtime type registry.
//!
//! TODO: partially AI generated, review

const std = @import("std");
const protobuf = @import("root.zig");

const DescMessage = protobuf.DescMessage;

/// Type-erased operations for one generated message type.
pub const MessageType = struct {
    /// Fully-qualified proto name, e.g. "example.Bar.Nested".
    fully_qualified_proto_name: []const u8,
    /// Allocate and default-initialize a message; returns an opaque pointer.
    create: *const fn (std.mem.Allocator) std.mem.Allocator.Error!*anyopaque,
    /// Free the box returned by `create`. Does not release field memory; call
    /// `deinit` first.
    destroy: *const fn (*anyopaque, std.mem.Allocator) void,
    /// Release memory owned by the message's fields (the generated `deinit`).
    deinit: *const fn (*anyopaque, std.mem.Allocator) void,
    /// Decode wire bytes into the message.
    fromBinary: *const fn (*anyopaque, []const u8, std.mem.Allocator) anyerror!void,
    /// Encode the message to wire bytes (caller owns the returned slice).
    toBinary: *const fn (*anyopaque, std.mem.Allocator) anyerror![]u8,
    /// Encode the message to ProtoJSON (caller owns the returned slice).
    toJson: *const fn (*anyopaque, std.mem.Allocator, *const Registry) anyerror![]u8,
    /// Decode ProtoJSON into the message.
    fromJson: *const fn (*anyopaque, []const u8, std.mem.Allocator, *const Registry) anyerror!void,
    /// Linked descriptor for this message.
    desc: *const fn () anyerror!*const DescMessage,

    /// Build (at comptime) the vtable for message type `T` and return a pointer
    /// to its process-lifetime static instance.
    pub fn of(comptime T: type) *const MessageType {
        const shims = struct {
            inline fn cast(ptr: *anyopaque) *T {
                return @ptrCast(@alignCast(ptr));
            }
            fn create(allocator: std.mem.Allocator) std.mem.Allocator.Error!*anyopaque {
                const p = try allocator.create(T);
                p.* = .{};
                return @ptrCast(p);
            }
            fn destroy(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                allocator.destroy(cast(ptr));
            }
            fn deinit(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                cast(ptr).deinit(allocator);
            }
            fn fromBinary(ptr: *anyopaque, bytes: []const u8, allocator: std.mem.Allocator) anyerror!void {
                try protobuf.from_binary(cast(ptr), bytes, allocator);
            }
            fn toBinary(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror![]u8 {
                return protobuf.to_binary(allocator, cast(ptr).*);
            }
            fn toJson(ptr: *anyopaque, allocator: std.mem.Allocator, registry: *const Registry) anyerror![]u8 {
                return protobuf.to_json(allocator, cast(ptr).*, registry);
            }
            fn fromJson(ptr: *anyopaque, json: []const u8, allocator: std.mem.Allocator, registry: *const Registry) anyerror!void {
                try protobuf.from_json(cast(ptr), json, allocator, registry);
            }
            fn desc() anyerror!*const DescMessage {
                return T._desc();
            }

            const vtable = MessageType{
                .fully_qualified_proto_name = T._metadata.fully_qualified_proto_name,
                .create = create,
                .destroy = destroy,
                .deinit = deinit,
                .fromBinary = fromBinary,
                .toBinary = toBinary,
                .toJson = toJson,
                .fromJson = fromJson,
                .desc = desc,
            };
        };
        return &shims.vtable;
    }
};

/// Maps fully-qualified proto names to their type-erased `MessageType`.
///
/// A struct (not a bare hashmap) so that extension and enum tables can be added
/// later without changing the public API.
pub const Registry = struct {
    messages: std.StringHashMapUnmanaged(*const MessageType) = .empty,

    pub const empty: Registry = .{};

    pub fn deinit(self: *Registry, allocator: std.mem.Allocator) void {
        self.messages.deinit(allocator);
    }

    /// Register every message type declared in the generated file `File`,
    /// including nested messages. Does not follow `File`'s imports.
    ///
    /// Returns `error.DuplicateMessageName` if a message with the same
    /// fully-qualified proto name is already registered (e.g. the same file
    /// registered twice, or two files with a colliding message name). On this
    /// error the registry may contain a partial set of `File`'s messages and
    /// should not be reused.
    pub fn registerFile(self: *Registry, allocator: std.mem.Allocator, comptime File: type) !void {
        inline for (comptime messageTypesOf(File)) |mt| {
            const gop = try self.messages.getOrPut(allocator, mt.fully_qualified_proto_name);
            if (gop.found_existing) return error.DuplicateMessageName;
            gop.value_ptr.* = mt;
        }
    }

    /// Look up a message type by fully-qualified proto name.
    pub fn getMessageType(self: *const Registry, fully_qualified_proto_name: []const u8) ?*const MessageType {
        return self.messages.get(fully_qualified_proto_name);
    }
};

/// Returns the `MessageType` of every message declared in `Scope` (a generated
/// file struct or a message struct), recursing into nested messages.
fn messageTypesOf(comptime Scope: type) []const *const MessageType {
    comptime {
        var out: []const *const MessageType = &.{};
        for (@typeInfo(Scope).@"struct".decls) |decl| {
            const D = @field(Scope, decl.name);
            if (@TypeOf(D) != type) continue;
            if (@typeInfo(D) != .@"struct") continue;
            if (!@hasDecl(D, "_metadata")) continue;
            out = out ++ [_]*const MessageType{MessageType.of(D)} ++ messageTypesOf(D);
        }
        return out;
    }
}

test "registerFile registers top-level and nested messages" {
    const example = @import("testgen/example.pb.zig");

    const allocator = std.testing.allocator;
    var registry = Registry.empty;
    defer registry.deinit(allocator);

    try registry.registerFile(allocator, example);

    try std.testing.expect(registry.getMessageType("example.Foo") != null);
    try std.testing.expect(registry.getMessageType("example.Bar") != null);
    try std.testing.expect(registry.getMessageType("example.Bar.Nested") != null);
    try std.testing.expect(registry.getMessageType("example.Color") == null); // enum, not registered
    try std.testing.expect(registry.getMessageType("example.Missing") == null);
}

test "registerFile errors on duplicate message names" {
    const example = @import("testgen/example.pb.zig");

    const allocator = std.testing.allocator;
    var registry = Registry.empty;
    defer registry.deinit(allocator);

    try registry.registerFile(allocator, example);
    try std.testing.expectError(error.DuplicateMessageName, registry.registerFile(allocator, example));
}

test "MessageType vtable round-trips through binary" {
    const example = @import("testgen/example.pb.zig");
    const allocator = std.testing.allocator;

    var registry = Registry.empty;
    defer registry.deinit(allocator);
    try registry.registerFile(allocator, example);

    const original = example.Foo{ .name = "hello", .id = 42, .@"struct" = 7 };
    const bytes = try protobuf.to_binary(allocator, original);
    defer allocator.free(bytes);

    const mt = registry.getMessageType("example.Foo").?;
    try std.testing.expectEqualStrings("example.Foo", mt.fully_qualified_proto_name);

    const ptr = try mt.create(allocator);
    defer mt.destroy(ptr, allocator);
    try mt.fromBinary(ptr, bytes, allocator);
    defer mt.deinit(ptr, allocator);

    const reencoded = try mt.toBinary(ptr, allocator);
    defer allocator.free(reencoded);
    try std.testing.expectEqualSlices(u8, bytes, reencoded);

    const desc = try mt.desc();
    try std.testing.expectEqualStrings("example.Foo", desc.fully_qualified_proto_name);
}

test "google.protobuf.Any round-trips through JSON" {
    const example = @import("testgen/example.pb.zig");
    const Any = protobuf.wkt.any.Any;
    const allocator = std.testing.allocator;

    var registry = Registry.empty;
    defer registry.deinit(allocator);
    try registry.registerFile(allocator, example);

    // Pack an example.Foo into an Any's `value`.
    const foo = example.Foo{ .name = "hello", .id = 42, .@"struct" = 7 };
    const foo_bytes = try protobuf.to_binary(allocator, foo);
    defer allocator.free(foo_bytes);

    const any: Any = .{ .type_url = "type.googleapis.com/example.Foo", .value = foo_bytes };

    // to_json must emit `@type` alongside the packed message's fields.
    const json = try protobuf.to_json(allocator, any, &registry);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"@type\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "type.googleapis.com/example.Foo") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "hello") != null);

    // from_json resolves the type via the registry and re-encodes `value`.
    var parsed: Any = .{};
    defer parsed.deinit(allocator);
    try protobuf.from_json(&parsed, json, allocator, &registry);
    try std.testing.expectEqualStrings(any.type_url, parsed.type_url);
    try std.testing.expectEqualSlices(u8, any.value, parsed.value);
}
