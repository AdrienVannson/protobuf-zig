//! Comptime derivation of message metadata from embedded descriptor bytes.
//! Doesn't depend on descriptor.proto to allow bootstrapping.
//!
//! TODO: fully AI-generated file, review and improve

const std = @import("std");
const metadata = @import("metadata.zig");

const MessageMetadata = metadata.MessageMetadata;
const FieldMetadata = metadata.FieldMetadata;
const FieldMetadataKind = metadata.FieldMetadataKind;
const FieldMetadataElementType = metadata.FieldMetadataElementType;
const ScalarType = metadata.ScalarType;
const DefaultValue = metadata.DefaultValue;
const SupportedFieldPresence = metadata.SupportedFieldPresence;

// Hard-coded field numbers and enum values from descriptor.proto
const FileDescriptorProto = struct {
    const package = 2;
    const message_type = 4;
    const syntax = 12;
    const edition = 14;
};
const DescriptorProto = struct {
    const name = 1;
    const field = 2;
    const nested_type = 3;
    const options = 7;
    const oneof_decl = 8;
};
const MessageOptions = struct {
    const map_entry = 7;
};
const FieldDescriptorProto = struct {
    const name = 1;
    const number = 3;
    const label = 4;
    const @"type" = 5;
    const type_name = 6;
    const default_value = 7;
    const options = 8;
    const oneof_index = 9;
    const json_name = 10;
    const proto3_optional = 17;

    const Type = struct {
        const group = 10;
        const message = 11;
        const @"enum" = 14;
    };
    const Label = struct {
        const required = 2;
        const repeated = 3;
    };
};
const FieldOptions = struct {
    const @"packed" = 2;
};
const Edition = struct {
    const proto3 = 999;
};

/// Parse `bytes` (a serialized `FileDescriptorProto`) at comptime and return the
/// metadata for the message addressed by `path`.
///
/// `path` is an index-only tuple: `path[0]` selects the top-level message
/// (`message_type`), and each further element selects a `nested_type`. Indices
/// count only real messages — synthetic map-entry messages are skipped, matching
/// the code generator's message walk. So `.{2}` is the 3rd top-level message and
/// `.{0, 1}` is `message[0]`'s 2nd (non-map-entry) nested message.
pub fn readMessageMetadata(comptime bytes: []const u8, comptime path: anytype) MessageMetadata {
    @setEvalBranchQuota(100_000_000);
    const is_proto3 = fileIsProto3(bytes);
    const msg_bytes = navigateToMessage(bytes, path);
    const fqn = buildFqn(bytes, path);
    return parseMessage(msg_bytes, is_proto3, fqn);
}

// ---------------------------------------------------------------------------
// Wire-format primitives (pure comptime arithmetic over []const u8)
// ---------------------------------------------------------------------------

const VarintResult = struct { value: u64, pos: usize };
const TagResult = struct { field: u32, wire: u3, pos: usize };

fn readVarint(comptime bytes: []const u8, comptime pos: usize) VarintResult {
    var result: u64 = 0;
    var shift: u6 = 0;
    var i = pos;
    while (true) {
        const byte = bytes[i];
        i += 1;
        result |= @as(u64, byte & 0x7f) << shift;
        if (byte & 0x80 == 0) break;
        shift += 7;
    }
    return .{ .value = result, .pos = i };
}

fn readTag(comptime bytes: []const u8, comptime pos: usize) TagResult {
    const v = readVarint(bytes, pos);
    return .{ .field = @intCast(v.value >> 3), .wire = @intCast(v.value & 0x7), .pos = v.pos };
}

/// Advance past the payload of a field whose tag was already consumed.
fn skipPayload(comptime bytes: []const u8, comptime pos: usize, comptime wire: u3) usize {
    return switch (wire) {
        0 => readVarint(bytes, pos).pos, // varint
        1 => pos + 8, // bit64
        5 => pos + 4, // bit32
        2 => blk: { // length-delimited
            const v = readVarint(bytes, pos);
            break :blk v.pos + @as(usize, @intCast(v.value));
        },
        else => @compileError("readMessageMetadata: unexpected wire type in descriptor bytes"),
    };
}

/// Last varint value for `field_no` in `bytes`, or null. (Protobuf "last wins".)
fn getVarint(comptime bytes: []const u8, comptime field_no: u32) ?u64 {
    var pos: usize = 0;
    var result: ?u64 = null;
    while (pos < bytes.len) {
        const tg = readTag(bytes, pos);
        pos = tg.pos;
        if (tg.field == field_no and tg.wire == 0) {
            const v = readVarint(bytes, pos);
            result = v.value;
            pos = v.pos;
        } else pos = skipPayload(bytes, pos, tg.wire);
    }
    return result;
}

/// Last length-delimited payload for `field_no` (string / bytes / sub-message).
fn getBytes(comptime bytes: []const u8, comptime field_no: u32) ?[]const u8 {
    var pos: usize = 0;
    var result: ?[]const u8 = null;
    while (pos < bytes.len) {
        const tg = readTag(bytes, pos);
        pos = tg.pos;
        if (tg.field == field_no and tg.wire == 2) {
            const v = readVarint(bytes, pos);
            const start = v.pos;
            const len: usize = @intCast(v.value);
            result = bytes[start .. start + len];
            pos = start + len;
        } else pos = skipPayload(bytes, pos, tg.wire);
    }
    return result;
}

/// All length-delimited payloads for `field_no`, in order (repeated fields).
fn collectBytes(comptime bytes: []const u8, comptime field_no: u32) []const []const u8 {
    var out: []const []const u8 = &.{};
    var pos: usize = 0;
    while (pos < bytes.len) {
        const tg = readTag(bytes, pos);
        pos = tg.pos;
        if (tg.field == field_no and tg.wire == 2) {
            const v = readVarint(bytes, pos);
            const start = v.pos;
            const len: usize = @intCast(v.value);
            out = out ++ [_][]const u8{bytes[start .. start + len]};
            pos = start + len;
        } else pos = skipPayload(bytes, pos, tg.wire);
    }
    return out;
}

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------

fn fileIsProto3(comptime file_bytes: []const u8) bool {
    // Mirrors descFileFromProto: edition wins over syntax when present.
    if (getVarint(file_bytes, FileDescriptorProto.edition)) |ed| return ed == Edition.proto3;
    if (getBytes(file_bytes, FileDescriptorProto.syntax)) |syntax| return std.mem.eql(u8, syntax, "proto3");
    return false;
}

fn isMapEntry(comptime msg_bytes: []const u8) bool {
    const opts = getBytes(msg_bytes, DescriptorProto.options) orelse return false;
    return (getVarint(opts, MessageOptions.map_entry) orelse 0) != 0;
}

/// Return the bytes of the `n`-th non-map-entry message under `field_no`.
fn nthRealMessage(comptime bytes: []const u8, comptime field_no: u32, comptime n: usize) []const u8 {
    var count: usize = 0;
    var pos: usize = 0;
    while (pos < bytes.len) {
        const tg = readTag(bytes, pos);
        pos = tg.pos;
        if (tg.field == field_no and tg.wire == 2) {
            const v = readVarint(bytes, pos);
            const start = v.pos;
            const len: usize = @intCast(v.value);
            const payload = bytes[start .. start + len];
            pos = start + len;
            if (!isMapEntry(payload)) {
                if (count == n) return payload;
                count += 1;
            }
        } else pos = skipPayload(bytes, pos, tg.wire);
    }
    @compileError("readMessageMetadata: message path index out of range");
}

fn buildFqn(comptime file_bytes: []const u8, comptime path: anytype) []const u8 {
    comptime var fqn: []const u8 = getBytes(file_bytes, FileDescriptorProto.package) orelse "";
    comptime var cur: []const u8 = file_bytes;
    comptime var depth: usize = 0;
    inline for (path) |idx| {
        const field_no: u32 = if (depth == 0) FileDescriptorProto.message_type else DescriptorProto.nested_type;
        cur = nthRealMessage(cur, field_no, idx);
        const msg_name: []const u8 = getBytes(cur, DescriptorProto.name) orelse
            @compileError("readMessageMetadata: message descriptor missing name field");
        fqn = if (fqn.len > 0)
            std.fmt.comptimePrint("{s}.{s}", .{ fqn, msg_name })
        else
            msg_name;
        depth += 1;
    }
    return fqn;
}

fn navigateToMessage(comptime file_bytes: []const u8, comptime path: anytype) []const u8 {
    var cur: []const u8 = file_bytes;
    comptime var depth: usize = 0;
    inline for (path) |idx| {
        const field_no: u32 = if (depth == 0) FileDescriptorProto.message_type else DescriptorProto.nested_type;
        cur = nthRealMessage(cur, field_no, idx);
        depth += 1;
    }
    return cur;
}

// ---------------------------------------------------------------------------
// FieldDescriptorProto parsing + resolution (mirrors desc_file_from_proto.zig)
// ---------------------------------------------------------------------------

const FieldInfo = struct {
    name: []const u8,
    number: u32,
    json_name: []const u8,
    label: u64,
    type: u64,
    type_name: ?[]const u8,
    default_value: ?[]const u8,
    oneof_index: ?usize,
    proto3_optional: bool,
    packed_opt: ?bool,
};

fn parseFieldInfo(comptime fb: []const u8) FieldInfo {
    const name = getBytes(fb, FieldDescriptorProto.name) orelse @compileError("descriptor field missing name");
    const opts = getBytes(fb, FieldDescriptorProto.options);
    return .{
        .name = name,
        .number = @intCast(getVarint(fb, FieldDescriptorProto.number) orelse @compileError("descriptor field missing number")),
        .json_name = getBytes(fb, FieldDescriptorProto.json_name) orelse @compileError("descriptor field missing json_name"),
        .label = getVarint(fb, FieldDescriptorProto.label) orelse @compileError("descriptor field missing label"),
        .type = getVarint(fb, FieldDescriptorProto.type) orelse @compileError("descriptor field missing type"),
        .type_name = getBytes(fb, FieldDescriptorProto.type_name),
        .default_value = getBytes(fb, FieldDescriptorProto.default_value),
        .oneof_index = if (getVarint(fb, FieldDescriptorProto.oneof_index)) |o| @intCast(o) else null,
        .proto3_optional = (getVarint(fb, FieldDescriptorProto.proto3_optional) orelse 0) != 0,
        .packed_opt = if (opts) |o| (if (getVarint(o, FieldOptions.@"packed")) |p| (p != 0) else null) else null,
    };
}

/// A field belongs to a real (non-synthetic) oneof iff it has a oneof_index and
/// is not a proto3 `optional` field (those live in synthetic oneofs).
fn isRealOneofMember(comptime fi: FieldInfo) bool {
    return fi.oneof_index != null and !fi.proto3_optional;
}

fn scalarFromType(comptime t: u64) ?ScalarType {
    // ScalarType's integer values match FieldDescriptorProto.Type, so group(10),
    // message(11) and enum(14) have no ScalarType and yield null.
    return std.enums.fromInt(ScalarType, @as(i32, @intCast(t)));
}

fn computePresence(comptime fi: FieldInfo, comptime is_proto3: bool) SupportedFieldPresence {
    if (fi.label == FieldDescriptorProto.Label.required) return .legacy_required;
    if (fi.label == FieldDescriptorProto.Label.repeated) return .implicit;
    if (fi.oneof_index != null) return .explicit;
    if (fi.type == FieldDescriptorProto.Type.message or fi.type == FieldDescriptorProto.Type.group) return .explicit;
    if (!is_proto3) return .explicit;
    return .implicit;
}

fn computePacked(comptime fi: FieldInfo, comptime is_proto3: bool) bool {
    if (fi.packed_opt) |p| return p;
    if (!is_proto3) return false;
    return switch (fi.type) {
        1, 2, 3, 4, 5, 6, 7, 8, 13, 14, 15, 16, 17, 18 => true, // numeric + enum
        else => false, // string(9), group(10), message(11), bytes(12)
    };
}

fn parseDefaultValue(comptime sc: ScalarType, comptime raw: ?[]const u8) ?DefaultValue {
    const s = raw orelse return null;
    if (s.len == 0) return null;
    return switch (sc) {
        .bool => .{ .bool = std.mem.eql(u8, s, "true") },
        .int32, .sint32, .sfixed32 => .{ .int32 = std.fmt.parseInt(i32, s, 10) catch return null },
        .int64, .sint64, .sfixed64 => .{ .int64 = std.fmt.parseInt(i64, s, 10) catch return null },
        .uint32, .fixed32 => .{ .uint32 = std.fmt.parseInt(u32, s, 10) catch return null },
        .uint64, .fixed64 => .{ .uint64 = std.fmt.parseInt(u64, s, 10) catch return null },
        .float => .{ .float = std.fmt.parseFloat(f32, s) catch return null },
        .double => .{ .double = std.fmt.parseFloat(f64, s) catch return null },
        .string => .{ .string = s },
        .bytes => .{ .bytes = s },
    };
}

fn enumDefault(comptime fi: FieldInfo) i32 {
    const s = fi.default_value orelse return 0;
    return std.fmt.parseInt(i32, s, 10) catch 0;
}

fn elementType(comptime fi: FieldInfo) FieldMetadataElementType {
    if (scalarFromType(fi.type)) |sc| return .{ .scalar = sc };
    if (fi.type == FieldDescriptorProto.Type.message or fi.type == FieldDescriptorProto.Type.group) return .{ .message = {} };
    if (fi.type == FieldDescriptorProto.Type.@"enum") return .{ .enum_type = {} };
    @compileError("readMessageMetadata: invalid field element type");
}

fn simpleName(comptime tn: []const u8) []const u8 {
    var i = tn.len;
    while (i > 0) : (i -= 1) {
        if (tn[i - 1] == '.') return tn[i..];
    }
    return tn;
}

/// Find a map-entry message nested in `msg_bytes` matching `type_name`.
fn findMapEntry(comptime msg_bytes: []const u8, comptime type_name: []const u8) ?[]const u8 {
    const target = simpleName(type_name);
    for (collectBytes(msg_bytes, DescriptorProto.nested_type)) |nb| {
        const nm = getBytes(nb, FieldDescriptorProto.name) orelse continue;
        if (std.mem.eql(u8, nm, target) and isMapEntry(nb)) return nb;
    }
    return null;
}

const MapKV = struct { key: ScalarType, value: FieldMetadataElementType };

fn mapKeyValue(comptime entry: []const u8) MapKV {
    var key: ?ScalarType = null;
    var value: ?FieldMetadataElementType = null;
    for (collectBytes(entry, DescriptorProto.field)) |fb| {
        const fi = parseFieldInfo(fb);
        if (fi.number == 1) key = scalarFromType(fi.type) orelse @compileError("map key is not scalar");
        if (fi.number == 2) value = elementType(fi);
    }
    return .{
        .key = key orelse @compileError("map entry missing key field"),
        .value = value orelse @compileError("map entry missing value field"),
    };
}

/// Kind for a plain (non-oneof) field. Mirrors codegen's `_metadata` emission:
/// `message_field`/`list`/`map` carry only the fields codegen writes.
fn buildPlainKind(comptime msg_bytes: []const u8, comptime fi: FieldInfo, comptime is_proto3: bool) FieldMetadataKind {
    const repeated = fi.label == FieldDescriptorProto.Label.repeated;

    if (repeated and (fi.type == FieldDescriptorProto.Type.message or fi.type == FieldDescriptorProto.Type.group)) {
        if (fi.type_name) |tn| {
            if (findMapEntry(msg_bytes, tn)) |entry| {
                const kv = mapKeyValue(entry);
                return .{ .map = .{ .key = kv.key, .value = kv.value } };
            }
        }
    }

    if (repeated) {
        return .{ .list = .{
            .element = elementType(fi),
            .is_packed = computePacked(fi, is_proto3),
        } };
    }

    if (fi.type == FieldDescriptorProto.Type.message or fi.type == FieldDescriptorProto.Type.group) {
        return .{ .message_field = .{ .presence = computePresence(fi, is_proto3) } };
    }
    if (fi.type == FieldDescriptorProto.Type.@"enum") {
        return .{ .enum_field = .{
            .presence = computePresence(fi, is_proto3),
            .default_value = enumDefault(fi),
        } };
    }
    const sc = scalarFromType(fi.type) orelse @compileError("readMessageMetadata: invalid scalar type");
    return .{ .scalar = .{
        .scalar = sc,
        .presence = computePresence(fi, is_proto3),
        .default_value = parseDefaultValue(sc, fi.default_value),
    } };
}

/// Kind for a oneof variant. Oneof variants are always singular and codegen omits
/// presence (and scalar defaults) for them.
fn buildOneofKind(comptime fi: FieldInfo) FieldMetadataKind {
    if (fi.type == FieldDescriptorProto.Type.message or fi.type == FieldDescriptorProto.Type.group) return .{ .message_field = .{} };
    if (fi.type == FieldDescriptorProto.Type.@"enum") return .{ .enum_field = .{ .default_value = enumDefault(fi) } };
    const sc = scalarFromType(fi.type) orelse @compileError("readMessageMetadata: invalid oneof scalar type");
    return .{ .scalar = .{ .scalar = sc } };
}

fn parseMessage(comptime msg_bytes: []const u8, comptime is_proto3: bool, comptime fqn: []const u8) MessageMetadata {
    const field_protos = collectBytes(msg_bytes, DescriptorProto.field);
    const oneof_protos = collectBytes(msg_bytes, DescriptorProto.oneof_decl);

    // Pre-parse every field once.
    var infos: []const FieldInfo = &.{};
    inline for (field_protos) |fb| {
        infos = infos ++ [_]FieldInfo{parseFieldInfo(fb)};
    }

    var out: []const FieldMetadata = &.{};
    var field_index: u16 = 0;

    // Plain fields first, in declaration order (matches codegen's struct layout).
    inline for (infos) |fi| {
        if (isRealOneofMember(fi)) continue;
        out = out ++ [_]FieldMetadata{.{
            .number = fi.number,
            .field_index = field_index,
            .proto_name = fi.name,
            .json_name = fi.json_name,
            .kind = buildPlainKind(msg_bytes, fi, is_proto3),
        }};
        field_index += 1;
    }

    // Then each real oneof, in oneof_decl order; all variants share one index.
    inline for (oneof_protos, 0..) |_, oi| {
        var has_real_member = false;
        inline for (infos) |fi| {
            if (isRealOneofMember(fi) and fi.oneof_index.? == oi) {
                has_real_member = true;
            }
        }
        if (!has_real_member) continue; // synthetic / empty oneof

        inline for (infos) |fi| {
            if (!isRealOneofMember(fi) or fi.oneof_index.? != oi) continue;
            out = out ++ [_]FieldMetadata{.{
                .number = fi.number,
                .field_index = field_index,
                .oneof_variant = fi.name,
                .proto_name = fi.name,
                .json_name = fi.json_name,
                .kind = buildOneofKind(fi),
            }};
        }
        field_index += 1;
    }

    return .{ .fields = out, .fully_qualified_proto_name = fqn };
}
