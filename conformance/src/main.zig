const std = @import("std");
// Paths match zig-protobuf's package-based output (not file-based).
const conformance_pb = @import("generated/conformance.pb.zig");
// test_messages_proto3.proto uses allow_alias enums and
// test_messages_proto2.proto uses group fields; both are unsupported by
// zig-protobuf's generator. Payload decode/encode is skipped at runtime.

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
        const response = try handleRequest(&request, alloc);

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

fn handleRequest(request: *ConformanceRequest, alloc: std.mem.Allocator) !ConformanceResponse {
    // First request: FailureSet negotiation — return empty FailureSet.
    if (std.mem.eql(u8, request.message_type, "conformance.FailureSet")) {
        var failure_set: FailureSet = .{};
        var w: std.Io.Writer.Allocating = .init(alloc);
        try failure_set.encode(&w.writer, alloc);
        return .{ .result = .{ .protobuf_payload = w.written() } };
    }

    // zig-protobuf's generator does not support allow_alias enums (proto3 test
    // messages) or group fields (proto2 test messages), so all payload tests
    // are skipped until upstream support is added.
    return .{ .result = .{ .skipped = "payload decode not yet supported" } };
}
