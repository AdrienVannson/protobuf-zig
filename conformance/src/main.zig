const std = @import("std");
const conformance_pb = @import("gen_conformance");
const gen_proto3 = @import("gen_proto3");
const protobuf = @import("protobuf");

const ConformanceRequest = conformance_pb.ConformanceRequest;
const ConformanceResponse = conformance_pb.ConformanceResponse;

pub fn main(init: std.process.Init) !void {
    var stdin_buf: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(init.io, &stdin_buf);
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(init.io, &stdout_buf);

    var alloc = init.arena.allocator();

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
        var response = try handleRequest(&request, alloc);
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

fn handleRequest(request: *ConformanceRequest, alloc: std.mem.Allocator) !ConformanceResponse {
    // Dispatch proto3 binary roundtrip.
    if (std.mem.eql(u8, request.getMessageType(), "protobuf_test_messages.proto3.TestAllTypesProto3")) {
        // Only handle binary protobuf output; skip JSON, text, etc.
        if (request.getRequestedOutputFormat() != .PROTOBUF) {
            return .{ .result = .{ .skipped = try alloc.dupe(u8, "non-binary output format not supported") } };
        }
        const payload = if (request.payload) |p| switch (p) {
            .protobuf_payload => |b| b,
            else => return .{ .result = .{ .skipped = try alloc.dupe(u8, "non-binary payload not supported") } },
        } else return .{ .result = .{ .skipped = try alloc.dupe(u8, "no payload") } };

        var test_gpa = std.heap.DebugAllocator(.{}){};
        const test_alloc = test_gpa.allocator();

        var response = try roundTrip(payload, test_alloc, alloc);
        if (test_gpa.deinit() == .leak) {
            response.deinit(alloc);
            return .{ .result = .{ .runtime_error = try alloc.dupe(u8, "memory leak detected") } };
        }
        return response;
    }

    // proto2 test messages use group fields, unsupported by zig-protobuf's generator.
    return .{ .result = .{ .skipped = try alloc.dupe(u8, "payload decode not yet supported") } };
}

fn roundTrip(payload: []const u8, inner_alloc: std.mem.Allocator, result_alloc: std.mem.Allocator) !ConformanceResponse {
    var msg: gen_proto3.TestAllTypesProto3 = .{};
    defer msg.deinit(inner_alloc);
    protobuf.from_binary(&msg, payload, inner_alloc) catch |err| {
        return .{ .result = .{ .parse_error = try result_alloc.dupe(u8, @errorName(err)) } };
    };
    const encoded = protobuf.to_binary(result_alloc, msg) catch |err| {
        return .{ .result = .{ .serialize_error = try result_alloc.dupe(u8, @errorName(err)) } };
    };
    return .{ .result = .{ .protobuf_payload = encoded } };
}
