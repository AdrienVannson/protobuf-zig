const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const our_protobuf_dep = b.dependency("our_protobuf", .{ .target = target, .optimize = optimize });
    const our_protobuf_mod = our_protobuf_dep.module("protobuf");

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("protobuf", our_protobuf_mod);
    exe_mod.addImport("our_protobuf", our_protobuf_mod);

    const exe = b.addExecutable(.{
        .name = "protoc-gen-zig",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/generated_file.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("protobuf", our_protobuf_mod);
    test_mod.addImport("our_protobuf", our_protobuf_mod);

    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
