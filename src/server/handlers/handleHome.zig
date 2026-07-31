const std = @import("std");
const rootSrc = @import("~");

pub fn handleHome(
    req: *std.http.Server.Request,
    allocator: std.mem.Allocator,
    env: *const rootSrc.config.env.ENV,
) !void {
    _ = allocator;
    _ = env;
    try req.respond("Welcome to home\n", .{ .status = .ok, .extra_headers = &.{.{
        .name = "content-type",
        .value = "text/plain; charset=utf-8",
    }} });
}
