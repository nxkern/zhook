const std = @import("std");

pub fn HandleCD(req: *std.http.Server.Request) !void {
    var buff: [300]u8 = undefined;
    const result = try std.fmt.bufPrint(&buff, "Welcome to {s}\n", .{req.head.target});
    try req.respond(result, .{
        .status = .ok,
        .extra_headers = &.{.{ .name = "content-type", .value = "text/plain; charset=utf-8" }},
    });
}
