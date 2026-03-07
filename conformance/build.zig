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
        // test_messages_proto3.proto uses allow_alias enums and
        // test_messages_proto2.proto uses group fields, both unsupported by
        // zig-protobuf's generator. Only generate the conformance harness proto;
        // payload tests are skipped at runtime.
        .source_files = &.{
            b.pathJoin(&.{ cache_include, "conformance/conformance.proto" }),
        },
        .include_directories = &.{cache_include},
    });

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
    exe.step.dependOn(&gen_step.step);

    b.installArtifact(exe);
}
