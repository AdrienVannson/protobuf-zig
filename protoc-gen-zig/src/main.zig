const std = @import("std");
const plugin = @import("gen/google/protobuf/compiler.pb.zig");
const descriptor = @import("gen/google/protobuf.pb.zig");
const codegen = @import("codegen.zig");
const desc_file_from_proto = @import("desc_file_from_proto.zig");
const protobuf = @import("our_protobuf");

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

    // Build DescFile graph for all proto files.
    // protoc guarantees proto_file is in topological order (deps before dependents),
    // so each file's imports are already in desc_by_name when we process it.
    var desc_by_name = std.StringHashMap(*const protobuf.DescFile).init(alloc);
    defer desc_by_name.deinit();
    var owned_descs: std.ArrayList(desc_file_from_proto.OwnedDescFile) = .{};
    defer {
        for (owned_descs.items) |*o| o.deinit();
        owned_descs.deinit(alloc);
    }
    for (request.proto_file.items) |*f| {
        const owned = try desc_file_from_proto.descFileFromProto(f, &desc_by_name, alloc);
        try owned_descs.append(alloc, owned);
        // Reference the stable arena-owned file from the just-appended element.
        const last = &owned_descs.items[owned_descs.items.len - 1];
        if (f.name) |name| try desc_by_name.put(name, last.file);
    }

    // Build response
    var response: plugin.CodeGeneratorResponse = .{
        .supported_features = @intFromEnum(plugin.CodeGeneratorResponse.Feature.FEATURE_PROTO3_OPTIONAL) | @intFromEnum(plugin.CodeGeneratorResponse.Feature.FEATURE_SUPPORTS_EDITIONS),
        .minimum_edition = 998, // EDITION_PROTO_2, TODO use constant
        .maximum_edition = 1000, // EDITION_2023, TODO use constant
    };
    defer response.deinit(alloc);

    for (request.file_to_generate.items) |file_name| {
        const file_desc = file_map.get(file_name) orelse continue;
        const desc_file = desc_by_name.get(file_name) orelse continue;

        const content = try codegen.generateFile(alloc, desc_file, file_desc);

        // Output name: strip .proto, append .zig
        const base = file_name[0 .. file_name.len - ".proto".len];
        const out_name = try std.mem.concat(alloc, u8, &.{ base, ".pb.zig" });

        const out_file: plugin.CodeGeneratorResponse.File = .{
            .name = out_name,
            .content = content,
        };
        try response.file.append(alloc, out_file);
    }

    // Encode response and write to stdout
    var w: std.Io.Writer.Allocating = .init(alloc);
    defer w.deinit();
    try response.encode(&w.writer, alloc);
    try std.fs.File.stdout().writeAll(w.written());
}
