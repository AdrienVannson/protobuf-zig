const std = @import("std");
const protobuf = @import("protobuf");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const protobuf_dep = b.dependency("protobuf", .{
        .target = target,
        .optimize = optimize,
    });
    const protobuf_mod = protobuf_dep.module("protobuf");

    // Absolute path to the conformance proto include directory in our cache.
    // b.pathFromRoot resolves ".." properly via fs.path.resolve.
    const cache_include = b.pathFromRoot(
        "../.cache/upstream-protobuf/33.2/conformance/package/include",
    );

    const gen_step = protobuf.RunProtocStep.create(protobuf_dep.builder, target, .{
        .destination_directory = b.path("src/generated"),
        // test_messages_proto2.proto uses group fields, unsupported by
        // zig-protobuf's generator. Only generate conformance + proto3.
        .source_files = &.{
            b.pathJoin(&.{ cache_include, "conformance/conformance.proto" }),
            b.pathJoin(&.{ cache_include, "google/protobuf/test_messages_proto3.proto" }),
        },
        .include_directories = &.{cache_include},
    });

    // test_messages_proto3.proto contains AliasedEnum with allow_alias = true,
    // causing duplicate enum tag values that Zig rejects at compile time.
    // DeduplicateEnumsStep patches the generated file, keeping only the first
    // variant per numeric value.
    const dedup_step = DeduplicateEnumsStep.create(
        b,
        b.pathFromRoot("src/generated/protobuf_test_messages/proto3.pb.zig"),
    );
    dedup_step.step.dependOn(&gen_step.step);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("protobuf", protobuf_mod);

    const exe = b.addExecutable(.{
        .name = "conformance",
        .root_module = exe_mod,
    });
    exe.step.dependOn(&dedup_step.step);

    b.installArtifact(exe);
}

const DeduplicateEnumsStep = struct {
    step: std.Build.Step,
    file_path: []const u8,

    fn create(b: *std.Build, file_path: []const u8) *@This() {
        const self = b.allocator.create(@This()) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "deduplicate allow_alias enum values",
                .owner = b,
                .makeFn = make,
            }),
            .file_path = file_path,
        };
        return self;
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
        const self: *@This() = @fieldParentPtr("step", step);
        const b = step.owner;

        const file_contents = std.fs.cwd().readFileAlloc(
            b.allocator,
            self.file_path,
            10 * 1024 * 1024,
        ) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        defer b.allocator.free(file_contents);

        var output_lines: std.ArrayList([]const u8) = .{};
        defer output_lines.deinit(b.allocator);

        var seen_values = std.AutoHashMap(i64, void).init(b.allocator);
        defer seen_values.deinit();

        var in_enum = false;
        var changed = false;

        var iter = std.mem.splitScalar(u8, file_contents, '\n');
        while (iter.next()) |line| {
            if (!in_enum) {
                if (std.mem.indexOf(u8, line, "= enum(i32) {") != null) {
                    in_enum = true;
                    seen_values.clearRetainingCapacity();
                }
                try output_lines.append(b.allocator, line);
            } else {
                const trimmed = std.mem.trim(u8, line, " \t");

                if (std.mem.eql(u8, trimmed, "};")) {
                    in_enum = false;
                    try output_lines.append(b.allocator, line);
                    continue;
                }

                if (std.mem.eql(u8, trimmed, "_,")) {
                    try output_lines.append(b.allocator, line);
                    continue;
                }

                // Try to parse: IDENTIFIER = VALUE,
                if (std.mem.indexOf(u8, trimmed, " = ")) |eq_pos| {
                    const after_eq = trimmed[eq_pos + 3 ..];
                    if (after_eq.len > 0 and after_eq[after_eq.len - 1] == ',') {
                        const value_str = after_eq[0 .. after_eq.len - 1];
                        if (std.fmt.parseInt(i64, value_str, 10)) |value| {
                            if (seen_values.contains(value)) {
                                changed = true;
                                continue;
                            }
                            try seen_values.put(value, {});
                        } else |_| {}
                    }
                }

                try output_lines.append(b.allocator, line);
            }
        }

        // The generator emits `corecursive: ?TestAllTypesProto3 = null` inside
        // NestedMessage without a pointer, creating a size cycle Zig rejects.
        // Fix: add `*` to make it a pointer, matching how `recursive_message`
        // is already emitted at the top-level (`?*TestAllTypesProto3`).
        for (output_lines.items) |*line| {
            const needle = ": ?TestAllTypesProto3 = null,";
            if (std.mem.indexOf(u8, line.*, needle)) |pos| {
                var new_line: std.ArrayList(u8) = .{};
                try new_line.appendSlice(b.allocator, line.*[0 .. pos + 3]); // up to and including `?`
                try new_line.append(b.allocator, '*');
                try new_line.appendSlice(b.allocator, line.*[pos + 3 ..]);
                line.* = try new_line.toOwnedSlice(b.allocator);
                changed = true;
            }
        }

        if (!changed) return;

        var out: std.ArrayList(u8) = .{};
        defer out.deinit(b.allocator);
        for (output_lines.items, 0..) |line, i| {
            if (i > 0) try out.append(b.allocator, '\n');
            try out.appendSlice(b.allocator, line);
        }

        try std.fs.cwd().writeFile(.{ .sub_path = self.file_path, .data = out.items });
    }
};
