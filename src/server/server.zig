const std = @import("std");
const barrel = @import("./handlers/index.zig");

const Handler = *const fn (req: *std.http.Server.Request) anyerror!void;

const Route = struct {
    method: std.http.Method,
    path: []const u8,
    handle: Handler,
};

const routes = [_]Route{
    .{ .method = .GET, .path = "/api", .handle = barrel.handleHome },
    .{ .method = .GET, .path = "/api/cd", .handle = barrel.HandleCD },
};

pub fn dispatch(req: *std.http.Server.Request) !void {
    for (routes) |route| {
        if (route.method == req.head.method and std.mem.eql(u8, route.path, req.head.target)) {
            return try route.handle(req);
        }
    }
    try req.respond("404 Not Found\n", .{ .status = .not_found });
}


pub fn ServerListen(init: std.process.Init, running: std.atomic.Value(bool)) !void {
    const io = init.io;
    const net = std.Io.net;
    const address = net.IpAddress;
    const ip = try net.IpAddress.parse("127.0.0.1", 8088);
    var server_listener = try address.listen(&ip, io, .{
        .reuse_address = true,
    });
    std.debug.print("Server listening in 127.0.0.1:8088\n", .{});

    while (running.load(.acquire)) {
        var buf: [1024]u8 = undefined;
        var stream = try server_listener.accept(io);
        defer stream.close(io);

        var reader = stream.reader(io, &buf);
        var writter = stream.writer(io, &buf);

        var http_server = std.http.Server.init(&reader.interface, &writter.interface);
        var req = try http_server.receiveHead();

        try dispatch(&req);
    }
}

pub fn NewRequest(init: std.process.Init, allocatorMem: std.mem.Allocator, url: []const u8, method: std.http.Method, headers: []const std.http.Header, payload: ?[]const u8) struct { ?std.http.Client.FetchResult, std.http.Status } {
    const io = init.io;
    var arena = std.heap.ArenaAllocator.init(allocatorMem);
    defer arena.deinit();
    const allocator = arena.allocator();
    const uri = std.Uri.parse(url) catch return .{ null, .bad_request };

    var client: std.http.Client = .{
        .allocator = allocator,
        .io = io,
    };
    defer client.deinit();
    const result = client.fetch(.{
        .location = .{ .uri = uri },
        .method = method,
        .extra_headers = headers,
        .payload = payload,
    }) catch return .{ null,  .service_unavailable };

    return .{ result, result.status };
}
