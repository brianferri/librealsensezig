const std = @import("std");
const mem = std.mem;

const Target = struct {
    include: [][]const u8,
    files: [][]const u8,
    flags: [][]const u8,
    modules: [][]const u8,
};

const Module = struct {
    include: [][]const u8,
    files: [][]const u8,
    headers: []struct {
        source: []const u8,
        dest: []const u8,
    },
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

    const base = try getConfig(Target, b, "targets", "base");
    const target_os = getConfig(Target, b, "targets", target_config) catch return error.InvalidTarget;

    const include = try std.mem.concat(b.allocator, []const u8, &.{ base.include, target_os.include });
    const files = try std.mem.concat(b.allocator, []const u8, &.{ base.files, target_os.files });
    const flags = try std.mem.concat(b.allocator, []const u8, &.{ base.flags, target_os.flags });
    const modules = try std.mem.concat(b.allocator, []const u8, &.{ base.modules, target_os.modules });

    for (include) |include_path| {
        librealsense.root_module.addIncludePath(realsense.path(include_path));
    }

    librealsense.root_module.addCSourceFiles(.{
        .root = realsense.path(""),
        .files = files,
        .flags = flags,
    });

    if (target.result.os.tag == .windows) {
        librealsense.root_module.linkSystemLibrary("mf", .{});
        librealsense.root_module.linkSystemLibrary("mfplat", .{});
        librealsense.root_module.linkSystemLibrary("mfreadwrite", .{});
        librealsense.root_module.linkSystemLibrary("mfuuid", .{});
        librealsense.root_module.linkSystemLibrary("Shlwapi", .{});
        librealsense.root_module.linkSystemLibrary("Ole32", .{});
        librealsense.root_module.linkSystemLibrary("Setupapi", .{});
        librealsense.root_module.linkSystemLibrary("WinUSB", .{});
    } else if (target.result.os.tag == .macos) {
        librealsense.root_module.linkFramework("CoreFoundation", .{});
        librealsense.root_module.linkFramework("IOKit", .{});
    } else if (target.result.os.tag == .linux) {
        librealsense.root_module.linkSystemLibrary("udev", .{});
    }

    if (target.result.os.tag != .windows) {
        librealsense.root_module.linkSystemLibrary("usb-1.0", .{});
    }

    for (modules) |module| {
        const module_config = try getConfig(Module, b, "targets/modules", module);
        addModule(librealsense, realsense, module_config);
    }

    linkNlohmannJson(b, librealsense);
    lib.root_module.linkLibrary(librealsense);
}

pub fn linkNlohmannJson(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
) void {
    const json = b.dependency("nlohmann_json", .{});
    lib.root_module.addIncludePath(json.path("include"));
    lib.root_module.addIncludePath(json.path("include/nlohmann"));
    lib.installHeader(json.path("include/nlohmann/json_fwd.hpp"), "nlohmann/json_fwd.hpp");
    lib.installHeader(json.path("include/nlohmann/json.hpp"), "nlohmann/json.hpp");
}

fn getConfig(comptime T: type, b: *std.Build, dir: []const u8, name: []const u8) !T {
    const alloc = b.allocator;

    const config_path = try b.build_root.handle.realpathAlloc(alloc, b.fmt("{s}/{s}.zon", .{ dir, name }));
    defer alloc.free(config_path);

    const config_file = try std.fs.openFileAbsolute(config_path, .{});
    defer config_file.close();

    const file = try config_file.stat();
    var buffer = try alloc.allocSentinel(u8, file.size, 0);
    errdefer alloc.destroy(&buffer);

    var reader = config_file.reader(buffer);
    try reader.interface.readSliceAll(buffer);

    return try std.zon.parse.fromSlice(T, alloc, buffer, null, .{});
}

pub fn addModule(
    lib: *std.Build.Step.Compile,
    dependency: *std.Build.Dependency,
    module: Module,
) void {
    for (module.include) |include| {
        lib.root_module.addIncludePath(dependency.path(include));
    }

    for (module.headers) |header| {
        lib.installHeader(dependency.path(header.source), header.dest);
    }

    lib.root_module.addCSourceFiles(.{
        .root = dependency.path(""),
        .files = module.files,
    });
}

