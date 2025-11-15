const std = @import("std");
const mem = std.mem;

const Target = struct {
    include: [][]const u8,
    files: [][]const u8,
    flags: [][]const u8,
};

pub fn linkLibRealSense(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
) !void {
    const target = lib.root_module.resolved_target.?;
    const optimize = lib.root_module.optimize.?;

    const target_config = try std.fmt.allocPrint(b.allocator, "{s}-{s}", .{
        @tagName(target.result.cpu.arch),
        @tagName(target.result.os.tag),
    });

    const realsense = b.dependency("librealsense", .{});

    const librealsense = b.addLibrary(.{
        .name = "librealsense",
        .linkage = .static,
        .root_module = b.createModule(.{
            .link_libc = true,
            .link_libcpp = true,
            .target = target,
            .optimize = optimize,
        }),
    });

    const base = try getTarget(b.allocator, "base");
    const target_os = getTarget(b.allocator, target_config) catch return error.InvalidTarget;

    const include = try std.mem.concat(b.allocator, []const u8, &.{ base.include, target_os.include });
    const files = try std.mem.concat(b.allocator, []const u8, &.{ base.files, target_os.files });
    const flags = try std.mem.concat(b.allocator, []const u8, &.{ base.flags, target_os.flags });

    for (include) |include_path| {
        librealsense.addIncludePath(realsense.path(include_path));
    }

    librealsense.addCSourceFiles(.{
        .root = realsense.path(""),
        .files = files,
        .flags = flags,
    });

    if (target.result.os.tag == .windows) {
        librealsense.linkSystemLibrary("mf");
        librealsense.linkSystemLibrary("mfplat");
        librealsense.linkSystemLibrary("mfreadwrite");
        librealsense.linkSystemLibrary("mfuuid");
        librealsense.linkSystemLibrary("Shlwapi");
        librealsense.linkSystemLibrary("Ole32");
        librealsense.linkSystemLibrary("Setupapi");
        librealsense.linkSystemLibrary("WinUSB");
    } else if (target.result.os.tag == .macos) {
        librealsense.linkFramework("CoreFoundation");
        librealsense.linkFramework("IOKit");
    }

    if (target.result.os.tag != .windows) {
        librealsense.linkSystemLibrary("usb-1.0");
    }

    linkNlohmannJson(b, librealsense);
    lib.root_module.linkLibrary(librealsense);
}

pub fn linkNlohmannJson(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
) void {
    const json = b.dependency("nlohmann_json", .{});
    lib.addIncludePath(json.path("include"));
    lib.addIncludePath(json.path("include/nlohmann"));
    lib.installHeader(json.path("include/nlohmann/json_fwd.hpp"), "nlohmann/json_fwd.hpp");
    lib.installHeader(json.path("include/nlohmann/json.hpp"), "nlohmann/json.hpp");
}

fn getTarget(alloc: std.mem.Allocator, name: []const u8) !Target {
    const path = try std.fmt.allocPrint(alloc, "targets/{s}.zon", .{name});

    const input_file = try std.fs.cwd().openFile(path, .{});
    defer input_file.close();

    const file = try input_file.stat();
    var buffer = try alloc.allocSentinel(u8, file.size, 0);
    errdefer alloc.destroy(&buffer);

    var file_reader = input_file.reader(buffer);
    try file_reader.interface.readSliceAll(buffer);

    return try std.zon.parse.fromSlice(Target, alloc, buffer, null, .{});
}
