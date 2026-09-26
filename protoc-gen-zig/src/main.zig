const std = @import("std");
const plugin = @import("gen/google/protobuf/compiler/plugin.pb.zig");
const codegen = @import("codegen.zig");
const protobuf = @import("protobuf");
const descFileFromProto = protobuf._codegen.descFileFromProto;
const OwnedDescFile = protobuf._codegen.OwnedDescFile;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    // Read entire stdin (CodeGeneratorRequest bytes)
    var stdin_buf: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &stdin_buf);
    const input = try stdin_reader.interface.allocRemaining(allocator, .unlimited);
    defer allocator.free(input);

    // Decode request
    var request: plugin.CodeGeneratorRequest = .{};
    defer request.deinit(allocator);
    try protobuf.fromBinary(&request, allocator, input);

    // Build map: file name → FileDescriptorProto
    var file_map = std.StringHashMap(*protobuf.wkt.descriptor.FileDescriptorProto).init(allocator);
    defer file_map.deinit();
    for (request.proto_file.items) |f| {
        if (f.name) |name| try file_map.put(name, f);
    }

    // Build DescFile graph for all proto files.
    // protoc guarantees proto_file is in topological order (deps before dependents),
    // so each file's imports are already in desc_by_name when we process it.
    var desc_by_name = std.StringHashMap(*const protobuf.DescFile).init(allocator);
    defer desc_by_name.deinit();
    var owned_descs: std.ArrayList(OwnedDescFile) = .empty;
    defer {
        for (owned_descs.items) |*o| o.deinit();
        owned_descs.deinit(allocator);
    }
    for (request.proto_file.items) |f| {
        const owned = try descFileFromProto(allocator, f, &desc_by_name);
        try owned_descs.append(allocator, owned);
        // Reference the stable arena-owned file from the just-appended element.
        const last = &owned_descs.items[owned_descs.items.len - 1];
        if (f.name) |name| try desc_by_name.put(name, last.file);
    }

    // Build response
    var response: plugin.CodeGeneratorResponse = .{
        .supported_features = @intFromEnum(plugin.CodeGeneratorResponse.Feature.FEATURE_PROTO3_OPTIONAL) | @intFromEnum(plugin.CodeGeneratorResponse.Feature.FEATURE_SUPPORTS_EDITIONS),
        .minimum_edition = @intFromEnum(protobuf.wkt.descriptor.Edition.EDITION_PROTO2),
        .maximum_edition = @intFromEnum(protobuf.wkt.descriptor.Edition.EDITION_2023),
    };
    defer response.deinit(allocator);

    for (request.file_to_generate.items) |file_name| {
        const file_desc = file_map.get(file_name) orelse continue;
        const desc_file = desc_by_name.get(file_name) orelse continue;

        const content = try codegen.generateFile(allocator, desc_file, file_desc);

        // Output name: strip .proto, append .zig
        const base = file_name[0 .. file_name.len - ".proto".len];
        const out_name = try std.mem.concat(allocator, u8, &.{ base, ".pb.zig" });

        const out_file = try allocator.create(plugin.CodeGeneratorResponse.File);
        out_file.* = .{
            .name = out_name,
            .content = content,
        };
        try response.file.append(allocator, out_file);
    }

    // Encode response and write to stdout
    const encoded = try protobuf.toBinary(allocator, response);
    defer allocator.free(encoded);
    try std.Io.File.stdout().writeStreamingAll(io, encoded);
}

test {
    _ = codegen;
    _ = @import("generated_file.zig");
    _ = @import("wkt_methods/any.zig");
}
