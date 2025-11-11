const std = @import("std");
const rs = @import("librealsense");

pub fn main() !void {
    std.debug.print("RS2 API: {d}.{d}.{d}.{d}\n", .{
        rs.RS2_API_MAJOR_VERSION,
        rs.RS2_API_MINOR_VERSION,
        rs.RS2_API_PATCH_VERSION,
        rs.RS2_API_BUILD_VERSION,
    });
}
