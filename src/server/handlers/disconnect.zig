const std = @import("std");

pub fn handleDisconnect(init: std.process.Init, status: std.http.Status) !void {
    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const stdout = &stdout_writer.interface;
    try stdout.print("connect unavailable code: {d}\n", .{@intFromEnum(status)});
    try stdout.flush();
}
