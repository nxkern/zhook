const std = @import("std");

pub const ENV = struct {
    URI: []const u8,
    TOKEN: []const u8,

    pub fn initEnv(envs: *std.process.Environ.Map) !?ENV {
        const uri_val = envs.get("URI_SERVER") orelse return null;
        const token_val = envs.get("TOKEN_CD") orelse return null;
        return ENV{
            .URI = uri_val,
            .TOKEN = token_val,
        };
    }
    pub fn getEnvs(self: *const ENV) ENV {
        return ENV{
            .URI = self.URI,
            .TOKEN = self.TOKEN,
        };
    }
};
