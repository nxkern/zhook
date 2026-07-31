const std = @import("std");
const rootSrc = @import("~");

const UserTest = struct { usuario: []const u8, id: u32, activo: bool };

pub fn HandleCD(
    req: *std.http.Server.Request,
    allocator: std.mem.Allocator,
    env: *const rootSrc.config.env.ENV,
) !void {
    const headers = req.head_buffer;
    const types = rootSrc.customTypes;

    var lines = std.mem.tokenizeSequence(u8, headers, "\r\n");

    var jsonResponde: types.json.tokenJson = undefined;

    var buffJson: [1024]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buffJson);
    var w: std.json.Stringify = .{ .writer = &out, .options = .{} };

    while (lines.next()) |line| {
        if (line.len == 0) break;
        if (std.mem.startsWith(u8, line, "Authorization: ") or std.mem.startsWith(u8, line, "authorization: ")) {
            const auth_value = line[15..];
            if (auth_value.len > 7 and std.mem.startsWith(u8, auth_value, "Bearer ")) {
                const token = auth_value[7..];
                if (std.mem.eql(u8, token, env.TOKEN)) {

                } else {
                    jsonResponde = types.json.tokenJson{
                        .data = error.incorrectToken,
                    };

                    try w.beginObject();
                    inline for (@typeInfo(@TypeOf(jsonResponde)).@"struct".fields) |key| {
                        try w.objectField(key.name);
                        if (@field(jsonResponde, key.name)) |_| {} else |err| {
                            try w.print("{s}", .{@errorName(err)});
                        }
                    }
                    try w.endObject();
                    try req.respond(out.buffered(), .{
                        .status = .unauthorized,
                        .extra_headers = &.{
                            .{ .name = "content-type", .value = "apllication/json" },
                        },
                    });
                    return;
                }
            }
        }
    }

    if (req.head.content_length) |len| {
        const bodyBuff = try allocator.alloc(u8, len);
        defer allocator.free(bodyBuff);
        var buffer: [1024]u8 = undefined;
        const reader = try req.readerExpectContinue(&buffer);
        try reader.readSliceAll(bodyBuff);
        const parsed = try std.json.parseFromSlice(UserTest, allocator, bodyBuff, .{});
        defer parsed.deinit();

        try req.respond("", .{
            .status = .ok,
            .extra_headers = &.{.{ .name = "content-type", .value = "text/plain; charset=utf-8" }},
        });
    }
}
