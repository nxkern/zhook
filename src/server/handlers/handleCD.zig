const std = @import("std");
const rootSrc = @import("~");
const utils = @import("utils/index.zig");

const customTypes = rootSrc.customTypes;

const WebhookPayload = union(enum) {
    github: customTypes.json.PayloadGithub,
    gitea: customTypes.json.PayloadGitea,
};

const AuthResult = enum {
    valid,
    invalid,
    noAuth,
};
const platformSignatureHeader = enum {
    hub,
    gitlab,
};
const payloadGl = struct {
    id: []const u8,
    signature: []const u8,
    timestamp: []const u8,
};

const types = rootSrc.customTypes;

pub fn HandleCD(
    req: *std.http.Server.Request,
    allocator: std.mem.Allocator,
    env: *const rootSrc.config.env.ENV,
    io: std.Io,
) !void {
    const headers = req.head_buffer;

    var lines = std.mem.tokenizeSequence(u8, headers, "\r\n");

    var jsonResponde: types.json.tokenJson = undefined;

    var buffJson: [1024]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buffJson);
    var w: std.json.Stringify = .{ .writer = &out, .options = .{} };
    var value: bool = false;

    // gitlab
    var glId: []const u8 = undefined;
    var glTt: []const u8 = undefined;
    var glSn: []const u8 = undefined;
    var platformGl: []const u8 = undefined;

    const data = req.readerExpectNone(&.{});
    const buffJsonData = try data.allocRemaining(allocator, .unlimited);
    defer allocator.free(buffJsonData);

    while (lines.next()) |line| {
        if (line.len == 0) break;
        value = try processAuth(
            line,
            env,
            &jsonResponde,
            &w,
            req,
            &out,
            buffJsonData,
            null,
            allocator,
            io,
        );
        if (value) break;
    }
    if (!value) {
        while (lines.next()) |line| {
            if (line.len == 0) break;
            if (std.mem.startsWith(u8, line, "webhook-signature")) glSn = line[3..];
            if (std.mem.startsWith(u8, line, "webhook-id")) glId = line;
            if (std.mem.startsWith(u8, line, "webhook-timestamp")) glTt = line;
            if (std.mem.startsWith(u8, line, "x-gitlab-event-uuid")) platformGl = "gitlab";
            break;
        }
        const payload = payloadGl{
            .id = glId,
            .timestamp = glTt,
            .signature = glSn,
        };
        value = try processAuth(
            platformGl,
            env,
            &jsonResponde,
            &w,
            req,
            &out,
            buffJsonData,
            payload,
            allocator,
            io,
        );
        if (!value) std.debug.print("unsopporter headers\n", .{});
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
fn handleSecret(
    line: []const u8,
    env: *const rootSrc.config.env.ENV,
    json: []const u8,
    payloadInfo: ?payloadGl,
) !AuthResult {
    const sha256 = std.crypto.auth.hmac.sha2.HmacSha256;
    var digest: [sha256.mac_length]u8 = undefined;
    const isHeaderSecret = std.mem.startsWith(u8, line, "X-") or
        std.mem.startsWith(u8, line, "x-");
    if (!isHeaderSecret) return .noAuth;
    const startHeader = line[2..];
    var headerRest: []const u8 = undefined;
    var platformShort: []const u8 = undefined;

    var buf: [30]u8 = undefined;

    if (std.mem.indexOf(u8, startHeader, "-")) |index| {
        platformShort = std.ascii.lowerString(&buf, startHeader[0..index]);
        headerRest = startHeader[index..];
    } else {
        platformShort = line;
    }
    if (std.meta.stringToEnum(platformSignatureHeader, platformShort)) |platf| {
        switch (platf) {
            .hub => {
                if (std.ascii.startsWithIgnoreCase(headerRest[1..], "Signature")) {
                    var signature: []const u8 = undefined;
                    var token: []const u8 = undefined;
                    if (std.ascii.startsWithIgnoreCase(headerRest[11..], "256")) {
                        signature = headerRest[16..];
                        if (std.ascii.startsWithIgnoreCase(signature, "sha256")) {
                            token = signature[7..];
                            sha256.create(&digest, json, env.TOKEN);
                            var hexBuf: [sha256.mac_length]u8 = undefined;
                            const calculateHex = try std.fmt.hexToBytes(&hexBuf, token[0..64]);
                            if (std.ascii.eqlIgnoreCase(&digest, calculateHex)) return .valid;
                            return .invalid;
                        }
                    }
                    signature = headerRest[12..];
                    if (std.ascii.startsWithIgnoreCase(signature, "sha1")) {
                        token = signature[5..];
                        const sha1 = std.crypto.auth.hmac.HmacSha1;
                        var digestSha1: [sha1.mac_length]u8 = undefined;
                        sha1.create(&digestSha1, json, env.TOKEN);
                        var hexBuf: [sha1.mac_length]u8 = undefined;
                        const calculateHex = try std.fmt.hexToBytes(&hexBuf, token[0..40]);
                        if (std.ascii.eqlIgnoreCase(&digestSha1, calculateHex)) return .valid;
                        return .invalid;
                    }
                    return .invalid;
                }
            },
            .gitlab => {
                const token: []const u8 = payloadInfo.?.signature[20..];
                const timestamp: []const u8 = payloadInfo.?.timestamp[17..];
                const id: []const u8 = payloadInfo.?.id[10..];

                var buffGl: [2048]u8 = undefined;

                const payload = try std.fmt.bufPrint(&buffGl, "{s}.{s}.{s}", .{ id, timestamp, json });

                sha256.create(&digest, payload, env.TOKEN);
                var hexBuf: [sha256.mac_length]u8 = undefined;
                const calculateHex = try std.fmt.hexToBytes(&hexBuf, token[0..64]);
                if (std.mem.eql(u8, &digest, calculateHex)) return .valid;
                return .invalid;
            },
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
    json: []const u8,
    payload: ?payloadGl,
    allocator: std.mem.Allocator,
    io: std.Io,
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
    switch (try handleSecret(line, env, json, payload)) {
        .valid => {
            std.debug.print("correct token\n", .{});
            const target = "~";
            _ = try utils.Container(allocator, io, env, target);
            return true;
        },
        .invalid => {
            try utils.SendJsonWrong(jsonResponde, w, req, out);
            return true;
        },
        .noAuth => {},
    }
    return false;
}

fn setJson() !WebhookPayload {}
