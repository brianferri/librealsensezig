const std = @import("std");
const rs = @import("librealsense").c;

const time = std.time;

const pixels = " .:nhBXWW";

const STREAM_W = 640;
const STREAM_H = 480;

const BLOCK_W = 4;
const BLOCK_H = 8;
const BLOCK_AREA = BLOCK_W * BLOCK_H;

const ROW_LENGTH = STREAM_W / BLOCK_W;
const ROWS = STREAM_H / BLOCK_H;

const DISPLAY_SIZE = (ROWS + 1) * (ROW_LENGTH + 1);

pub fn main() !void {
    var stdout_buffer: [DISPLAY_SIZE]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var e: ?*rs.rs2_error = null;

    const ctx = rs.rs2_create_context(rs.RS2_API_VERSION, &e);
    defer rs.rs2_delete_context(ctx);
    check_error(e);

    const device_list = rs.rs2_query_devices(ctx, &e);
    defer rs.rs2_delete_device_list(device_list);
    check_error(e);

    const dev_count = rs.rs2_get_device_count(device_list, &e);
    check_error(e);

    std.debug.print("There are {d} connected RealSense devices.\n", .{dev_count});
    if (dev_count == 0) return;

    const dev = rs.rs2_create_device(device_list, 0, &e);
    defer rs.rs2_delete_device(dev);
    check_error(e);

    print_device_info(dev);

    const depth_unit = get_depth_unit_value(dev);
    const one_meter: u16 = @intFromFloat(1.0 / depth_unit);

    const pipeline = rs.rs2_create_pipeline(ctx, &e);
    defer rs.rs2_delete_pipeline(pipeline);
    check_error(e);

    const config = rs.rs2_create_config(&e);
    defer rs.rs2_delete_config(config);
    check_error(e);

    rs.rs2_config_enable_stream(config, rs.RS2_STREAM_DEPTH, 0, STREAM_W, STREAM_H, rs.RS2_FORMAT_Z16, 30, &e);
    check_error(e);

    const profile = rs.rs2_pipeline_start_with_config(pipeline, config, &e);
    defer rs.rs2_delete_pipeline_profile(profile);
    check_error(e);

    const denom = BLOCK_AREA / (pixels.len - 1);

    var buffer: [DISPLAY_SIZE]u8 = undefined;
    var coverage: [ROW_LENGTH]usize = undefined;

    while (true) {
        const frames = rs.rs2_pipeline_wait_for_frames(pipeline, rs.RS2_DEFAULT_TIMEOUT, &e);
        defer rs.rs2_release_frame(frames);
        check_error(e);

        const frame_count = rs.rs2_embedded_frames_count(frames, &e);
        check_error(e);

        var fi: c_int = 0;
        while (fi < frame_count) : (fi += 1) {
            var timer = try time.Timer.start();
            const frame = rs.rs2_extract_frame(frames, fi, &e);
            defer rs.rs2_release_frame(frame);
            check_error(e);

            if (rs.rs2_is_frame_extendable_to(frame, rs.RS2_EXTENSION_DEPTH_FRAME, &e) == 0) {
                check_error(e);
                continue;
            }

            const depth_ptr = rs.rs2_get_frame_data(frame, &e);
            check_error(e);
            const depth_data: [*]const u16 = @ptrCast(@alignCast(depth_ptr));
            @memset(&coverage, 0);

            var data_ptr = depth_data;
            var out_index: usize = 0;
            var block_y: usize = 0;

            for (0..STREAM_H) |_| {
                for (0..ROW_LENGTH) |cov_idx| {
                    var block_hits: usize = 0;
                    for (0..BLOCK_W) |_| {
                        const depth = data_ptr[0];
                        data_ptr += 1;
                        if (depth > 0 and depth < one_meter) block_hits += 1;
                    }

                    coverage[cov_idx] += block_hits;
                }

                block_y += 1;

                if (block_y == BLOCK_H) {
                    block_y = 0;

                    for (0..ROW_LENGTH) |i| {
                        const hits = coverage[i];
                        const pixel_i = if (hits >= BLOCK_AREA)
                            pixels.len - 1
                        else
                            hits / denom;

                        buffer[out_index] = pixels[pixel_i];
                        out_index += 1;
                        coverage[i] = 0;
                    }

                    buffer[out_index] = '\n';
                    out_index += 1;
                }
            }

            const iter_time = @as(f64, @floatFromInt(timer.read())) / time.ns_per_ms;
            try stdout.print("\x1B[2J\x1B[H{s}\n", .{buffer[0..out_index]});
            try stdout.flush();
            std.debug.print("frame time: {d}\n", .{ iter_time });
        }
    }
}

fn check_error(err: ?*rs.rs2_error) void {
    if (err) |e| {
        std.debug.panic("rs_error was raised when calling {s}({s}):\n {s}", .{
            rs.rs2_get_failed_function(e),
            rs.rs2_get_failed_args(e),
            rs.rs2_get_error_message(e),
        });
    }
}

fn get_depth_unit_value(dev: ?*rs.rs2_device) f32 {
    var e: ?*rs.rs2_error = null;

    const sensor_list = rs.rs2_query_sensors(dev, &e);
    defer rs.rs2_delete_sensor_list(sensor_list);

    const num_sensors = rs.rs2_get_sensors_count(sensor_list, &e);
    check_error(e);

    var depth_scale: f32 = 0.001;
    var found_depth_sensor = false;

    var i: c_int = 0;
    while (i < num_sensors) : (i += 1) {
        const sensor = rs.rs2_create_sensor(sensor_list, i, &e);
        defer rs.rs2_delete_sensor(sensor);
        check_error(e);

        const is_depth = rs.rs2_is_sensor_extendable_to(
            sensor,
            rs.RS2_EXTENSION_DEPTH_SENSOR,
            &e,
        );
        check_error(e);

        if (is_depth == 1) {
            if (rs.rs2_supports_option(@ptrCast(sensor), rs.RS2_OPTION_DEPTH_UNITS, &e) == 1) {
                depth_scale = rs.rs2_get_option(@ptrCast(sensor), rs.RS2_OPTION_DEPTH_UNITS, &e);
                check_error(e);
            }
            found_depth_sensor = true;
            break;
        }
    }

    if (!found_depth_sensor)
        std.debug.panic("Depth sensor not found!\n", .{}) catch {};

    return depth_scale;
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
