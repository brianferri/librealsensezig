const std = @import("std");
const rs = @import("librealsense").c;

fn check_error(err: ?*rs.rs2_error) void {
    if (err) |e| {
        std.debug.panic("rs_error was raised when calling {s}({s}):\n {s}", .{
            rs.rs2_get_failed_function(e),
            rs.rs2_get_failed_args(e),
            rs.rs2_get_error_message(e),
        });
    }
}

fn print_device_info(dev: ?*rs.rs2_device) void {
    var rs2_error: ?*rs.rs2_error = null;
    const dev_name = rs.rs2_get_device_info(dev, rs.RS2_CAMERA_INFO_NAME, &rs2_error);
    check_error(rs2_error);
    const dev_serial = rs.rs2_get_device_info(dev, rs.RS2_CAMERA_INFO_SERIAL_NUMBER, &rs2_error);
    check_error(rs2_error);
    const dev_fw_version = rs.rs2_get_device_info(dev, rs.RS2_CAMERA_INFO_FIRMWARE_VERSION, &rs2_error);
    check_error(rs2_error);

    std.debug.print(
        \\Device    : {s}
        \\  Serial  : {s}
        \\  Firmware: {s}
        \\
    , .{ dev_name, dev_serial, dev_fw_version });
}

pub fn main() !void {
    std.debug.print("RS2 API: {d}.{d}.{d}.{d}\n", .{
        rs.RS2_API_MAJOR_VERSION,
        rs.RS2_API_MINOR_VERSION,
        rs.RS2_API_PATCH_VERSION,
        rs.RS2_API_BUILD_VERSION,
    });

    var e: ?*rs.rs2_error = null;

    const ctx = rs.rs2_create_context(rs.RS2_API_VERSION, &e);
    defer rs.rs2_delete_context(ctx);
    check_error(e);

    const device_list = rs.rs2_query_devices(ctx, &e);
    defer rs.rs2_delete_device_list(device_list);
    check_error(e);

    const dev_count = rs.rs2_get_device_count(device_list, &e);
    check_error(e);

    std.debug.print("{d} Devices Found\n", .{dev_count});
    if (dev_count == 0) std.process.cleanExit();

    const dev = rs.rs2_create_device(device_list, 0, &e);
    defer rs.rs2_delete_device(dev);
    check_error(e);

    print_device_info(dev);

    const pipeline = rs.rs2_create_pipeline(ctx, &e);
    defer rs.rs2_delete_pipeline(pipeline);
    check_error(e);

    const config = rs.rs2_create_config(&e);
    defer rs.rs2_delete_config(config);
    check_error(e);

    rs.rs2_config_enable_stream(config, rs.RS2_STREAM_COLOR, -1, 0, 0, rs.RS2_FORMAT_ANY, 0, &e);
    check_error(e);

    const pipeline_profile = rs.rs2_pipeline_start_with_config(pipeline, config, &e);
    defer rs.rs2_delete_pipeline_profile(pipeline_profile);
    if (e != null)
        std.debug.panic("The connected device doesn't support color streaming!\n", .{});

    while (true) {
        const frames = rs.rs2_pipeline_wait_for_frames(pipeline, rs.RS2_DEFAULT_TIMEOUT, &e);
        defer rs.rs2_release_frame(frames);
        check_error(e);

        const frame_count = rs.rs2_embedded_frames_count(frames, &e);
        check_error(e);

        var i: c_int = 0;
        while (i < frame_count) : (i += 1) {
            const frame = rs.rs2_extract_frame(frames, i, &e);
            defer rs.rs2_release_frame(frame);
            check_error(e);

            const data_ptr = rs.rs2_get_frame_data(frame, &e);
            check_error(e);
            const rgb_data: [*]const u8 = @ptrCast(data_ptr);

            const frame_number = rs.rs2_get_frame_number(frame, &e);
            check_error(e);

            const timestamp = rs.rs2_get_frame_timestamp(frame, &e);
            check_error(e);

            const ts_domain = rs.rs2_get_frame_timestamp_domain(frame, &e);
            check_error(e);
            const ts_domain_str = rs.rs2_timestamp_domain_to_string(ts_domain);

            const toa = rs.rs2_get_frame_metadata(frame, rs.RS2_FRAME_METADATA_TIME_OF_ARRIVAL, &e);
            check_error(e);

            std.debug.print(
                \\RGB frame arrived.
                \\First 10 bytes:
                \\
            , .{});

            for (rgb_data[0..10]) |b| {
                std.debug.print("{x:0>2} ", .{b});
            }

            std.debug.print(
                \\
                \\Frame No: {d}
                \\Timestamp: {d}
                \\Timestamp domain: {s}
                \\Time of arrival: {d}
                \\
            , .{ frame_number, timestamp, ts_domain_str, toa });
        }
    }
}

