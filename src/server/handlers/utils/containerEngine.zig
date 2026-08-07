const std = @import("std");

const ContainerEngine = enum {
    valid,
    err,
    noContainerEngine,
};

pub fn Container(allocator: std.mem.Allocator, io: std.Io) !ContainerEngine {
    const result = try std.process.run(allocator, io, .{
        .argv = &.{ "docker", "-v" },
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

