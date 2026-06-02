const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const protobuf_dep = b.dependency("protobuf", .{
        .target = target,
        .optimize = optimize,
    });
    const protobuf_mod = protobuf_dep.module("protobuf");

    const gen_conformance_mod = b.createModule(.{
        .root_source_file = b.path("src/gen/conformance/conformance.pb.zig"),
        .target = target,
        .optimize = optimize,
    });
    gen_conformance_mod.addImport("protobuf", protobuf_mod);

    const gen_proto3_mod = b.createModule(.{
        .root_source_file = b.path("src/gen/google/protobuf/test_messages_proto3.pb.zig"),
        .target = target,
        .optimize = optimize,
    });
    gen_proto3_mod.addImport("protobuf", protobuf_mod);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("protobuf", protobuf_mod);
    exe_mod.addImport("gen_conformance", gen_conformance_mod);
    exe_mod.addImport("gen_proto3", gen_proto3_mod);

    const exe = b.addExecutable(.{
        .name = "conformance",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);
}
