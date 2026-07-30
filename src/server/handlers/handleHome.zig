const std = @import("std");

pub fn handleHome(req: *std.http.Server.Request) !void {
    try req.respond("Welcome to home\n", .{ .status = .ok, .extra_headers = &.{.{
        .name = "content-type",
        .value = "text/plain; charset=utf-8",
    }} });
}
