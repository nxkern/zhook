const std = @import("std");
const builtin = @import("builtin");
const server = @import("server/server.zig");

pub const config = .{
    .env = @import("config/env.zig"),
};

pub const customTypes = .{
    .json = @import("types/json.zig"),
};

pub var running: std.atomic.Value(bool) = std.atomic.Value(bool).init(true);

fn handleSignal(sig: std.posix.SIG) callconv(.c) void {
    _ = sig;
    running.store(false, .release);
}

pub fn main(init: std.process.Init) !void {
    var dbg_alloc = if (builtin.mode == .Debug) std.heap.DebugAllocator(.{}){};
    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const stdout = &stdout_writer.interface;
    const envsSystem = init.environ_map;
    const envMod = @import("~").config.env;
    const ENV = envMod.ENV;
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

    if (ENV.initEnv(envsSystem)) |configEnv| {
        var envs = configEnv.getEnvs();
        const thread1 = try std.Thread.spawn(.{}, server.Ticker, .{
            init,
            envs.URI,
            allocator,
        });
        const thread2 = try std.Thread.spawn(.{}, server.ServerListen, .{
            init, allocator, &envs, stdout,
        });
        while (running.load(.acquire)) {
            try std.Io.sleep(init.io, std.Io.Duration.fromMilliseconds(50), std.Io.Clock.awake);
        }
        try std.Io.sleep(init.io, std.Io.Duration.fromMilliseconds(100), std.Io.Clock.awake);

        thread1.detach();
        thread2.detach();
    }
    try stdout.print("\nGood Bye\n", .{});
    try stdout.flush();
}
