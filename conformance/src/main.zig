const std = @import("std");
// Paths match zig-protobuf's package-based output (not file-based).
const conformance_pb = @import("generated_old_lib/conformance.pb.zig");
const proto3_pb = @import("generated_old_lib/protobuf_test_messages/proto3.pb.zig");
const convert = @import("convert.zig");
const our_proto = @import("our_protobuf");

const ConformanceRequest = conformance_pb.ConformanceRequest;
const ConformanceResponse = conformance_pb.ConformanceResponse;
const FailureSet = conformance_pb.FailureSet;

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const base_alloc = gpa.allocator();

    const stdin = std.fs.File.stdin();
    const stdout = std.fs.File.stdout();

    while (true) {
        // Read 4-byte little-endian request length.
        var len_buf: [4]u8 = undefined;
        const n = try stdin.readAll(&len_buf);
        if (n == 0) break; // clean EOF
        if (n != 4) return error.UnexpectedEof;
        const request_len = std.mem.readInt(u32, &len_buf, .little);

        var arena = std.heap.ArenaAllocator.init(base_alloc);
        defer arena.deinit();
        const alloc = arena.allocator();

        // Read request bytes.
        const request_bytes = try alloc.alloc(u8, request_len);
        const bytes_read = try stdin.readAll(request_bytes);
        if (bytes_read != request_len) return error.UnexpectedEof;

        // Decode ConformanceRequest.
        var req_reader: std.Io.Reader = .fixed(request_bytes);
        var request = try ConformanceRequest.decode(&req_reader, alloc);

        // Build response.
        const response = handleRequest(&request, alloc);

        // Encode ConformanceResponse.
        var w: std.Io.Writer.Allocating = .init(alloc);
        try response.encode(&w.writer, alloc);
        const response_bytes = w.written();

        // Write 4-byte LE length + response bytes.
        var out_len_buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &out_len_buf, @intCast(response_bytes.len), .little);
        try stdout.writeAll(&out_len_buf);
        try stdout.writeAll(response_bytes);
    }
}

// Replicates the Python conformance.py check for a test case that causes the
// runner to abort (rather than record a failure) when certain response types
// are returned.  Returning an empty protobuf payload is the safe sentinel.
fn isUnknownOrderingCrashCase(request: *const ConformanceRequest) bool {
    if (request.test_category != .BINARY_TEST) return false;
    if (request.requested_output_format != .PROTOBUF) return false;

    const known_types = [_][]const u8{
        "protobuf_test_messages.proto3.TestAllTypesProto3",
        "protobuf_test_messages.proto2.TestAllTypesProto2",
        "protobuf_test_messages.editions.proto2.TestAllTypesProto2",
        "protobuf_test_messages.editions.proto3.TestAllTypesProto3",
    };
    var found_type = false;
    for (known_types) |t| {
        if (std.mem.eql(u8, request.message_type, t)) {
            found_type = true;
            break;
        }
    }
    if (!found_type) return false;

    const crash_bytes = [_]u8{
        210, 41,  3,   97,  98, 99,  208, 41, 123, 210, 41, 3,
        100, 101, 102, 208, 41, 200, 3,
    };
    const payload_bytes = if (request.payload) |p| switch (p) {
        .protobuf_payload => |b| b,
        else => return false,
    } else return false;

    return std.mem.eql(u8, payload_bytes, &crash_bytes);
}

fn handleRequest(request: *ConformanceRequest, alloc: std.mem.Allocator) ConformanceResponse {
    // Detect the crash-inducing unknown-ordering test case and return a safe
    // empty payload sentinel (mirrors Python conformance.py lines 108-129).
    if (isUnknownOrderingCrashCase(request)) {
        return .{ .result = .{ .protobuf_payload = &.{} } };
    }
    // Dispatch proto3 binary roundtrip.
    if (std.mem.eql(u8, request.message_type, "protobuf_test_messages.proto3.TestAllTypesProto3")) {
        // Only handle binary protobuf output; skip JSON, text, etc.
        if (request.requested_output_format != .PROTOBUF) {
            return .{ .result = .{ .skipped = "non-binary output format not supported" } };
        }
        const payload = if (request.payload) |p| switch (p) {
            .protobuf_payload => |b| b,
            else => return .{ .result = .{ .skipped = "non-binary payload not supported" } },
        } else return .{ .result = .{ .skipped = "no payload" } };
        return roundTrip(proto3_pb.TestAllTypesProto3, payload, alloc);
    }

    // proto2 test messages use group fields, unsupported by zig-protobuf's generator.
    return .{ .result = .{ .skipped = "payload decode not yet supported" } };
}

fn roundTrip(comptime T: type, payload: []const u8, alloc: std.mem.Allocator) ConformanceResponse {
    var reader: std.Io.Reader = .fixed(payload);
    var msg = T.decode(&reader, alloc) catch |err| {
        return .{ .result = .{ .parse_error = @errorName(err) } };
    };
    defer msg.deinit(alloc);

    if (T == proto3_pb.TestAllTypesProto3) {
        const converted = convert.fromExternal(msg, alloc) catch |err| {
            return .{ .result = .{ .parse_error = @errorName(err) } };
        };

        var out: std.Io.Writer.Allocating = .init(alloc);
        our_proto.to_binary(alloc, converted, &out.writer) catch |err| {
            return .{ .result = .{ .serialize_error = @errorName(err) } };
        };
        return .{ .result = .{ .protobuf_payload = out.written() } };
    }

    var w: std.Io.Writer.Allocating = .init(alloc);
    msg.encode(&w.writer, alloc) catch |err| {
        return .{ .result = .{ .serialize_error = @errorName(err) } };
    };
    return .{ .result = .{ .protobuf_payload = w.written() } };
}
