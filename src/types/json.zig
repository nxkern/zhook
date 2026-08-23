pub const tokenJson = struct {
    data: error{ incorrectToken, notFoundToken }![]const u8,
};

pub const PayloadGitea = struct {
    repository: repositoryGitea,
};

const repositoryGitea = struct {
    id: u64,
    owner: ownerGitea,
    name: []u8,
    full_name: []const u8,
    description: []const u8,
    private: bool,
    language: []const u8,
    html_url: []const u8,
    clone_url: []const u8,
    default_branch: []const u8,
    start_count: u32,
    forks_count: u32,
    open_issues_count: u16,
    release_counter: u32,
};

const ownerGitea = struct {
    login_name: ?[]const u8,
};

pub const PayloadGithub = struct {
    repository: repositoryGithub,
};

const repositoryGithub = struct {
    id: u64,
    name: []u8,
    full_name: []const u8,
    private: bool,
    html_url: []const u8,
};
