const std = @import("std");
const builtin = @import("builtin");
const server = @import("./server/server.zig");

var running: std.atomic.Value(bool) = std.atomic.Value(bool).init(true);

const ENV = struct {
    URI: []const u8,
    pub fn initEnv(init: std.process.Init, envs: ENV) !?ENV {
        const uri_val = init.environ_map.get(envs.URI) orelse return null;
        return ENV{
            .URI = uri_val,
        };
    }
};

fn handleSignal(sig: std.posix.SIG) callconv(.c) void {
    _ = sig;
    running.store(false, .release);
}

pub fn main(init: std.process.Init) !void {
    var dbg_alloc = if (builtin.mode == .Debug) std.heap.DebugAllocator(.{}){};
    defer {
        if (builtin.mode == .Debug) {
            const check = dbg_alloc.deinit();
            if (check == .leak) std.debug.print("memory leak: ", .{});
        }
    }
    const allocator = if (builtin.mode == .Debug) dbg_alloc.allocator() else std.heap.page_allocator;

    const act = std.posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };

    std.posix.sigaction(std.posix.SIG.TERM, &act, null);
    std.posix.sigaction(std.posix.SIG.INT, &act, null);

    const envs = try ENV.initEnv(init, .{
        .URI = "URI_SERVER",
    });
    const thread1 = try std.Thread.spawn(.{}, Ticker, .{ init, envs.?.URI, allocator });
    const thread2 = try std.Thread.spawn(.{}, server.ServerListen, .{ init, running });
    while (running.load(.acquire)) {
        try std.Io.sleep(init.io, std.Io.Duration.fromMilliseconds(50), std.Io.Clock.awake);
    }
    try std.Io.sleep(init.io, std.Io.Duration.fromMilliseconds(100), std.Io.Clock.awake);

    thread1.detach();
    thread2.detach();
    std.debug.print("\nGood Bye\n", .{});
}

fn Ticker(init: std.process.Init, uri: ?[]const u8, allocator: std.mem.Allocator) !void {
    const method: std.http.Method = .POST;
    var buff: [100]u8 = undefined;
    var url: []const u8 = undefined;
    if (uri) |unwrap_uri| {
        url = try std.fmt.bufPrint(&buff, "{s}/heartbeat", .{unwrap_uri});
    } else {
        return;
    }
    const headers: []const std.http.Header = &.{
        .{ .name = "content-type", .value = "application/json" },
    };
    const payload = "{\"username\": \"zig_user\"}";
    while (running.load(.acquire)) {
        const value, const status = server.NewRequest(init, allocator, url, method, headers, payload);
        try switch (@intFromEnum(status)) {
            @intFromEnum(std.http.Status.service_unavailable) => handleDisconnect(),
            400...499 => std.debug.print("status code: {d}\n", .{@intFromEnum(status)}),
            200...299 => {
                if (value) |res| {
                    std.debug.print("{d}\n", .{@intFromEnum(res.status)});
                }
            },
            else => {
                std.debug.print("error", .{});
                return;
            },
        };
        try std.Io.sleep(init.io, std.Io.Duration.fromSeconds(1), std.Io.Clock.awake);
    }
}

fn handleDisconnect() !void {
    std.debug.print("Disconnect\n", .{});
}
