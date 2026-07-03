const std = @import("std");
const conformance_pb = @import("gen_conformance");
const gen_proto3 = @import("gen_proto3");
const protobuf = @import("protobuf");

const ConformanceRequest = conformance_pb.ConformanceRequest;
const ConformanceResponse = conformance_pb.ConformanceResponse;
const WireFormat = conformance_pb.WireFormat;

pub fn main(init: std.process.Init) !void {
    var stdin_buf: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(init.io, &stdin_buf);
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(init.io, &stdout_buf);

    var alloc = init.arena.allocator();

    // Registry used to resolve `google.protobuf.Any` payloads during JSON
    // (de)serialization. Arena-owned, lives for the whole process.
    var registry = protobuf.Registry.empty;
    try registry.registerFile(alloc, gen_proto3);
    try registry.registerFile(alloc, protobuf.wkt.any);
    try registry.registerFile(alloc, protobuf.wkt.wrappers);
    try registry.registerFile(alloc, protobuf.wkt.struct_);
    try registry.registerFile(alloc, protobuf.wkt.duration);
    try registry.registerFile(alloc, protobuf.wkt.timestamp);
    try registry.registerFile(alloc, protobuf.wkt.field_mask);

    while (true) {
        // Read 4-byte little-endian request length; EOF here means clean shutdown.
        var len_buf: [4]u8 = undefined;
        stdin_reader.interface.readSliceAll(&len_buf) catch break;
        const request_len = std.mem.readInt(u32, &len_buf, .little);

        // Read request bytes.
        const request_bytes = try alloc.alloc(u8, request_len);
        defer alloc.free(request_bytes);
        try stdin_reader.interface.readSliceAll(request_bytes);

        // Decode ConformanceRequest.
        var request: ConformanceRequest = .{};
        defer request.deinit(alloc);
        try protobuf.from_binary(&request, request_bytes, alloc);

        // Build response.
        var response = try handleRequest(&request, alloc, &registry);
        defer response.deinit(alloc);

        // Encode ConformanceResponse.
        const response_bytes = try protobuf.to_binary(alloc, response);
        defer alloc.free(response_bytes);

        // Write 4-byte LE length + response bytes.
        var out_len_buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &out_len_buf, @intCast(response_bytes.len), .little);
        try stdout_writer.interface.writeAll(&out_len_buf);
        try stdout_writer.interface.writeAll(response_bytes);
        try stdout_writer.flush();
    }
}

fn handleRequest(request: *ConformanceRequest, alloc: std.mem.Allocator, registry: *const protobuf.Registry) !ConformanceResponse {
    // Dispatch proto3 binary/JSON roundtrip.
    if (std.mem.eql(u8, request.getMessageType(), "protobuf_test_messages.proto3.TestAllTypesProto3")) {
        const output_format = request.getRequestedOutputFormat();
        if (output_format != .PROTOBUF and output_format != .JSON) {
            return .{ .result = .{ .skipped = try alloc.dupe(u8, "TEXT_FORMAT and JSPB output not supported") } };
        }

        var test_gpa = std.heap.DebugAllocator(.{}){};
        const test_alloc = test_gpa.allocator();

        var msg: gen_proto3.TestAllTypesProto3 = .{};

        // Parse
        const maybe_parse_err: ?ConformanceResponse = blk: {
            if (request.payload) |p| switch (p) {
                .protobuf_payload => |bytes| protobuf.from_binary(&msg, bytes, test_alloc) catch |err|
                    break :blk .{ .result = .{ .parse_error = try alloc.dupe(u8, @errorName(err)) } },
                .json_payload => |json_str| protobuf.from_json(&msg, json_str, test_alloc, registry) catch |err|
                    break :blk .{ .result = .{ .parse_error = try alloc.dupe(u8, @errorName(err)) } },
                else => break :blk .{ .result = .{ .skipped = try alloc.dupe(u8, "JSPB and TEXT_FORMAT payloads not supported") } },
            } else break :blk .{ .result = .{ .skipped = try alloc.dupe(u8, "no payload") } };
            break :blk null;
        };

        // Serialize
        var response: ConformanceResponse = if (maybe_parse_err) |r| r else switch (output_format) {
            .PROTOBUF => serialize: {
                const encoded = protobuf.to_binary(alloc, msg) catch |err|
                    break :serialize .{ .result = .{ .serialize_error = try alloc.dupe(u8, @errorName(err)) } };
                break :serialize .{ .result = .{ .protobuf_payload = encoded } };
            },
            .JSON => serialize: {
                const json_out = protobuf.to_json(alloc, msg, registry) catch |err|
                    break :serialize .{ .result = .{ .serialize_error = try alloc.dupe(u8, @errorName(err)) } };
                break :serialize .{ .result = .{ .json_payload = json_out } };
            },
            else => unreachable,
        };

        msg.deinit(test_alloc);
        if (test_gpa.deinit() == .leak) {
            response.deinit(alloc);
            return .{ .result = .{ .runtime_error = try alloc.dupe(u8, "memory leak detected") } };
        }
        return response;
    }

    // proto2 test messages use group fields, unsupported by zig-protobuf's generator.
    return .{ .result = .{ .skipped = try alloc.dupe(u8, "payload decode not yet supported") } };
}
