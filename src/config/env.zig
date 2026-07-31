const std = @import("std");

pub const ENV = struct {
    URI: []const u8,
    TOKEN: []const u8,

    const Self = @This();

    pub fn initEnv(envs: *std.process.Environ.Map) ?Self {
        const uri_val = envs.get("URI_SERVER") orelse return null;
        const token_val = envs.get("TOKEN_CD") orelse return null;
        return Self{
            .URI = uri_val,
            .TOKEN = token_val,
        };
    }
    pub fn getEnvs(self: *const Self) Self {
        return Self{
            .URI = self.URI,
            .TOKEN = self.TOKEN,
        };
    }
};
