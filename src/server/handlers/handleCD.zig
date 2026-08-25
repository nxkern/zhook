const std = @import("std");
const rootSrc = @import("~");
const utils = @import("utils/index.zig");

const customTypes = rootSrc.customTypes;

const headersSupporter = [_][]const u8{
    "X-Hub-Signature",
    "X-Hub-Signature-256",
    "X-Gitea-Signature",
    "X-Gogs-Signature",
    "X-Forgejo-Signature",
};

const headersGitlab = [_][]const u8{
    "webhook-id",
    "webhook-timestamp",
    "webhook-signature",
};

const gitlabBuildToken = struct {
    webhook_id: ?[]const u8,
    webhook_timestamp: ?[]const u8,

    const Self = @This();

    pub fn init(self: *Self, id: ?[]const u8, timestamp: ?[]const u8) void {
        self.webhook_id = id;
        self.webhook_timestamp = timestamp;
    }
};

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
    var it = req.iterateHeaders();
    var contentHeader: []const u8 = undefined;
    var idGitlab: []const u8 = undefined;
    var timestampGitlab: ?[]const u8 = null;

    // process headers
    {
        while (it.next()) |header| {
            var found: bool = false;
            for (headersSupporter) |head| {
                if (std.mem.eql(u8, header.name, head)) found = true;
                if (found) {
                    contentHeader = header.value;
                    break;
                }
                if (std.mem.eql(u8, header.name, "webhook_id")) idGitlab = header.value;
                if (std.mem.eql(u8, header.name, "webhook_timestamp")) timestampGitlab = header.value;
                if (std.mem.eql(u8, header.name, "webhook-timestamp ")) contentHeader = header.value;
            }
        }
    }

    var gitlab = gitlabBuildToken{
        .webhook_timestamp = null,
        .webhook_id = null,
    };

    if (!(timestampGitlab == null)) {
        gitlab.init(idGitlab, timestampGitlab);
    }

    var jsonResponde: types.json.tokenJson = undefined;

    var buffJson: [1024]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buffJson);
    var w: std.json.Stringify = .{ .writer = &out, .options = .{} };
    var value: bool = false;

    const data = req.readerExpectNone(&.{});
    const buffJsonData = try data.allocRemaining(allocator, .unlimited);
    defer allocator.free(buffJsonData);

    value = try processAuth(
        gitlab,
        contentHeader,
        env,
        &jsonResponde,
        &w,
        req,
        &out,
        buffJsonData,
        allocator,
        io,
    );
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
    gitlabData: ?gitlabBuildToken,
    valueHeader: []const u8,
    env: *const rootSrc.config.env.ENV,
    json: []const u8,
) !AuthResult {
    const sha256 = std.crypto.auth.hmac.sha2.HmacSha256;
    const sha1 = std.crypto.auth.hmac.HmacSha1;
    var token: ?[]const u8 = null;
    var valid: bool = false;
    if (std.ascii.startsWithIgnoreCase(valueHeader, "sha256")) token = valueHeader[7..];
    if (std.ascii.startsWithIgnoreCase(valueHeader, "sha1")) token = valueHeader[5..];
    if (!(gitlabData.?.webhook_id == null) and std.ascii.startsWithIgnoreCase(valueHeader, "whsec_"))
        token = valueHeader[5..];
    if (token == null) token = valueHeader;

    // Process hash sha256
    {
        std.debug.print("hola sha256", .{});
        var digest: [sha256.mac_length]u8 = undefined;
        sha256.create(&digest, json, env.TOKEN);
        var hexBuf: [sha256.mac_length]u8 = undefined;
        const calculateHex = try std.fmt.hexToBytes(&hexBuf, token.?);
        if (std.ascii.eqlIgnoreCase(&digest, calculateHex)) valid = true;
    }

    // Process hash sha1
    if (!valid) {
        std.debug.print("hola sha1", .{});
        var digest: [sha1.mac_length]u8 = undefined;
        sha1.create(&digest, json, env.TOKEN);
        var hexBuf: [sha1.mac_length]u8 = undefined;
        const calculateHex = try std.fmt.hexToBytes(&hexBuf, token.?);
        if (std.ascii.eqlIgnoreCase(&digest, calculateHex)) valid = true;
    }

    // process hash gitlab sha256
    if (!valid) {
        var bufMessage: [300]u8 = undefined;
        const message = try std.fmt.bufPrint(&bufMessage, "{?s}.{?s}.{s}", .{gitlabData.?.webhook_id, gitlabData.?.webhook_timestamp, json});
        var digest: [sha256.mac_length]u8 = undefined;
         sha256.create(&digest, message, env.TOKEN);
        var hexBuf: [sha256.mac_length]u8 = undefined;
        const calculateHex = try std.fmt.hexToBytes(&hexBuf, token.?);
        if (std.ascii.eqlIgnoreCase(&digest, calculateHex)) valid = true;
    }

    if (valid) return .valid;
    if(!valid) return .invalid;
    return .noAuth;
}

fn processAuth(
    gitlabData: ?gitlabBuildToken,
    valueHeader: []const u8,
    env: *const rootSrc.config.env.ENV,
    jsonResponde: *types.json.tokenJson,
    w: *std.json.Stringify,
    req: *std.http.Server.Request,
    out: *std.Io.Writer,
    json: []const u8,
    allocator: std.mem.Allocator,
    io: std.Io,
) !bool {
    switch (try handleBearer(valueHeader, env)) {
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
    switch (try handleSecret(
        gitlabData,
        valueHeader,
        env,
        json,
    )) {
        .valid => {
            std.debug.print("correct token\n", .{});
            jsonResponde.* = types.json.tokenJson{
                .data = "correct token, process up"
            };
            

            const target = try setJson(allocator, json);
            defer allocator.free(target);
            try w.*.beginObject();
            inline for (@typeInfo(@TypeOf(jsonResponde.*)).@"struct".fields) |key| {
                try w.*.objectField(key.name);
                if(@field(jsonResponde.*, key.name)) |_| {} else |err| {
                    try w.*.print("{s}", .{@errorName(err)});
                }
            }
            try w.endObject();
            try req.*.respond(out.*.buffered(),.{
                .status = .accepted,
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "application/json"}
                },
            });

            try utils.Container(allocator, io, env, target);
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

fn setJson(allocator: std.mem.Allocator, json: []const u8) ![]u8 {
    const parsedGt = try std.json.parseFromSlice(
        customTypes.json.PayloadGitea,
        allocator,
        json,
        .{
            .ignore_unknown_fields = true,
        },
    );
    defer parsedGt.deinit();
    const resultGt: customTypes.json.PayloadGitea = parsedGt.value;
    if (resultGt.repository.owner.login_name != null) {
        const repoName: []u8 = try allocator.dupe(u8, resultGt.repository.name);
        return repoName;
    }
    parsedGt.deinit();
    const parsedGh = try std.json.parseFromSlice(
        customTypes.json.PayloadGithub,
        allocator,
        json,
        .{
            .ignore_unknown_fields = true,
        },
    );
    defer parsedGh.deinit();
    const resultGh: customTypes.json.PayloadGithub = parsedGh.value;
    const repoName: []u8 = try allocator.dupe(u8, resultGh.repository.name);
    return repoName;
}
