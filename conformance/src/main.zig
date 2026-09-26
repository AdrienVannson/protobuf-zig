const std = @import("std");
const conformance_pb = @import("gen/conformance/conformance.pb.zig");
const protobuf = @import("protobuf");

/// Generated files whose messages the runner may request, plus the
/// well-known types needed to resolve `google.protobuf.Any` in JSON.
const registered_files = .{
    @import("gen/google/protobuf/test_messages_proto2.pb.zig"),
    @import("gen/google/protobuf/test_messages_proto3.pb.zig"),
    @import("gen/google/protobuf/test_messages_proto2_editions.pb.zig"),
    @import("gen/google/protobuf/test_messages_proto3_editions.pb.zig"),
    @import("gen/google/protobuf/test_messages_edition2023.pb.zig"),
    protobuf.wkt.any,
    protobuf.wkt.wrappers,
    protobuf.wkt.struct_,
    protobuf.wkt.duration,
    protobuf.wkt.timestamp,
    protobuf.wkt.field_mask,
    protobuf.wkt.empty,
};

const ConformanceRequest = conformance_pb.ConformanceRequest;
const ConformanceResponse = conformance_pb.ConformanceResponse;
const WireFormat = conformance_pb.WireFormat;

pub fn main(init: std.process.Init) !void {
    var stdin_buf: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(init.io, &stdin_buf);
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(init.io, &stdout_buf);

    var allocator = init.arena.allocator();

    // Registry used to look up the requested message type and for JSON (de)serialization.
    var registry: protobuf.Registry = .empty;
    inline for (registered_files) |file| try registry.registerFile(allocator, file);

    while (true) {
        // Read 4-byte little-endian request length; EOF here means clean shutdown.
        var len_buf: [4]u8 = undefined;
        stdin_reader.interface.readSliceAll(&len_buf) catch break;
        const request_len = std.mem.readInt(u32, &len_buf, .little);

        // Read request bytes.
        const request_bytes = try allocator.alloc(u8, request_len);
        defer allocator.free(request_bytes);
        try stdin_reader.interface.readSliceAll(request_bytes);

        // Decode ConformanceRequest.
        var request: ConformanceRequest = .{};
        defer request.deinit(allocator);
        try protobuf.fromBinary(&request, allocator, request_bytes);

        // Build response.
        var response = try handleRequest(allocator, &request, &registry);
        defer response.deinit(allocator);

        // Encode ConformanceResponse.
        const response_bytes = try protobuf.toBinary(allocator, response);
        defer allocator.free(response_bytes);

        // Write 4-byte LE length + response bytes.
        var out_len_buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &out_len_buf, @intCast(response_bytes.len), .little);
        try stdout_writer.interface.writeAll(&out_len_buf);
        try stdout_writer.interface.writeAll(response_bytes);
        try stdout_writer.flush();
    }
}

fn handleRequest(allocator: std.mem.Allocator, request: *ConformanceRequest, registry: *const protobuf.Registry) !ConformanceResponse {
    const ops = registry._getMessageOps(request.getMessageType()) orelse
        return .{ .result = .{ .skipped = try allocator.dupe(u8, "message type not supported") } };
    return roundtrip(allocator, ops, request, registry);
}

/// Parses the request payload into the message described by `ops` and serializes it back in the requested format.
fn roundtrip(allocator: std.mem.Allocator, ops: *const protobuf.MessageOps, request: *ConformanceRequest, registry: *const protobuf.Registry) !ConformanceResponse {
    const output_format = request.getRequestedOutputFormat();
    if (output_format != .PROTOBUF and output_format != .JSON) {
        return .{ .result = .{ .skipped = try allocator.dupe(u8, "TEXT_FORMAT and JSPB output not supported") } };
    }

    var test_gpa = std.heap.DebugAllocator(.{}){};
    const test_allocator = test_gpa.allocator();

    const msg = try ops.create(test_allocator);

    // Parse
    const maybe_parse_err: ?ConformanceResponse = blk: {
        if (request.payload) |p| switch (p) {
            .protobuf_payload => |bytes| ops.fromBinary(msg, test_allocator, bytes) catch |err|
                break :blk .{ .result = .{ .parse_error = try allocator.dupe(u8, @errorName(err)) } },
            .json_payload => |json_str| ops.fromJson(msg, test_allocator, json_str, registry) catch |err|
                break :blk .{ .result = .{ .parse_error = try allocator.dupe(u8, @errorName(err)) } },
            else => break :blk .{ .result = .{ .skipped = try allocator.dupe(u8, "JSPB and TEXT_FORMAT payloads not supported") } },
        } else break :blk .{ .result = .{ .skipped = try allocator.dupe(u8, "no payload") } };
        break :blk null;
    };

    // Serialize
    var response: ConformanceResponse = if (maybe_parse_err) |r| r else switch (output_format) {
        .PROTOBUF => serialize: {
            const encoded = ops.toBinary(allocator, msg) catch |err|
                break :serialize .{ .result = .{ .serialize_error = try allocator.dupe(u8, @errorName(err)) } };
            break :serialize .{ .result = .{ .protobuf_payload = encoded } };
        },
        .JSON => serialize: {
            const json_out = ops.toJson(allocator, msg, registry) catch |err|
                break :serialize .{ .result = .{ .serialize_error = try allocator.dupe(u8, @errorName(err)) } };
            break :serialize .{ .result = .{ .json_payload = json_out } };
        },
        else => unreachable,
    };

    ops.deinit(msg, test_allocator);
    ops.destroy(msg, test_allocator);
    if (test_gpa.deinit() == .leak) {
        response.deinit(allocator);
        return .{ .result = .{ .runtime_error = try allocator.dupe(u8, "memory leak detected") } };
    }
    return response;
}
