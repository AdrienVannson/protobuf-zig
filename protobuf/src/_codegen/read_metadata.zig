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

// Hard-coded field numbers from descriptor.proto
const FILE_MESSAGE_TYPE = 4; // FileDescriptorProto.message_type
const FILE_SYNTAX = 12; // FileDescriptorProto.syntax
const FILE_EDITION = 14; // FileDescriptorProto.edition
const MSG_FIELD = 2; // DescriptorProto.field
const MSG_NESTED_TYPE = 3; // DescriptorProto.nested_type
const MSG_OPTIONS = 7; // DescriptorProto.options
const MSG_ONEOF_DECL = 8; // DescriptorProto.oneof_decl
const MSGOPT_MAP_ENTRY = 7; // MessageOptions.map_entry
const FIELD_NAME = 1; // FieldDescriptorProto.name
const FIELD_NUMBER = 3; // FieldDescriptorProto.number
const FIELD_LABEL = 4; // FieldDescriptorProto.label
const FIELD_TYPE = 5; // FieldDescriptorProto.type
const FIELD_TYPE_NAME = 6; // FieldDescriptorProto.type_name
const FIELD_DEFAULT_VALUE = 7; // FieldDescriptorProto.default_value
const FIELD_OPTIONS = 8; // FieldDescriptorProto.options
const FIELD_ONEOF_INDEX = 9; // FieldDescriptorProto.oneof_index
const FIELD_JSON_NAME = 10; // FieldDescriptorProto.json_name
const FIELD_PROTO3_OPTIONAL = 17; // FieldDescriptorProto.proto3_optional
const FOPT_PACKED = 2; // FieldOptions.packed

// FieldDescriptorProto.Type values.
const TYPE_GROUP = 10;
const TYPE_MESSAGE = 11;
const TYPE_ENUM = 14;
// FieldDescriptorProto.Label values.
const LABEL_REQUIRED = 2;
const LABEL_REPEATED = 3;
// Edition.EDITION_PROTO3 value.
const EDITION_PROTO3 = 999;

/// Parse `bytes` (a serialized `FileDescriptorProto`) at comptime and return the
/// metadata for the message addressed by `path`.
///
/// `path` is an index-only tuple: `path[0]` selects the top-level message
/// (`message_type`), and each further element selects a `nested_type`. Indices
/// count only real messages — synthetic map-entry messages are skipped, matching
/// the code generator's message walk. So `.{2}` is the 3rd top-level message and
/// `.{0, 1}` is `message[0]`'s 2nd (non-map-entry) nested message.
pub fn read_message_metadata(comptime bytes: []const u8, comptime path: anytype) MessageMetadata {
    @setEvalBranchQuota(100_000_000);
    const is_proto3 = fileIsProto3(bytes);
    const msg_bytes = navigateToMessage(bytes, path);
    return parseMessage(msg_bytes, is_proto3);
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
        else => @compileError("read_message_metadata: unexpected wire type in descriptor bytes"),
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
    if (getVarint(file_bytes, FILE_EDITION)) |ed| return ed == EDITION_PROTO3;
    if (getBytes(file_bytes, FILE_SYNTAX)) |syntax| return std.mem.eql(u8, syntax, "proto3");
    return false;
}

fn isMapEntry(comptime msg_bytes: []const u8) bool {
    const opts = getBytes(msg_bytes, MSG_OPTIONS) orelse return false;
    return (getVarint(opts, MSGOPT_MAP_ENTRY) orelse 0) != 0;
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
    @compileError("read_message_metadata: message path index out of range");
}

fn navigateToMessage(comptime file_bytes: []const u8, comptime path: anytype) []const u8 {
    var cur: []const u8 = file_bytes;
    comptime var depth: usize = 0;
    inline for (path) |idx| {
        const field_no: u32 = if (depth == 0) FILE_MESSAGE_TYPE else MSG_NESTED_TYPE;
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
    const name = getBytes(fb, FIELD_NAME) orelse @compileError("descriptor field missing name");
    const opts = getBytes(fb, FIELD_OPTIONS);
    return .{
        .name = name,
        .number = @intCast(getVarint(fb, FIELD_NUMBER) orelse @compileError("descriptor field missing number")),
        .json_name = getBytes(fb, FIELD_JSON_NAME) orelse @compileError("descriptor field missing json_name"),
        .label = getVarint(fb, FIELD_LABEL) orelse @compileError("descriptor field missing label"),
        .type = getVarint(fb, FIELD_TYPE) orelse @compileError("descriptor field missing type"),
        .type_name = getBytes(fb, FIELD_TYPE_NAME),
        .default_value = getBytes(fb, FIELD_DEFAULT_VALUE),
        .oneof_index = if (getVarint(fb, FIELD_ONEOF_INDEX)) |o| @intCast(o) else null,
        .proto3_optional = (getVarint(fb, FIELD_PROTO3_OPTIONAL) orelse 0) != 0,
        .packed_opt = if (opts) |o| (if (getVarint(o, FOPT_PACKED)) |p| (p != 0) else null) else null,
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
    if (fi.label == LABEL_REQUIRED) return .legacy_required;
    if (fi.label == LABEL_REPEATED) return .implicit;
    if (fi.oneof_index != null) return .explicit;
    if (fi.type == TYPE_MESSAGE or fi.type == TYPE_GROUP) return .explicit;
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
    if (fi.type == TYPE_MESSAGE or fi.type == TYPE_GROUP) return .{ .message = {} };
    if (fi.type == TYPE_ENUM) return .{ .enum_type = {} };
    @compileError("read_message_metadata: invalid field element type");
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
    for (collectBytes(msg_bytes, MSG_NESTED_TYPE)) |nb| {
        const nm = getBytes(nb, FIELD_NAME) orelse continue;
        if (std.mem.eql(u8, nm, target) and isMapEntry(nb)) return nb;
    }
    return null;
}

const MapKV = struct { key: ScalarType, value: FieldMetadataElementType };

fn mapKeyValue(comptime entry: []const u8) MapKV {
    var key: ?ScalarType = null;
    var value: ?FieldMetadataElementType = null;
    for (collectBytes(entry, MSG_FIELD)) |fb| {
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
    const repeated = fi.label == LABEL_REPEATED;

    if (repeated and (fi.type == TYPE_MESSAGE or fi.type == TYPE_GROUP)) {
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

    if (fi.type == TYPE_MESSAGE or fi.type == TYPE_GROUP) {
        return .{ .message_field = .{ .presence = computePresence(fi, is_proto3) } };
    }
    if (fi.type == TYPE_ENUM) {
        return .{ .enum_field = .{
            .presence = computePresence(fi, is_proto3),
            .default_value = enumDefault(fi),
        } };
    }
    const sc = scalarFromType(fi.type) orelse @compileError("read_message_metadata: invalid scalar type");
    return .{ .scalar = .{
        .scalar = sc,
        .presence = computePresence(fi, is_proto3),
        .default_value = parseDefaultValue(sc, fi.default_value),
    } };
}

/// Kind for a oneof variant. Oneof variants are always singular and codegen omits
/// presence (and scalar defaults) for them.
fn buildOneofKind(comptime fi: FieldInfo) FieldMetadataKind {
    if (fi.type == TYPE_MESSAGE or fi.type == TYPE_GROUP) return .{ .message_field = .{} };
    if (fi.type == TYPE_ENUM) return .{ .enum_field = .{ .default_value = enumDefault(fi) } };
    const sc = scalarFromType(fi.type) orelse @compileError("read_message_metadata: invalid oneof scalar type");
    return .{ .scalar = .{ .scalar = sc } };
}

fn parseMessage(comptime msg_bytes: []const u8, comptime is_proto3: bool) MessageMetadata {
    const field_protos = collectBytes(msg_bytes, MSG_FIELD);
    const oneof_protos = collectBytes(msg_bytes, MSG_ONEOF_DECL);

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
                .json_name = fi.json_name,
                .kind = buildOneofKind(fi),
            }};
        }
        field_index += 1;
    }

    return .{ .fields = out };
}
