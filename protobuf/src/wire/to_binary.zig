const std = @import("std");
const binary_writer_mod = @import("binary_writer.zig");
const tag_mod = @import("tag.zig");
const metadata_mod = @import("../_codegen/metadata.zig");
const field_access = @import("../_codegen/field_access.zig");

const BinaryWriter = binary_writer_mod.BinaryWriter;
const WireType = tag_mod.WireType;
const ScalarType = metadata_mod.ScalarType;
const FieldMetadata = metadata_mod.FieldMetadata;

/// Returns the wire type for a ScalarType.
fn scalarWireType(comptime scalar: ScalarType) WireType {
    return switch (scalar) {
        .int32, .int64, .uint32, .uint64, .sint32, .sint64, .bool => .varint,
        .fixed32, .sfixed32, .float => .bit32,
        .fixed64, .sfixed64, .double => .bit64,
        .string, .bytes => .length_delimited,
    };
}

/// Writes a scalar value to bw using the appropriate BinaryWriter method.
fn writeScalar(bw: *BinaryWriter, comptime scalar: ScalarType, value: metadata_mod.scalarZigType(scalar)) !void {
    switch (scalar) {
        .int32 => try bw.int32(value),
        .int64 => try bw.int64(value),
        .uint32 => try bw.uint32(value),
        .uint64 => try bw.uint64(value),
        .sint32 => try bw.sint32(value),
        .sint64 => try bw.sint64(value),
        .fixed32 => try bw.fixed32(value),
        .fixed64 => try bw.fixed64(value),
        .sfixed32 => try bw.sfixed32(value),
        .sfixed64 => try bw.sfixed64(value),
        .bool => try bw.bool_(value),
        .float => try bw.float_(value),
        .double => try bw.double(value),
        .string => try bw.string(value),
        .bytes => try bw.bytes(value),
    }
}

const WriteMessageError = error{ OutOfMemory, JoinWithoutFork };

fn writeMessageField(bw: *BinaryWriter, comptime number: u32, child: anytype) WriteMessageError!void {
    try bw.tag(number, .length_delimited);
    try bw.fork();
    try writeMessage(bw, child);
    try bw.join();
}

fn writeListField(
    bw: *BinaryWriter,
    list: anytype,
    comptime list_meta: anytype,
    comptime number: u32,
) WriteMessageError!void {
    if (list.items.len == 0) return;
    switch (comptime list_meta.element) {
        .scalar => |sc| {
            if (comptime list_meta.is_packed) {
                try bw.tag(number, .length_delimited);
                try bw.fork();
                for (list.items) |v| try writeScalar(bw, sc, v);
                try bw.join();
            } else {
                for (list.items) |v| {
                    try bw.tag(number, comptime scalarWireType(sc));
                    try writeScalar(bw, sc, v);
                }
            }
        },
        .message => {
            for (list.items) |child_ptr| {
                try writeMessageField(bw, number, child_ptr.*);
            }
        },
        .enum_type => {
            if (comptime list_meta.is_packed) {
                try bw.tag(number, .length_delimited);
                try bw.fork();
                for (list.items) |v| try bw.int32(@intFromEnum(v));
                try bw.join();
            } else {
                for (list.items) |v| {
                    try bw.tag(number, .varint);
                    try bw.int32(@intFromEnum(v));
                }
            }
        },
    }
}

/// Callback used by `forEachSetField` inside `writeMessage`.
/// Receives each set field's payload and writes it to the BinaryWriter.
fn writeFieldCallback(bw: *BinaryWriter, comptime fm: FieldMetadata, value: anytype) WriteMessageError!void {
    switch (comptime fm.kind) {
        .scalar => |sc| {
            try bw.tag(fm.number, comptime scalarWireType(sc.scalar));
            try writeScalar(bw, sc.scalar, value);
        },
        .enum_field => {
            try bw.tag(fm.number, .varint);
            try bw.int32(@intFromEnum(value));
        },
        .message_field => {
            try writeMessageField(bw, fm.number, value.*);
        },
        .list => |lm| {
            try writeListField(bw, value, lm, fm.number);
        },
        .map => {},
    }
}

/// Encodes all fields of msg into bw.
///
/// Uses `field_access.forEachSetField` to iterate over every field that is currently "set"
/// (presence-aware: implicit fields skip the proto3 default value, explicit fields skip null).
/// Oneof fields are handled transparently by `hasField` / `getField` in field_access.zig.
fn writeMessage(bw: *BinaryWriter, msg: anytype) WriteMessageError!void {
    try field_access.forEachSetField(msg, bw, writeFieldCallback);
}

/// Serializes a message to its binary Protocol Buffer representation,
/// returning the encoded bytes as a caller-owned slice (freed with allocator).
pub fn to_binary(allocator: std.mem.Allocator, msg: anytype) ![]u8 {
    var bw = BinaryWriter.init(allocator);
    defer bw.deinit();
    try writeMessage(&bw, msg);
    return bw.toOwnedSlice();
}
