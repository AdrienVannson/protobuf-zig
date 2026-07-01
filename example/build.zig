const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const io = b.graph.io;

    const protobuf_dep = b.dependency("protobuf", .{
        .target = target,
        .optimize = optimize,
    });

    const run_step = b.step("run", "Build and run all examples");

    var examples_dir = try b.build_root.handle.openDir(io, "examples", .{ .iterate = true });
    defer examples_dir.close(io);

    var it = examples_dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;

        const name = entry.name[0 .. entry.name.len - ".zig".len];

        const exe_mod = b.createModule(.{
            .root_source_file = b.path(b.fmt("examples/{s}", .{entry.name})),
            .target = target,
            .optimize = optimize,
        });
        exe_mod.addImport("protobuf", protobuf_dep.module("protobuf"));
        exe_mod.addAnonymousImport("example_pb", .{
            .root_source_file = b.path("gen/example.pb.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "protobuf", .module = protobuf_dep.module("protobuf") },
            },
        });

        const exe = b.addExecutable(.{
            .name = name,
            .root_module = exe_mod,
        });
        b.installArtifact(exe);

        const example_run_step = b.step(b.fmt("run-{s}", .{name}), b.fmt("Run the {s} example", .{name}));
        example_run_step.dependOn(&b.addRunArtifact(exe).step);
        run_step.dependOn(example_run_step);
    }
}
