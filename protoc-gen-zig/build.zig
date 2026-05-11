const std = @import("std");
const protobuf = @import("protobuf");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const protobuf_dep = b.dependency("protobuf", .{ .target = target, .optimize = optimize });
    const protobuf_mod = protobuf_dep.module("protobuf");

    const protobuf_version = b.option(
        []const u8,
        "protobuf_version",
        "Upstream protobuf version (e.g. 33.2)",
    ) orelse @panic("missing -Dprotobuf_version");

    const protoc_include = b.pathFromRoot(
        b.fmt("../.cache/upstream-protobuf/{s}/protoc/include", .{protobuf_version}),
    );

    const gen_step = protobuf.RunProtocStep.create(protobuf_dep.builder, target, .{
        .destination_directory = b.path("src/gen"),
        .source_files = &.{
            b.pathJoin(&.{ protoc_include, "google/protobuf/descriptor.proto" }),
            b.pathJoin(&.{ protoc_include, "google/protobuf/compiler/plugin.proto" }),
        },
        .include_directories = &.{protoc_include},
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("protobuf", protobuf_mod);

    const exe = b.addExecutable(.{
        .name = "protoc-gen-zig",
        .root_module = exe_mod,
    });
    exe.step.dependOn(&gen_step.step);

    b.installArtifact(exe);

    const test_step = b.step("test", "Run unit tests");
    _ = test_step;
}
