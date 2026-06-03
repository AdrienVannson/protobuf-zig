// FULLY AI GENERATED WITHOUT REVIEW
// TODO: rewrite properly

const std = @import("std");
const descriptor = @import("protobuf").wkt.descriptor;
const protobuf = @import("protobuf");

const FieldType = descriptor.FieldDescriptorProto.Type;

const SupportedEdition = protobuf.SupportedEdition;

/// Owns a fully-linked DescFile graph. Call deinit() to free everything at once.
pub const OwnedDescFile = struct {
    arena: std.heap.ArenaAllocator,
    /// Pointer into the arena; stable for the lifetime of this owner.
    file: *const protobuf.DescFile,

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
    }
};

const Ctx = struct {
    alloc: std.mem.Allocator,
    /// FQN → mutable arena node (const cast OK; we own the arena).
    msg_index: std.StringHashMap(*protobuf.DescMessage),
    enum_index: std.StringHashMap(*protobuf.DescEnum),
    /// Synthetic map-entry messages excluded from nested_messages.
    map_entries: std.AutoHashMap(*protobuf.DescMessage, void),
    is_proto3: bool,
};

/// Convert a parsed FileDescriptorProto into a fully-linked DescFile graph.
///
/// `deps` maps each import path from proto.dependency to an already-built
/// *const DescFile. Convert imported files first (topological order).
/// Dep values are referenced by pointer and must outlive the returned owner.
pub fn descFileFromProto(
    proto: *const descriptor.FileDescriptorProto,
    deps: *const std.StringHashMap(*const protobuf.DescFile),
    allocator: std.mem.Allocator,
) error{ OutOfMemory, MissingDependency, UnresolvedTypeName, InvalidDescriptor }!OwnedDescFile {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const alloc = arena.allocator();

    const edition: SupportedEdition = blk: {
        if (proto.edition) |ed| break :blk switch (ed) {
            .EDITION_PROTO3 => .edition_proto3,
            .EDITION_2023 => .edition_2023,
            .EDITION_2024 => .edition_2024,
            else => .edition_proto2,
        };
        if (proto.syntax) |s| if (std.mem.eql(u8, s, "proto3")) break :blk .edition_proto3;
        break :blk .edition_proto2;
    };

    var ctx: Ctx = .{
        .alloc = alloc,
        .msg_index = std.StringHashMap(*protobuf.DescMessage).init(alloc),
        .enum_index = std.StringHashMap(*protobuf.DescEnum).init(alloc),
        .map_entries = std.AutoHashMap(*protobuf.DescMessage, void).init(alloc),
        .is_proto3 = edition == .edition_proto3,
    };

    // Seed indices from deps so cross-file type_name refs resolve.
    var dep_it = deps.valueIterator();
    while (dep_it.next()) |dp| {
        try seedMsgIndex(dp.*, &ctx.msg_index);
        try seedEnumIndex(dp.*, &ctx.enum_index);
    }

    // DescFile node — stable arena address used as back-pointer by all child nodes.
    const file_node: *protobuf.DescFile = try alloc.create(protobuf.DescFile);

    // Dependency pointer slice.
    const dep_slice = try alloc.alloc(*const protobuf.DescFile, proto.dependency.items.len);
    for (proto.dependency.items, dep_slice) |dep_name, *out|
        out.* = deps.get(dep_name) orelse return error.MissingDependency;

    const pkg = proto.package;

    // ---- Pass 1: allocate all Desc* nodes, populate FQN indices ----
    const top_enums = try p1Enums(&ctx, proto.enum_type.items, file_node, null, pkg);
    const top_messages = try p1Messages(&ctx, proto.message_type.items, file_node, null, pkg);
    const top_extensions = try p1Extensions(&ctx, proto.extension.items, file_node, null);

    file_node.* = .{
        .edition = edition,
        .name = try alloc.dupe(u8, proto.name orelse return error.InvalidDescriptor),
        .dependencies = dep_slice,
        .enums = top_enums,
        .messages = top_messages,
        .extensions = top_extensions,
        .deprecated = if (proto.options) |o| o.deprecated orelse false else false,
    };

    // ---- Pass 2: fill cross-references (depth-first: nested before parent) ----
    try p2Enums(&ctx, @constCast(top_enums));
    try p2Messages(&ctx, proto.message_type.items, pkg);

    return .{ .arena = arena, .file = file_node };
}

// =============================================================================
// Pass 1 — allocate nodes and register in FQN indices
// =============================================================================

fn buildFqn(alloc: std.mem.Allocator, scope: ?[]const u8, name: []const u8) ![]u8 {
    if (scope) |s| if (s.len > 0) return std.fmt.allocPrint(alloc, "{s}.{s}", .{ s, name });
    return alloc.dupe(u8, name);
}

fn isMapEntryProto(mp: *const descriptor.DescriptorProto) bool {
    return if (mp.options) |o| o.map_entry orelse false else false;
}

fn isOneofSynthetic(mp: *const descriptor.DescriptorProto, oneof_idx: i32) bool {
    for (mp.field.items) |fp| {
        if (fp.oneof_index != oneof_idx) continue;
        if (fp.proto3_optional != true) return false;
    }
    return true;
}

fn p1Enums(
    ctx: *Ctx,
    protos: []*descriptor.EnumDescriptorProto,
    file: *protobuf.DescFile,
    parent: ?*protobuf.DescMessage,
    scope: ?[]const u8,
) ![]protobuf.DescEnum {
    const out = try ctx.alloc.alloc(protobuf.DescEnum, protos.len);
    for (protos, out) |ep, *de| {
        const name = ep.name orelse return error.InvalidDescriptor;
        const full_name = try buildFqn(ctx.alloc, scope, name);
        de.* = .{
            .fully_qualified_proto_name = full_name,
            .local_name = try ctx.alloc.dupe(u8, name),
            .file = file,
            .parent = parent,
            .closed = !ctx.is_proto3,
            .values = try p1EnumValues(ctx, ep.value.items),
            .value = .{},
            .shared_prefix = null,
            .deprecated = if (ep.options) |o| o.deprecated orelse false else false,
        };
        try ctx.enum_index.put(full_name, de);
    }
    return out;
}

fn p1EnumValues(ctx: *Ctx, protos: []*descriptor.EnumValueDescriptorProto) ![]protobuf.DescEnumValue {
    const out = try ctx.alloc.alloc(protobuf.DescEnumValue, protos.len);
    for (protos, out) |vp, *dv| {
        const name = vp.name orelse return error.InvalidDescriptor;
        dv.* = .{
            .proto_name = try ctx.alloc.dupe(u8, name),
            .local_name = try ctx.alloc.dupe(u8, name),
            .number = vp.number orelse return error.InvalidDescriptor,
            .deprecated = if (vp.options) |o| o.deprecated orelse false else false,
        };
    }
    return out;
}

fn p1Messages(
    ctx: *Ctx,
    protos: []*descriptor.DescriptorProto,
    file: *protobuf.DescFile,
    parent: ?*protobuf.DescMessage,
    scope: ?[]const u8,
) ![]protobuf.DescMessage {
    var real_count: usize = 0;
    var map_count: usize = 0;
    for (protos) |mp| if (isMapEntryProto(mp)) {
        map_count += 1;
    } else {
        real_count += 1;
    };

    // Separate stable allocations so map entries don't appear in nested_messages.
    const real_msgs = try ctx.alloc.alloc(protobuf.DescMessage, real_count);
    const map_msgs = try ctx.alloc.alloc(protobuf.DescMessage, map_count);

    var ri: usize = 0;
    var mi: usize = 0;
    for (protos) |mp| {
        const is_map = isMapEntryProto(mp);
        // dm pointer is stable (arena-allocated slice element).
        const dm: *protobuf.DescMessage = if (is_map) &map_msgs[mi] else &real_msgs[ri];

        const name = mp.name orelse return error.InvalidDescriptor;
        const msg_fqn = try buildFqn(ctx.alloc, scope, name);

        // Recurse before writing dm.* so nested can safely reference dm as parent.
        const nested_enums = try p1Enums(ctx, mp.enum_type.items, file, dm, msg_fqn);
        const nested_messages = try p1Messages(ctx, mp.nested_type.items, file, dm, msg_fqn);
        const nested_extensions = try p1Extensions(ctx, mp.extension.items, file, dm);

        // Count real (non-synthetic) oneofs.
        var real_oneof_count: usize = 0;
        for (0..mp.oneof_decl.items.len) |oi| {
            if (!isOneofSynthetic(mp, @intCast(oi))) real_oneof_count += 1;
        }

        // Count members (each real oneof counts once; proto3_optional fields count once).
        const seen_oi = try ctx.alloc.alloc(bool, mp.oneof_decl.items.len);
        @memset(seen_oi, false);
        var members_count: usize = 0;
        for (mp.field.items) |fp| {
            if (fp.oneof_index) |oi| {
                if (fp.proto3_optional != true) {
                    const idx: usize = @intCast(oi);
                    if (!seen_oi[idx]) {
                        seen_oi[idx] = true;
                        members_count += 1;
                    }
                    continue;
                }
            }
            members_count += 1;
        }

        dm.* = .{
            .fully_qualified_proto_name = msg_fqn,
            .local_name = try ctx.alloc.dupe(u8, name),
            .file = file,
            .parent = parent,
            .fields = try ctx.alloc.alloc(protobuf.DescField, mp.field.items.len),
            .field = .{},
            .oneofs = try ctx.alloc.alloc(protobuf.DescOneof, real_oneof_count),
            .members = try ctx.alloc.alloc(protobuf.DescMessageMember, members_count),
            .nested_enums = nested_enums,
            .nested_messages = nested_messages,
            .nested_extensions = nested_extensions,
            .deprecated = if (mp.options) |o| o.deprecated orelse false else false,
        };

        try ctx.msg_index.put(msg_fqn, dm);
        if (is_map) {
            try ctx.map_entries.put(dm, {});
            mi += 1;
        } else ri += 1;
    }
    return real_msgs;
}

fn p1Extensions(
    ctx: *Ctx,
    protos: []*descriptor.FieldDescriptorProto,
    file: *protobuf.DescFile,
    parent: ?*protobuf.DescMessage,
) ![]protobuf.DescExtension {
    const out = try ctx.alloc.alloc(protobuf.DescExtension, protos.len);
    for (protos, out) |fp, *dx| {
        const name = fp.name orelse return error.InvalidDescriptor;
        // extendee and kind filled in pass 2 (extensions are uncommon; stub for now).
        dx.* = .{
            .name = try ctx.alloc.dupe(u8, name),
            .fully_qualified_proto_name = try ctx.alloc.dupe(u8, name),
            .file = file,
            .parent = parent,
            .extendee = undefined,
            .number = fp.number orelse return error.InvalidDescriptor,
            .json_name = if (fp.json_name) |jn| try ctx.alloc.dupe(u8, jn) else try ctx.alloc.dupe(u8, name),
            .deprecated = if (fp.options) |o| o.deprecated orelse false else false,
            .presence = .explicit,
            .kind = .{ .scalar = .{ .scalar = .bool, .default_value = null } },
        };
    }
    return out;
}

// =============================================================================
// Pass 2 — fill cross-references
// =============================================================================

fn p2Enums(ctx: *Ctx, enums: []protobuf.DescEnum) !void {
    for (enums) |*de| {
        try de.value.ensureTotalCapacity(ctx.alloc, @intCast(de.values.len));
        for (de.values, 0..) |v, i| {
            const r = de.value.getOrPutAssumeCapacity(v.number);
            if (!r.found_existing) r.value_ptr.* = i;
        }
    }
}

/// Depth-first: fill nested messages and enums before filling the current
/// message's fields, so map-entry fields are resolved when the parent needs them.
fn p2Messages(
    ctx: *Ctx,
    protos: []*descriptor.DescriptorProto,
    scope: ?[]const u8,
) !void {
    for (protos) |mp| {
        const name = mp.name orelse return error.InvalidDescriptor;
        const msg_fqn = try buildFqn(ctx.alloc, scope, name);
        const dm = ctx.msg_index.get(msg_fqn) orelse return error.InvalidDescriptor;

        // Recurse first.
        try p2Enums(ctx, @constCast(dm.nested_enums));
        try p2Messages(ctx, mp.nested_type.items, msg_fqn);

        try p2OneMessage(ctx, mp, dm);
    }
}

fn p2OneMessage(ctx: *Ctx, mp: *const descriptor.DescriptorProto, dm: *protobuf.DescMessage) !void {
    const alloc = ctx.alloc;

    // Build oneof_map: proto oneof_index → *DescOneof (null for synthetic oneofs).
    const oneof_map = try alloc.alloc(?*protobuf.DescOneof, mp.oneof_decl.items.len);
    var real_oi: usize = 0;
    for (mp.oneof_decl.items, 0..) |op, oi| {
        if (isOneofSynthetic(mp, @intCast(oi))) {
            oneof_map[oi] = null;
            continue;
        }
        const do: *protobuf.DescOneof = &@constCast(dm.oneofs)[real_oi];
        do.proto_name = try alloc.dupe(u8, op.name orelse return error.InvalidDescriptor);
        do.local_name = try alloc.dupe(u8, op.name orelse return error.InvalidDescriptor);
        do.parent = dm;
        do.fields = &.{};
        oneof_map[oi] = do;
        real_oi += 1;
    }

    // Size and allocate each oneof's fields slice.
    const oi_field_counts = try alloc.alloc(usize, mp.oneof_decl.items.len);
    @memset(oi_field_counts, 0);
    for (mp.field.items) |fp| {
        if (fp.oneof_index) |oi| {
            if (fp.proto3_optional != true)
                oi_field_counts[@intCast(oi)] += 1;
        }
    }
    for (0..mp.oneof_decl.items.len) |oi| {
        const do = oneof_map[oi] orelse continue;
        do.fields = try alloc.alloc(*const protobuf.DescField, oi_field_counts[oi]);
    }
    const oi_cursors = try alloc.alloc(usize, mp.oneof_decl.items.len);
    @memset(oi_cursors, 0);

    // field name → index map.
    try dm.field.ensureTotalCapacity(alloc, @intCast(mp.field.items.len));

    // Fill each DescField.
    for (mp.field.items, 0..) |fp, fi| {
        const df: *protobuf.DescField = &@constCast(dm.fields)[fi];
        const field_name = fp.name orelse return error.InvalidDescriptor;

        const oneof_ptr: ?*const protobuf.DescOneof = blk: {
            const oi = fp.oneof_index orelse break :blk null;
            if (fp.proto3_optional == true) break :blk null;
            break :blk oneof_map[@intCast(oi)];
        };

        df.* = .{
            .name = try alloc.dupe(u8, field_name),
            .local_name = try escapeZigKeyword(alloc, field_name),
            .parent = dm,
            .number = fp.number orelse return error.InvalidDescriptor,
            .json_name = if (fp.json_name) |jn|
                try alloc.dupe(u8, jn)
            else
                try toJsonName(alloc, field_name),
            .deprecated = if (fp.options) |o| o.deprecated orelse false else false,
            .presence = computePresence(fp, ctx.is_proto3),
            .kind = try buildFieldKind(ctx, fp, oneof_ptr),
        };

        dm.field.putAssumeCapacity(df.local_name, fi);

        if (fp.oneof_index) |oi| if (fp.proto3_optional != true) {
            if (oneof_map[@intCast(oi)]) |do| {
                const cur = &oi_cursors[@intCast(oi)];
                @constCast(do.fields)[cur.*] = df;
                cur.* += 1;
            }
        };
    }

    // Build members slice in field-declaration order.
    const seen_oi = try alloc.alloc(bool, mp.oneof_decl.items.len);
    @memset(seen_oi, false);
    var mc: usize = 0;
    for (mp.field.items, 0..) |fp, fi| {
        if (fp.oneof_index) |oi| if (fp.proto3_optional != true) if (oneof_map[@intCast(oi)]) |do| {
            if (!seen_oi[@intCast(oi)]) {
                seen_oi[@intCast(oi)] = true;
                @constCast(dm.members)[mc] = .{ .oneof = do };
                mc += 1;
            }
            continue;
        };
        @constCast(dm.members)[mc] = .{ .field = &dm.fields[fi] };
        mc += 1;
    }
    std.debug.assert(mc == dm.members.len);
}

fn buildFieldKind(
    ctx: *Ctx,
    fp: *const descriptor.FieldDescriptorProto,
    oneof_ptr: ?*const protobuf.DescOneof,
) !protobuf.DescFieldKind {
    const t = fp.type orelse return error.InvalidDescriptor;
    const label = fp.label orelse return error.InvalidDescriptor;
    const repeated = label == .LABEL_REPEATED;

    // Map field: repeated message whose target is a map-entry synthetic message.
    if (repeated and (t == .TYPE_MESSAGE or t == .TYPE_GROUP)) {
        if (fp.type_name) |tn| {
            const stripped = if (tn[0] == '.') tn[1..] else tn;
            if (ctx.msg_index.get(stripped)) |target| {
                if (ctx.map_entries.contains(target)) {
                    // Map entry fields are filled (depth-first ensures this).
                    const key_f = findFieldByNumber(target, 1) orelse return error.InvalidDescriptor;
                    const val_f = findFieldByNumber(target, 2) orelse return error.InvalidDescriptor;
                    const key_sc = kindToScalar(key_f.kind) orelse return error.InvalidDescriptor;
                    const val_el = kindToElement(val_f.kind) orelse return error.InvalidDescriptor;
                    return .{ .map = .{ .key = key_sc, .value = val_el } };
                }
            }
        }
    }

    if (repeated) {
        return .{ .list = .{
            .element = try protoToElement(ctx, fp),
            .is_packed = computePacked(fp, t, ctx.is_proto3),
            .delimited_encoding = t == .TYPE_GROUP,
        } };
    }

    // Singular.
    switch (t) {
        .TYPE_GROUP, .TYPE_MESSAGE => {
            const tn = fp.type_name orelse return error.InvalidDescriptor;
            const stripped = if (tn[0] == '.') tn[1..] else tn;
            return .{ .message_field = .{
                .oneof = oneof_ptr,
                .message = ctx.msg_index.get(stripped) orelse return error.UnresolvedTypeName,
                .delimited_encoding = t == .TYPE_GROUP,
            } };
        },
        .TYPE_ENUM => {
            const tn = fp.type_name orelse return error.InvalidDescriptor;
            const stripped = if (tn[0] == '.') tn[1..] else tn;
            return .{ .enum_field = .{
                .oneof = oneof_ptr,
                .enum_type = ctx.enum_index.get(stripped) orelse return error.UnresolvedTypeName,
                .default_value = if (fp.default_value) |dv| std.fmt.parseInt(i32, dv, 10) catch null else null,
            } };
        },
        else => {
            const sc = protoTypeToScalar(t) orelse return error.InvalidDescriptor;
            return .{ .scalar = .{
                .oneof = oneof_ptr,
                .scalar = sc,
                .default_value = try parseDefaultValue(ctx.alloc, sc, fp.default_value),
            } };
        },
    }
}

fn protoToElement(ctx: *Ctx, fp: *const descriptor.FieldDescriptorProto) !protobuf.DescElementType {
    const t = fp.type orelse return error.InvalidDescriptor;
    if (protoTypeToScalar(t)) |s| return .{ .scalar = s };
    const tn = fp.type_name orelse return error.InvalidDescriptor;
    const stripped = if (tn[0] == '.') tn[1..] else tn;
    if (t == .TYPE_MESSAGE or t == .TYPE_GROUP)
        return .{ .message = ctx.msg_index.get(stripped) orelse return error.UnresolvedTypeName };
    if (t == .TYPE_ENUM)
        return .{ .enum_type = ctx.enum_index.get(stripped) orelse return error.UnresolvedTypeName };
    return error.InvalidDescriptor;
}

fn protoTypeToScalar(t: FieldType) ?protobuf.ScalarType {
    return switch (t) {
        .TYPE_INT32 => .int32,
        .TYPE_INT64 => .int64,
        .TYPE_UINT32 => .uint32,
        .TYPE_UINT64 => .uint64,
        .TYPE_SINT32 => .sint32,
        .TYPE_SINT64 => .sint64,
        .TYPE_FIXED32 => .fixed32,
        .TYPE_FIXED64 => .fixed64,
        .TYPE_SFIXED32 => .sfixed32,
        .TYPE_SFIXED64 => .sfixed64,
        .TYPE_BOOL => .bool,
        .TYPE_FLOAT => .float,
        .TYPE_DOUBLE => .double,
        .TYPE_STRING => .string,
        .TYPE_BYTES => .bytes,
        else => null,
    };
}

fn kindToScalar(kind: protobuf.DescFieldKind) ?protobuf.ScalarType {
    return if (kind == .scalar) kind.scalar.scalar else null;
}

fn kindToElement(kind: protobuf.DescFieldKind) ?protobuf.DescElementType {
    return switch (kind) {
        .scalar => |s| .{ .scalar = s.scalar },
        .message_field => |m| .{ .message = m.message },
        .enum_field => |e| .{ .enum_type = e.enum_type },
        else => null,
    };
}

fn findFieldByNumber(msg: *const protobuf.DescMessage, number: i32) ?*const protobuf.DescField {
    for (msg.fields) |*f| if (f.number == number) return f;
    return null;
}

fn computePresence(fp: *const descriptor.FieldDescriptorProto, is_proto3: bool) protobuf.SupportedFieldPresence {
    const label = fp.label orelse return .implicit;
    if (label == .LABEL_REQUIRED) return .legacy_required;
    if (label == .LABEL_REPEATED) return .implicit;
    if (fp.oneof_index != null) return .explicit;
    if (!is_proto3) return .explicit;
    return .implicit;
}

fn computePacked(fp: *const descriptor.FieldDescriptorProto, t: FieldType, is_proto3: bool) bool {
    if (fp.options) |o| if (o.@"packed") |p| return p;
    if (!is_proto3) return false;
    return switch (t) {
        .TYPE_DOUBLE, .TYPE_FLOAT, .TYPE_INT64, .TYPE_UINT64, .TYPE_INT32, .TYPE_FIXED64, .TYPE_FIXED32, .TYPE_BOOL, .TYPE_UINT32, .TYPE_SFIXED32, .TYPE_SFIXED64, .TYPE_SINT32, .TYPE_SINT64, .TYPE_ENUM => true,
        else => false,
    };
}

fn parseDefaultValue(alloc: std.mem.Allocator, sc: protobuf.ScalarType, raw: ?[]const u8) !?protobuf.DefaultValue {
    const s = raw orelse return null;
    if (s.len == 0) return null;
    return switch (sc) {
        .bool => .{ .boolean = std.mem.eql(u8, s, "true") },
        .int32, .int64, .sint32, .sint64, .sfixed32, .sfixed64 => .{ .integer = std.fmt.parseInt(i64, s, 10) catch return null },
        .uint32, .uint64, .fixed32, .fixed64 => .{ .integer = @bitCast(std.fmt.parseInt(u64, s, 10) catch return null) },
        .float, .double => .{ .float = std.fmt.parseFloat(f64, s) catch return null },
        .string => .{ .string = try alloc.dupe(u8, s) },
        .bytes => .{ .bytes = try alloc.dupe(u8, s) },
    };
}

fn toJsonName(alloc: std.mem.Allocator, snake: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    var up = false;
    for (snake) |c| {
        if (c == '_') {
            up = true;
            continue;
        }
        try out.append(alloc, if (up) std.ascii.toUpper(c) else c);
        up = false;
    }
    return out.toOwnedSlice(alloc);
}

fn escapeZigKeyword(alloc: std.mem.Allocator, name: []const u8) ![]u8 {
    if (std.zig.Token.keywords.has(name))
        return std.fmt.allocPrint(alloc, "@\"{s}\"", .{name});
    return alloc.dupe(u8, name);
}

// =============================================================================
// Dep index seeding
// =============================================================================

fn seedMsgIndex(file: *const protobuf.DescFile, idx: *std.StringHashMap(*protobuf.DescMessage)) !void {
    for (file.messages) |*m| try seedMsgMsg(m, idx);
}
fn seedMsgMsg(m: *const protobuf.DescMessage, idx: *std.StringHashMap(*protobuf.DescMessage)) !void {
    try idx.put(m.fully_qualified_proto_name, @constCast(m));
    for (m.nested_messages) |*nm| try seedMsgMsg(nm, idx);
}

fn seedEnumIndex(file: *const protobuf.DescFile, idx: *std.StringHashMap(*protobuf.DescEnum)) !void {
    for (file.enums) |*e| try idx.put(e.fully_qualified_proto_name, @constCast(e));
    for (file.messages) |*m| try seedEnumMsg(m, idx);
}
fn seedEnumMsg(m: *const protobuf.DescMessage, idx: *std.StringHashMap(*protobuf.DescEnum)) !void {
    for (m.nested_enums) |*e| try idx.put(e.fully_qualified_proto_name, @constCast(e));
    for (m.nested_messages) |*nm| try seedEnumMsg(nm, idx);
}

// =============================================================================
// Tests
// =============================================================================

const testing = std.testing;

fn noDeps(alloc: std.mem.Allocator) std.StringHashMap(*const protobuf.DescFile) {
    return std.StringHashMap(*const protobuf.DescFile).init(alloc);
}

test "trivial proto3 file — no leaks" {
    const alloc = testing.allocator;
    const proto: descriptor.FileDescriptorProto = .{ .name = "empty.proto", .syntax = "proto3" };
    var deps = noDeps(alloc);
    defer deps.deinit();

    var owned = try descFileFromProto(&proto, &deps, alloc);
    defer owned.deinit();

    try testing.expectEqualStrings("empty.proto", owned.file.name);
    try testing.expectEqual(SupportedEdition.edition_proto3, owned.file.edition);
    try testing.expectEqual(@as(usize, 0), owned.file.messages.len);
    try testing.expectEqual(@as(usize, 0), owned.file.enums.len);
    try testing.expectEqual(@as(usize, 0), owned.file.extensions.len);
    try testing.expectEqual(@as(usize, 0), owned.file.dependencies.len);
}

test "proto2 syntax yields edition_proto2" {
    const alloc = testing.allocator;
    const proto: descriptor.FileDescriptorProto = .{ .name = "p2.proto", .syntax = "proto2" };
    var deps = noDeps(alloc);
    defer deps.deinit();
    var owned = try descFileFromProto(&proto, &deps, alloc);
    defer owned.deinit();
    try testing.expectEqual(SupportedEdition.edition_proto2, owned.file.edition);
}

test "top-level enum with value map" {
    const alloc = testing.allocator;

    // Use an arena for input proto construction so string literals are not freed.
    var input_arena = std.heap.ArenaAllocator.init(alloc);
    defer input_arena.deinit();
    const pa = input_arena.allocator();

    const red = try pa.create(descriptor.EnumValueDescriptorProto);
    red.* = .{ .name = "RED", .number = 0 };
    const green = try pa.create(descriptor.EnumValueDescriptorProto);
    green.* = .{ .name = "GREEN", .number = 1 };

    const ep = try pa.create(descriptor.EnumDescriptorProto);
    ep.* = .{ .name = "Color" };
    try ep.value.append(pa, red);
    try ep.value.append(pa, green);

    var proto: descriptor.FileDescriptorProto = .{ .name = "e.proto", .syntax = "proto3" };
    try proto.enum_type.append(pa, ep);

    var deps = noDeps(alloc);
    defer deps.deinit();
    var owned = try descFileFromProto(&proto, &deps, alloc);
    defer owned.deinit();

    const e = &owned.file.enums[0];
    try testing.expectEqualStrings("Color", e.local_name);
    try testing.expectEqual(owned.file, e.file);
    try testing.expect(e.parent == null);
    try testing.expectEqual(@as(usize, 0), e.value.get(0).?);
    try testing.expectEqual(@as(usize, 1), e.value.get(1).?);
}

test "enum in package gets qualified name" {
    const alloc = testing.allocator;

    var input_arena = std.heap.ArenaAllocator.init(alloc);
    defer input_arena.deinit();
    const pa = input_arena.allocator();

    const v = try pa.create(descriptor.EnumValueDescriptorProto);
    v.* = .{ .name = "V", .number = 0 };

    const ep = try pa.create(descriptor.EnumDescriptorProto);
    ep.* = .{ .name = "E" };
    try ep.value.append(pa, v);

    var proto: descriptor.FileDescriptorProto = .{
        .name = "pkg.proto",
        .package = "mypkg",
        .syntax = "proto3",
    };
    try proto.enum_type.append(pa, ep);

    var deps = noDeps(alloc);
    defer deps.deinit();
    var owned = try descFileFromProto(&proto, &deps, alloc);
    defer owned.deinit();

    try testing.expectEqualStrings("mypkg.E", owned.file.enums[0].fully_qualified_proto_name);
}

test "missing dependency returns MissingDependency" {
    const alloc = testing.allocator;

    var input_arena = std.heap.ArenaAllocator.init(alloc);
    defer input_arena.deinit();
    const pa = input_arena.allocator();

    var proto: descriptor.FileDescriptorProto = .{ .name = "a.proto" };
    try proto.dependency.append(pa, "b.proto");

    var deps = noDeps(alloc);
    defer deps.deinit();
    try testing.expectError(error.MissingDependency, descFileFromProto(&proto, &deps, alloc));
}

test "message with scalar field — back-pointers and field map" {
    const alloc = testing.allocator;

    var input_arena = std.heap.ArenaAllocator.init(alloc);
    defer input_arena.deinit();
    const pa = input_arena.allocator();

    const field = try pa.create(descriptor.FieldDescriptorProto);
    field.* = .{
        .name = "id",
        .number = 1,
        .label = .LABEL_OPTIONAL,
        .type = .TYPE_INT32,
        .json_name = "id",
    };

    const msg = try pa.create(descriptor.DescriptorProto);
    msg.* = .{ .name = "Msg" };
    try msg.field.append(pa, field);

    var proto: descriptor.FileDescriptorProto = .{ .name = "msg.proto", .syntax = "proto3" };
    try proto.message_type.append(pa, msg);

    var deps = noDeps(alloc);
    defer deps.deinit();
    var owned = try descFileFromProto(&proto, &deps, alloc);
    defer owned.deinit();

    const dm = &owned.file.messages[0];
    try testing.expectEqualStrings("Msg", dm.local_name);
    try testing.expectEqual(owned.file, dm.file);
    try testing.expect(dm.parent == null);
    try testing.expectEqual(@as(usize, 1), dm.fields.len);

    const df = &dm.fields[0];
    try testing.expectEqualStrings("id", df.name);
    try testing.expectEqual(dm, df.parent);
    try testing.expectEqual(@as(i32, 1), df.number);
    try testing.expect(df.kind == .scalar);
    try testing.expectEqual(protobuf.ScalarType.int32, df.kind.scalar.scalar);
    try testing.expectEqual(protobuf.SupportedFieldPresence.implicit, df.presence);
    try testing.expectEqual(@as(usize, 0), dm.field.get("id").?);

    try testing.expectEqual(@as(usize, 1), dm.members.len);
    try testing.expect(dm.members[0] == .field);
}

test "oneof group — oneofs slice, field kinds, members" {
    const alloc = testing.allocator;

    var input_arena = std.heap.ArenaAllocator.init(alloc);
    defer input_arena.deinit();
    const pa = input_arena.allocator();

    const od = try pa.create(descriptor.OneofDescriptorProto);
    od.* = .{ .name = "choice" };

    const num = try pa.create(descriptor.FieldDescriptorProto);
    num.* = .{
        .name = "num",
        .number = 1,
        .label = .LABEL_OPTIONAL,
        .type = .TYPE_INT32,
        .json_name = "num",
        .oneof_index = 0,
    };

    const str = try pa.create(descriptor.FieldDescriptorProto);
    str.* = .{
        .name = "str",
        .number = 2,
        .label = .LABEL_OPTIONAL,
        .type = .TYPE_STRING,
        .json_name = "str",
        .oneof_index = 0,
    };

    const msg = try pa.create(descriptor.DescriptorProto);
    msg.* = .{ .name = "Msg" };
    try msg.oneof_decl.append(pa, od);
    try msg.field.append(pa, num);
    try msg.field.append(pa, str);

    var proto: descriptor.FileDescriptorProto = .{ .name = "oo.proto", .syntax = "proto3" };
    try proto.message_type.append(pa, msg);

    var deps = noDeps(alloc);
    defer deps.deinit();
    var owned = try descFileFromProto(&proto, &deps, alloc);
    defer owned.deinit();

    const dm = &owned.file.messages[0];
    try testing.expectEqual(@as(usize, 1), dm.oneofs.len);
    const do = &dm.oneofs[0];
    try testing.expectEqualStrings("choice", do.proto_name);
    try testing.expectEqual(dm, do.parent);
    try testing.expectEqual(@as(usize, 2), do.fields.len);
    try testing.expectEqual(do, dm.fields[0].kind.scalar.oneof.?);
    try testing.expectEqual(do, dm.fields[1].kind.scalar.oneof.?);
    try testing.expectEqual(protobuf.SupportedFieldPresence.explicit, dm.fields[0].presence);

    // Members: one oneof entry, not two field entries.
    try testing.expectEqual(@as(usize, 1), dm.members.len);
    try testing.expect(dm.members[0] == .oneof);
    try testing.expectEqual(do, dm.members[0].oneof);
}

test "cross-file message reference via deps" {
    const alloc = testing.allocator;

    // Build b.proto with message B.
    var b_input_arena = std.heap.ArenaAllocator.init(alloc);
    defer b_input_arena.deinit();
    const bpa = b_input_arena.allocator();

    const b_x = try bpa.create(descriptor.FieldDescriptorProto);
    b_x.* = .{ .name = "x", .number = 1, .label = .LABEL_OPTIONAL, .type = .TYPE_INT32, .json_name = "x" };
    const b_msg = try bpa.create(descriptor.DescriptorProto);
    b_msg.* = .{ .name = "B" };
    try b_msg.field.append(bpa, b_x);
    var b_proto: descriptor.FileDescriptorProto = .{ .name = "b.proto", .syntax = "proto3" };
    try b_proto.message_type.append(bpa, b_msg);

    var b_deps = noDeps(alloc);
    defer b_deps.deinit();
    var b_owned = try descFileFromProto(&b_proto, &b_deps, alloc);
    defer b_owned.deinit();

    // Build a.proto referencing B.
    var a_input_arena = std.heap.ArenaAllocator.init(alloc);
    defer a_input_arena.deinit();
    const apa = a_input_arena.allocator();

    const a_bf = try apa.create(descriptor.FieldDescriptorProto);
    a_bf.* = .{ .name = "b_field", .number = 1, .label = .LABEL_OPTIONAL, .type = .TYPE_MESSAGE, .type_name = ".B", .json_name = "bField" };
    const a_msg = try apa.create(descriptor.DescriptorProto);
    a_msg.* = .{ .name = "A" };
    try a_msg.field.append(apa, a_bf);
    var a_proto: descriptor.FileDescriptorProto = .{ .name = "a.proto", .syntax = "proto3" };
    try a_proto.message_type.append(apa, a_msg);
    try a_proto.dependency.append(apa, "b.proto");

    var a_deps = std.StringHashMap(*const protobuf.DescFile).init(alloc);
    defer a_deps.deinit();
    try a_deps.put("b.proto", b_owned.file);

    var a_owned = try descFileFromProto(&a_proto, &a_deps, alloc);
    defer a_owned.deinit();

    const a_dm = &a_owned.file.messages[0];
    const field_kind = a_dm.fields[0].kind;
    try testing.expect(field_kind == .message_field);
    // The resolved message should be B from b_owned.
    try testing.expectEqualStrings("B", field_kind.message_field.message.fully_qualified_proto_name);
}
