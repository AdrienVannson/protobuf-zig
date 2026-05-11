const std = @import("std");
const plugin = @import("gen/google/protobuf/compiler.pb.zig");
const descriptor = @import("gen/google/protobuf.pb.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Read entire stdin (CodeGeneratorRequest bytes)
    const input = try std.fs.File.stdin().readToEndAlloc(alloc, 100 * 1024 * 1024);
    defer alloc.free(input);

    // Decode request
    var reader: std.Io.Reader = .fixed(input);
    var request = try plugin.CodeGeneratorRequest.decode(&reader, alloc);
    defer request.deinit(alloc);

    // Build map: file name → FileDescriptorProto
    var file_map = std.StringHashMap(*const descriptor.FileDescriptorProto).init(alloc);
    defer file_map.deinit();
    for (request.proto_file.items) |*f| {
        if (f.name) |name| try file_map.put(name, f);
    }

    // Build response
    var response: plugin.CodeGeneratorResponse = .{};
    defer response.deinit(alloc);

    for (request.file_to_generate.items) |file_name| {
        const file_desc = file_map.get(file_name) orelse continue;

        // Build content: one comment per top-level message
        var content: std.ArrayListUnmanaged(u8) = .{};
        defer content.deinit(alloc);
        for (file_desc.message_type.items) |msg| {
            if (msg.name) |name| {
                try content.writer(alloc).print("// Message: {s}\n", .{name});
            }
        }

        // Output name: strip .proto, append .zig
        const base = file_name[0 .. file_name.len - ".proto".len];
        const out_name = try std.mem.concat(alloc, u8, &.{ base, ".zig" });

        const out_file: plugin.CodeGeneratorResponse.File = .{
            .name = out_name,
            .content = try content.toOwnedSlice(alloc),
        };
        try response.file.append(alloc, out_file);
    }

    // Encode response and write to stdout
    var w: std.Io.Writer.Allocating = .init(alloc);
    defer w.deinit();
    try response.encode(&w.writer, alloc);
    try std.fs.File.stdout().writeAll(w.written());
}
