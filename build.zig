const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Runtime library
    const protobuf_mod = b.addModule("protobuf", .{
        .root_source_file = b.path("protobuf/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    protobuf_mod.addImport("protobuf", protobuf_mod);

    // Code generator
    const plugin_mod = b.createModule(.{
        .root_source_file = b.path("protoc-gen-zig/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    plugin_mod.addImport("protobuf", protobuf_mod);

    const plugin_exe = b.addExecutable(.{
        .name = "protoc-gen-zig",
        .root_module = plugin_mod,
    });
    b.installArtifact(plugin_exe);

    // Tests
    const protobuf_tests = b.addTest(.{ .root_module = protobuf_mod });

    const plugin_tests = b.addTest(.{ .root_module = plugin_mod });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(protobuf_tests).step);
    test_step.dependOn(&b.addRunArtifact(plugin_tests).step);

    // Docs
    const lib_for_docs = b.addLibrary(.{
        .name = "protobuf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("protobuf/src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib_for_docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Build documentation");
    docs_step.dependOn(&install_docs.step);
}
