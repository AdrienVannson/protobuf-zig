//! Runtime helpers backing the `_fileDesc` / `_desc` accessors emitted in
//! generated `.pb.zig` files. They lazily parse the `DESCRIPTOR_BYTES` embedded
//! in each file into a fully-linked `DescFile` graph and cache it for the
//! lifetime of the process.
//!
//! Memory model: the decoded `FileDescriptorProto` and the resulting descriptor
//! arena are intentionally never freed. Descriptors live for the whole program,
//! so a one-time leak through `page_allocator` is simpler and safer than tracking
//! ownership (cross-file references point into other files' arenas).

const std = @import("std");
const protobuf = @import("../root.zig");
const descriptor = protobuf.wkt.descriptor;
const desc_file_from_proto = @import("desc_file_from_proto.zig");

const DescFile = protobuf.DescFile;
const DescMessage = protobuf.DescMessage;

/// Accessor for a generated file's lazily-built `DescFile`.
pub const FileDescFn = *const fn () *const DescFile;

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
) *const DescFile {
    const C = Cache(File);
    while (!C.mutex.tryLock()) {}
    defer C.mutex.unlock();
    if (C.value) |v| return v;
    const v = build(descriptor_bytes, dep_accessors) catch |err|
        std.debug.panic("failed to build descriptor for {s}: {}", .{ @typeName(File), err });
    C.value = v;
    return v;
}

/// Per-file static cache. Keyed on `File` so each generated file gets its own
/// storage (the `File` reference forces a distinct type per instantiation).
/// `mutex` is a lightweight spinlock guarding one-time initialization; there is
/// no import cycle between files, so distinct files use distinct locks and never
/// deadlock.
fn Cache(comptime File: type) type {
    return struct {
        comptime {
            _ = File;
        }
        var mutex: std.atomic.Mutex = .unlocked;
        var value: ?*const DescFile = null;
    };
}

fn build(descriptor_bytes: []const u8, dep_accessors: []const FileDescFn) !*const DescFile {
    // Leaked on purpose (see file header): descriptors are process-lifetime.
    const alloc = std.heap.page_allocator;

    const proto = try alloc.create(descriptor.FileDescriptorProto);
    proto.* = .{};
    try protobuf.from_binary(proto, descriptor_bytes, alloc);

    var deps = std.StringHashMap(*const DescFile).init(alloc);
    for (dep_accessors) |dep| {
        const df = dep();
        try deps.put(df.name, df);
    }

    const owned = try desc_file_from_proto.descFileFromProto(proto, &deps, alloc);
    return owned.file;
}

/// Navigate from a file descriptor to the message addressed by `path`: the first
/// index selects a top-level message in `file.messages`, each subsequent index
/// selects into `nested_messages`. Indices match those used for `_desc`
/// (synthetic map-entry messages are excluded from both).
pub fn messageDescAt(file: *const DescFile, comptime path: []const usize) *const DescMessage {
    comptime std.debug.assert(path.len > 0);
    var msg: *const DescMessage = &file.messages[path[0]];
    inline for (path[1..]) |i| {
        msg = &msg.nested_messages[i];
    }
    return msg;
}
