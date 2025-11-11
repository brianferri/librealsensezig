const std = @import("std");
const linkLibRealsense = @import("build.librealsense.zig").linkLibRealSense;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const librealsensebindings = b.addTranslateC(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("bindings/librealsense.h"),
    });
    const librealsense = librealsensebindings.addModule("librealsense");

    const realsense = b.addLibrary(.{
        .name = "librealsense",
        .linkage = .static,
        .root_module = librealsense,
    });
    try linkLibRealsense(b, realsense);

    const exe = b.addExecutable(.{
        .name = "librealsensezig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "librealsense", .module = librealsense },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    const asm_step = b.step("asm", "Emit assembly file");
    const awf = b.addWriteFiles();
    awf.step.dependOn(b.getInstallStep());
    // Path is relative to the cache dir in which it *would've* been placed in
    const asm_file_name = try std.fmt.allocPrint(b.allocator, "../../../zig-out/asm/rs.s", .{});
    _ = awf.addCopyFile(exe.getEmittedAsm(), asm_file_name);
    asm_step.dependOn(&awf.step);
}
