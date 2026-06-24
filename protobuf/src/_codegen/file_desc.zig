//! Runtime helpers backing the `_fileDesc` / `_desc` accessors emitted in
//! generated `.pb.zig` files. They lazily parse the `DESCRIPTOR_BYTES` embedded
//! in each file into a fully-linked `DescFile` graph and cache it for the
//! lifetime of the process.
//!
//! Memory model: the resulting descriptor arena is intentionally never freed;
//! descriptors live for the whole program. The intermediate decoded
//! `FileDescriptorProto` is only needed during the build and is freed afterwards.

const std = @import("std");
const protobuf = @import("../root.zig");
const descriptor = protobuf.wkt.descriptor;
const desc_file_from_proto = @import("desc_file_from_proto.zig");

const DescFile = protobuf.DescFile;
const DescMessage = protobuf.DescMessage;

/// Accessor for a generated file's lazily-built `DescFile`.
pub const FileDescFn = *const fn (std.Io) anyerror!*const DescFile;

/// Per-file static cache. Keyed on `File` so each generated file gets its own
/// storage (the `File` reference forces a distinct type per instantiation).
fn Cache(comptime File: type) type {
    return struct {
        comptime {
            _ = File;
        }
        var mutex: std.Io.Mutex = .init;
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
    io: std.Io,
) !*const DescFile {
    const C = Cache(File);

    if (C.value.load(.acquire)) |v| return v;

    try C.mutex.lock(io);
    defer C.mutex.unlock(io);

    if (C.value.load(.acquire)) |v| return v; // Re-check after acquiring the lock

    const v = try build(descriptor_bytes, dep_accessors, io);
    C.value.store(v, .release);
    return v;
}

fn build(descriptor_bytes: []const u8, dep_accessors: []const FileDescFn, io: std.Io) !*const DescFile {
    // Intermediate proto + deps map: only needed during the build, freed here.
    var tmp = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer tmp.deinit();
    const tmp_alloc = tmp.allocator();

    const proto = try tmp_alloc.create(descriptor.FileDescriptorProto);
    proto.* = .{};
    try protobuf.from_binary(proto, descriptor_bytes, tmp_alloc);

    var deps = std.StringHashMap(*const DescFile).init(tmp_alloc);
    for (dep_accessors) |dep| {
        const df = try dep(io);
        try deps.put(df.name, df);
    }

    // The DescFile graph must outlive the process. descFileFromProto builds it into
    // its own arena (backed by page_allocator); we intentionally leak that arena.
    const owned = try desc_file_from_proto.descFileFromProto(proto, &deps, std.heap.page_allocator);
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
