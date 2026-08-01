const rootSrc = @import("~");
const std = @import("std");

const types = rootSrc.customTypes;

pub fn SendJsonWrong(
    jsonResponde: *types.json.tokenJson,
    w: *std.json.Stringify,
    req: *std.http.Server.Request,
    out: *std.Io.Writer
) !void {
    jsonResponde.* = types.json.tokenJson{
        .data = error.incorrectToken,
    };

    try w.*.beginObject();
    inline for (@typeInfo(@TypeOf(jsonResponde.*)).@"struct".fields) |key| {
        try w.*.objectField(key.name);
        if (@field(jsonResponde.*, key.name)) |_| {} else |err| {
            try w.*.print("{s}", .{@errorName(err)});
        }
    }
    try w.endObject();
    try req.*.respond(out.*.buffered(), .{
        .status = .unauthorized,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "apllication/json" },
        },
    });
    return;
}
