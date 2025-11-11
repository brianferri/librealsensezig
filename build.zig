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

    const realsense = b.addLibrary(.{
        .name = "librealsense",
        .linkage = .static,
        .root_module = librealsensebindings.createModule(),
    });
    try linkLibRealsense(b, realsense);

    const librealsensezig = b.addLibrary(.{
        .name = "librealsensezig",
        .root_module = b.addModule("librealsensezig", .{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "librealsense", .module = realsense.root_module },
            },
        }),
    });

    b.installArtifact(librealsensezig);

    for ((try getExamples(b)).items) |example|
        try createExampleRunStep(b, example, librealsensezig);
}

const ExamplePath = struct {
    dir: []const u8,
    path: []const u8,
};
const Examples = std.ArrayListUnmanaged(ExamplePath);

fn getExamples(b: *std.Build) !Examples {
    var examples: Examples = .empty;

    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    var walker = try dir.walk(b.allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file and std.mem.eql(u8, entry.basename, "main.zig")) {
            const parent_dir = std.fs.path.dirname(entry.path) orelse continue;
            try examples.append(b.allocator, .{
                .dir = try b.allocator.dupe(u8, parent_dir),
                .path = try b.allocator.dupe(u8, entry.path),
            });
        }
    }

    return examples;
}

fn createExampleRunStep(
    b: *std.Build,
    example: ExamplePath,
    lib: *std.Build.Step.Compile,
) !void {
    const example_name = std.fs.path.basename(example.dir);
    const exe = b.addExecutable(.{
        .name = example_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(example.path),
            .target = lib.root_module.resolved_target.?,
            .optimize = lib.root_module.optimize.?,
            .imports = &.{
                .{ .name = "librealsense", .module = lib.root_module },
            },
        }),
    });

    const exe_install = b.addInstallArtifact(exe, .{});
    const run_example = b.addRunArtifact(exe);
    run_example.step.dependOn(&exe_install.step);

    const run_description = try std.fmt.allocPrint(b.allocator, "Run the {s} example", .{example_name});
    const example_step = b.step(example_name, run_description);
    example_step.dependOn(&run_example.step);

    const add_source = b.addUpdateSourceFiles();
    add_source.addCopyFileToSource(exe.getEmittedAsm(), "zig-out/asm/main.asm");
    add_source.step.dependOn(b.getInstallStep());

    const asm_description = try std.fmt.allocPrint(b.allocator, "Emit the {s} example ASM file", .{example_name});
    const asm_step_name = try std.fmt.allocPrint(b.allocator, "{s}-asm", .{example_name});
    const example_asm_step = b.step(asm_step_name, asm_description);
    example_asm_step.dependOn(&add_source.step);
}
