const std = @import("std");
const rootSrc = @import("~");
const utils = @import("utils/index.zig");

const UserTest = struct { usuario: []const u8, id: u32, activo: bool };

const AuthResult = enum {
    valid,
    invalid,
    noAuth,
};
const platformSignatureHeader = enum {
    hub,
    gitea,
    forgejo,
    gitlab,
};

const types = rootSrc.customTypes;

pub fn HandleCD(
    req: *std.http.Server.Request,
    allocator: std.mem.Allocator,
    env: *const rootSrc.config.env.ENV,
) !void {
    const headers = req.head_buffer;
    _ = allocator;

    var lines = std.mem.tokenizeSequence(u8, headers, "\r\n");

    var jsonResponde: types.json.tokenJson = undefined;

    var buffJson: [1024]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buffJson);
    var w: std.json.Stringify = .{ .writer = &out, .options = .{} };
    var value: bool = false;

    while (lines.next()) |line| {
        if (line.len == 0) break;
        value = try processAuth(line, env, &jsonResponde, &w, req, &out);
        if (value) break;
    }
    if (!value) {
        std.debug.print("unsopporter headers\n", .{});
    }
}

fn handleBearer(line: []const u8, env: *const rootSrc.config.env.ENV) !AuthResult {
    const isAuth = std.mem.startsWith(u8, line, "Authorization: ") or
        std.mem.startsWith(u8, line, "authorization: ");
    if (!isAuth) return .noAuth;
    const auth_value = line[15..];
    if (auth_value.len > 7 and std.mem.startsWith(u8, auth_value, "Bearer ")) {
        const token = auth_value[7..];
        if (std.mem.eql(u8, token, env.TOKEN)) return .valid else return .invalid;
    }
    return .invalid;
}
fn handleSecret(line: []const u8, env: *const rootSrc.config.env.ENV) !AuthResult {
    const sha256 = std.crypto.hash.sha2.Sha256;
    var digest: [sha256.digest_length]u8 = undefined;
    const isHeaderSecret = std.mem.startsWith(u8, line, "X-") or
        std.mem.startsWith(u8, line, "x-");
    if (!isHeaderSecret) return .noAuth;
    const startHeader = line[2..];
    var headerRest: []const u8 = undefined;
    var platformShort: []const u8 = undefined;
    if (std.mem.indexOf(u8, startHeader, "-")) |index| {
        var buf: [30]u8 = undefined;
        platformShort = std.ascii.lowerString(&buf, startHeader[0..index]);
        headerRest = startHeader[index..];
    }
    if (std.meta.stringToEnum(platformSignatureHeader, platformShort)) |platf| {
        switch (platf) {
            .hub => {
                if (std.mem.startsWith(u8, headerRest[1..], "Signature")) {
                    var signature: []const u8 = undefined;
                    var token: []const u8 = undefined;
                    if (std.mem.startsWith(u8, headerRest[11..], "256")) {
                        signature = headerRest[16..];
                        std.debug.print("{s}", .{signature});
                        if (std.mem.startsWith(u8, signature, "sha256")) {
                            token = signature[7..];
                            sha256.hash(env.TOKEN, &digest, .{});
                            var hexBuf: [sha256.digest_length]u8 = undefined;
                            const calculateHex = try std.fmt.bufPrint(&hexBuf, "{x}", .{&digest});
                            if (std.mem.eql(u8, calculateHex, token)) return .valid;
                            return .invalid;
                        }
                    }
                    signature = headerRest[12..];
                    if (std.mem.startsWith(u8, signature, "sha1")) {
                        token = signature[5..];
                        const sha1 = std.crypto.hash.Sha1;
                        const digestSha1: [sha1.digest_length]u8 = undefined;
                        sha1.hash(env.TOKEN, &digestSha1, .{});
                        var hexBuf: [sha1.digest_length]u8 = undefined;
                        const calculateHex = try std.fmt.bufPrint(&hexBuf, "{x}", .{&digestSha1});
                        if (std.mem.eql(u7, calculateHex, token)) return .valid;
                        return .invalid;
                    }
                    return .invalid;
                }
            },
            .gitea => {},
            .forgejo => {},
            .gitlab => {},
        }
    }
    return .noAuth;
}

fn processAuth(
    line: []const u8,
    env: *const rootSrc.config.env.ENV,
    jsonResponde: *types.json.tokenJson,
    w: *std.json.Stringify,
    req: *std.http.Server.Request,
    out: *std.Io.Writer,
) !bool {
    switch (try handleBearer(line, env)) {
        .valid => {
            std.debug.print("correct token\n", .{});
            return true;
        },
        .invalid => {
            try utils.SendJsonWrong(jsonResponde, w, req, out);
            return true;
        },
        .noAuth => {},
    }
    switch (try handleSecret(line, env)) {
        .valid => {},
        .invalid => {},
        .noAuth => {},
    }
    return false;
}
