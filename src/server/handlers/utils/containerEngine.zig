const std = @import("std");
const rootSrc = @import("~");

const ContainerEngine = enum {
    valid,
    err,
    noContainerEngine,
};
const ContainerIs = enum {
    podman,
    docker,
    noContainer,
};

pub fn Container(
    allocator: std.mem.Allocator,
    io: std.Io,
    env: *const rootSrc.config.env.ENV,
    target: []const u8,
) !void {
    var buffPath: [1024]u8 = undefined;
    const pathComplete = try std.fmt.bufPrint(&buffPath, "{s}/{s}", .{ env.APPS, target });
    const commandDown = [_][]const u8{
        "docker",
        "compose",
        "down",
    };
    const commandPull = [_][]const u8 {
        "docker",
        "compose",
        "pull",
    };
    const commandUp = [_][]const u8{
        "docker",
        "compose",
        "up",
        "-d"
    };
    const resultDown = try command(allocator, io, pathComplete, &commandDown);
    if (resultDown == .err) {
        std.debug.print("error resultDown\n", .{});
        return;
    }
    if (resultDown == .noContainerEngine) {
        std.debug.print("noContainerEngine resultDown\n", .{});
        return;
    }
    const resultPull = try command(allocator, io, pathComplete, &commandPull);
    if (resultPull == .err) {
        std.debug.print("error resultPull\n", .{});
        return;
    }
    if (resultPull == .noContainerEngine) {
        std.debug.print("noContainerEngine resultPull\n", .{});
        return;
    }
    const resultUp = try command(allocator, io, pathComplete, &commandUp);
    if (resultUp == .err) {
        std.debug.print("error resultUp\n", .{});
        return;
    }
    if (resultUp == .noContainerEngine) {
        std.debug.print("noContainerEngine resultUp\n", .{});
        return;
    }
}

fn command(
    allocator: std.mem.Allocator,
    io: std.Io,
    pathComplete: []const u8,
    commandLine: []const []const u8,
) !ContainerEngine {
    const result = try std.process.run(allocator, io, .{
        .argv = commandLine,
        .cwd = .{ .path = pathComplete },
    });
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
    const resutlSwitch = switch (result.term) {
        .signal => {
            std.debug.print("kill signal\n", .{});
            return .err;
        },
        .exited => |code| {
            if (code != 0) {
                std.debug.print("error exited: [{d}]\n", .{code});
                return .err;
            }
            std.debug.print("correct command resutl: {s}", .{result.stdout});
            return .valid;
        },
        .unknown => {
            std.debug.print("error unknown: {any}\n", .{result.stderr});
            return .err;
        },
        else => return .noContainerEngine,
    };

    return resutlSwitch;
}
