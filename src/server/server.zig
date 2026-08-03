const std = @import("std");
const barrel = @import("handlers/index.zig");
const rootSrc = @import("~");

const Handler = *const fn (
    req: *std.http.Server.Request,
    allocator: std.mem.Allocator,
    env: *const rootSrc.config.env.ENV,
) anyerror!void;

const Route = struct {
    method: std.http.Method,
    path: []const u8,
    handle: Handler,
};

const routes = [_]Route{
    .{ .method = .GET, .path = "/api", .handle = barrel.handleHome },
    .{ .method = .POST, .path = "/api/cd", .handle = barrel.HandleCD },
};

pub fn dispatch(
    req: *std.http.Server.Request,
    allocator: std.mem.Allocator,
    env: *const rootSrc.config.env.ENV,
) !void {
    for (routes) |route| {
        if (route.method == req.head.method and std.mem.eql(u8, route.path, req.head.target)) {
            return try route.handle(req, allocator, env);
        }
    }
    try req.respond("404 Not Found\n", .{ .status = .not_found });
}

pub fn ServerListen(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    environMap: *const rootSrc.config.env.ENV,
    stdout: *std.Io.Writer,
) !void {
    const io = init.io;
    const net = std.Io.net;
    const address = net.IpAddress;
    const ip = try net.IpAddress.parse("0.0.0.0", 8088);
    var server_listener = try address.listen(&ip, io, .{
        .reuse_address = true,
    });
    try stdout.print("Server listening in 0.0.0.0:8088\n", .{});
    try stdout.flush();

    while (rootSrc.running.load(.acquire)) {
        var buf: [16384]u8 = undefined;
        var stream = try server_listener.accept(io);
        defer stream.close(io);

        var reader = stream.reader(io, &buf);
        var writter = stream.writer(io, &buf);

        var http_server = std.http.Server.init(&reader.interface, &writter.interface);
        var req = try http_server.receiveHead();

        try dispatch(&req, allocator, environMap);
    }
}

pub fn NewRequest(
    init: std.process.Init,
    allocatorMem: std.mem.Allocator,
    url: []const u8,
    method: std.http.Method,
    headers: []const std.http.Header,
    payload: ?[]const u8,
) struct {
    ?std.http.Client.FetchResult,
    std.http.Status,
} {
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
    }) catch return .{ null, .service_unavailable };

    return .{ result, result.status };
}
pub fn Ticker(
    init: std.process.Init,
    uri: ?[]const u8,
    allocator: std.mem.Allocator,
) !void {
    const method: std.http.Method = .POST;
    var count: u8 = 0;
    var buff: [100]u8 = undefined;
    const url: []const u8 = if (uri) |unwrap_uri|
        try std.fmt.bufPrint(&buff, "{s}/heartbeat", .{unwrap_uri})
    else
        return;

    const headers: []const std.http.Header = &.{
        .{ .name = "content-type", .value = "application/json" },
    };
    const payload = "{\"username\": \"zig_user\"}";
    while (rootSrc.running.load(.acquire)) {
        const value, const status = NewRequest(init, allocator, url, method, headers, payload);
        switch (@intFromEnum(status)) {
            @intFromEnum(std.http.Status.service_unavailable) => {
                count += 1;
                if (count >= 5) try barrel.Disconnect(init, status);
            },
            400...499 => std.debug.print("status code: {d}\n", .{@intFromEnum(status)}),
            200...299 => {
                if (value) |res| {
                    if (count != 0) count = 0;
                    std.debug.print("{d}\n", .{@intFromEnum(res.status)});
                }
            },
            else => {
                std.debug.print("error", .{});
                return;
            },
        }
        if (count >= 5) count = 0;
        try std.Io.sleep(init.io, std.Io.Duration.fromSeconds(30), std.Io.Clock.awake);
    }
}
