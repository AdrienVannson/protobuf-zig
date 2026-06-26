//! Runtime helpers backing the `_fileDesc` / `_desc` accessors emitted in
//! generated `.pb.zig` files. They lazily parse the `DESCRIPTOR_BYTES` embedded
//! in each file into a fully-linked `DescFile` graph and cache it for the
//! lifetime of the process. The caching mechanism is thread-safe.
//!
//! Memory model: the winning arena is intentionally never freed; descriptors
//! live for the whole program.

const std = @import("std");
const protobuf = @import("../root.zig");
const descriptor = protobuf.wkt.descriptor;
const desc_file_from_proto = @import("desc_file_from_proto.zig");

const DescFile = protobuf.DescFile;
const DescMessage = protobuf.DescMessage;

/// Accessor for a generated file's lazily-built `DescFile`.
pub const FileDescFn = *const fn () anyerror!*const DescFile;

/// Per-file static cache. Keyed on `File` so each generated file gets its own
/// storage (the `File` reference forces a distinct type per instantiation).
fn Cache(comptime File: type) type {
    return struct {
        comptime {
            _ = File;
        }
        var value: std.atomic.Value(?*const DescFile) = std.atomic.Value(?*const DescFile).init(null);
    };
}

/// Lazily build (and cache, process-lifetime) the `DescFile` for the generated
/// file `File` from its `DESCRIPTOR_BYTES`. `dep_accessors` lists the `_fileDesc`
/// accessor of every direct import so cross-file type references resolve.
///
/// `File` is used only as a unique key for the per-file static cache (pass
/// `@This()` from the generated file).
pub fn fileDesc(
    comptime File: type,
    comptime descriptor_bytes: []const u8,
    dep_accessors: []const FileDescFn,
) !*const DescFile {
    const C = Cache(File);

    if (C.value.load(.acquire)) |v| return v;

    const arena = try std.heap.page_allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer {
        arena.deinit();
        std.heap.page_allocator.destroy(arena);
    }
    const allocator = arena.allocator();

    const desc_file = try build_desc_file(descriptor_bytes, dep_accessors, allocator);

    // TODO: check values for success_order and failure_order
    if (C.value.cmpxchgStrong(null, desc_file, .release, .acquire)) |winner| {
        // Lost the race: another thread cached first.
        arena.deinit();
        std.heap.page_allocator.destroy(arena);
        return winner.?;
    }
    return desc_file;
}

fn build_desc_file(descriptor_bytes: []const u8, dep_accessors: []const FileDescFn, allocator: std.mem.Allocator) !*const DescFile {
    const proto = try allocator.create(descriptor.FileDescriptorProto);
    proto.* = .{};
    try protobuf.from_binary(proto, descriptor_bytes, allocator);

    // name -> *const DescFile
    var deps = std.StringHashMap(*const DescFile).init(allocator);
    for (dep_accessors) |dep| {
        const desc_file = try dep();
        try deps.put(desc_file.name, desc_file);
    }

    // TODO: descFileFromProto is already creating an arena, so we have two arenas each time.
    // Re-consider this after reviewing descFileFromProto.
    const owned = (try desc_file_from_proto.descFileFromProto(proto, &deps, allocator));
    return owned.file;
}

/// Navigate from a file descriptor to the message addressed by `path`: the first
/// index selects a top-level message in `file.messages`, each subsequent index
/// selects into `nested_messages`. Indices match those used for `_desc`.
pub fn messageDescAt(file: *const DescFile, comptime path: []const usize) *const DescMessage {
    comptime std.debug.assert(path.len > 0);
    var msg: *const DescMessage = &file.messages[path[0]];
    inline for (path[1..]) |i| {
        msg = &msg.nested_messages[i];
    }
    return msg;
}
