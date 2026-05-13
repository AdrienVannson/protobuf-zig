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

    const our_protobuf_dep = b.dependency("our_protobuf", .{
        .target = target,
        .optimize = optimize,
    });
    const our_protobuf_mod = our_protobuf_dep.module("protobuf");

    const protobuf_version = b.option(
        []const u8,
        "protobuf_version",
        "Upstream protobuf version (e.g. 33.2)",
    ) orelse @panic("missing -Dprotobuf_version");

    // Absolute path to the conformance proto include directory in our cache.
    // b.pathFromRoot resolves ".." properly via fs.path.resolve.
    const cache_include = b.pathFromRoot(
        b.fmt("../.cache/upstream-protobuf/{s}/conformance/package/include", .{protobuf_version}),
    );

    const gen_step = protobuf.RunProtocStep.create(protobuf_dep.builder, target, .{
        .destination_directory = b.path("src/generated_old_lib"),
        // test_messages_proto2.proto uses group fields, unsupported by
        // zig-protobuf's generator. Only generate conformance + proto3.
        .source_files = &.{
            b.pathJoin(&.{ cache_include, "conformance/conformance.proto" }),
        },
        .include_directories = &.{cache_include},
    });

    const gen_proto3_mod = b.createModule(.{
        .root_source_file = b.path("src/gen/google/protobuf/test_messages_proto3.pb.zig"),
        .target = target,
        .optimize = optimize,
    });
    gen_proto3_mod.addImport("protobuf", our_protobuf_mod);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("protobuf", protobuf_mod);
    exe_mod.addImport("our_protobuf", our_protobuf_mod);
    exe_mod.addImport("gen_proto3", gen_proto3_mod);

    const exe = b.addExecutable(.{
        .name = "conformance",
        .root_module = exe_mod,
    });
    exe.step.dependOn(&gen_step.step);

    b.installArtifact(exe);
}
