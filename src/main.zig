const std = @import("std");
const server = @import("./server/server.zig");


pub fn main(init: std.process.Init) !void {
    try server.Server(init);

}
