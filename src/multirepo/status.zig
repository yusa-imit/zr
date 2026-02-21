const std = @import("std");
const types = @import("../config/types.zig");
const RepoConfig = types.RepoConfig;
const RepoWorkspaceConfig = types.RepoWorkspaceConfig;

/// Git status for a single repository.
pub const GitStatus = struct {
    name: []const u8,
    exists: bool,
    branch: ?[]const u8 = null,
    ahead: u32 = 0,
    behind: u32 = 0,
    modified: u32 = 0,
    untracked: u32 = 0,
    clean: bool = true,

    pub fn deinit(self: *GitStatus, allocator: std.mem.Allocator) void {
        if (self.branch) |b| allocator.free(b);
    }
};

/// Get git status for all repositories in the workspace.
pub fn getRepoStatuses(allocator: std.mem.Allocator, config: *const RepoWorkspaceConfig) ![]GitStatus {
    var statuses = std.ArrayList(GitStatus){};
    errdefer {
        for (statuses.items) |*status| {
            var status_mut = status.*;
            status_mut.deinit(allocator);
        }
        statuses.deinit(allocator);
    }

    for (config.repos) |repo| {
        const status = try getRepoStatus(allocator, &repo);
        try statuses.append(allocator, status);
    }

    return try statuses.toOwnedSlice(allocator);
}

/// Get git status for a single repository.
fn getRepoStatus(allocator: std.mem.Allocator, repo: *const RepoConfig) !GitStatus {
    var status = GitStatus{
        .name = repo.name,
        .exists = false,
    };

    // Check if repo exists
    std.fs.cwd().access(repo.path, .{}) catch {
        return status;
    };
    status.exists = true;

    // Get current branch
    status.branch = getCurrentBranch(allocator, repo.path) catch null;

    // Get ahead/behind status
    const tracking = getTrackingStatus(allocator, repo.path) catch return status;
    status.ahead = tracking.ahead;
    status.behind = tracking.behind;

    // Get working tree status
    const tree_status = getWorkingTreeStatus(allocator, repo.path) catch return status;
    status.modified = tree_status.modified;
    status.untracked = tree_status.untracked;
    status.clean = tree_status.modified == 0 and tree_status.untracked == 0;

    return status;
}

fn getCurrentBranch(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    var argv = [_][]const u8{ "git", "-C", path, "branch", "--show-current" };

    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024);
    errdefer allocator.free(stdout);

    const term = try child.wait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                allocator.free(stdout);
                return error.GitBranchFailed;
            }
        },
        else => {
            allocator.free(stdout);
            return error.GitBranchFailed;
        },
    }

    const branch = std.mem.trim(u8, stdout, " \t\r\n");
    if (branch.len == 0) {
        allocator.free(stdout);
        return error.NoBranch;
    }

    // Trim and return owned slice
    const trimmed = try allocator.dupe(u8, branch);
    allocator.free(stdout);
    return trimmed;
}

const TrackingStatus = struct {
    ahead: u32,
    behind: u32,
};

fn getTrackingStatus(allocator: std.mem.Allocator, path: []const u8) !TrackingStatus {
    var argv = [_][]const u8{ "git", "-C", path, "rev-list", "--left-right", "--count", "@{u}...HEAD" };

    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024);
    defer allocator.free(stdout);

    _ = try child.wait();

    // Parse output: "behind\tahead\n"
    var it = std.mem.splitScalar(u8, std.mem.trim(u8, stdout, " \t\r\n"), '\t');
    const behind_str = it.next() orelse return TrackingStatus{ .ahead = 0, .behind = 0 };
    const ahead_str = it.next() orelse return TrackingStatus{ .ahead = 0, .behind = 0 };

    const behind = std.fmt.parseInt(u32, behind_str, 10) catch 0;
    const ahead = std.fmt.parseInt(u32, ahead_str, 10) catch 0;

    return TrackingStatus{ .ahead = ahead, .behind = behind };
}

const WorkingTreeStatus = struct {
    modified: u32,
    untracked: u32,
};

fn getWorkingTreeStatus(allocator: std.mem.Allocator, path: []const u8) !WorkingTreeStatus {
    var argv = [_][]const u8{ "git", "-C", path, "status", "--porcelain" };

    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(stdout);

    const term = try child.wait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) return error.GitStatusFailed;
        },
        else => return error.GitStatusFailed,
    }

    var modified: u32 = 0;
    var untracked: u32 = 0;

    var lines = std.mem.splitScalar(u8, stdout, '\n');
    while (lines.next()) |line| {
        if (line.len < 2) continue;
        const status_code = line[0..2];

        if (std.mem.eql(u8, status_code, "??")) {
            untracked += 1;
        } else if (status_code[0] != ' ' or status_code[1] != ' ') {
            modified += 1;
        }
    }

    return WorkingTreeStatus{ .modified = modified, .untracked = untracked };
}

// ========== TESTS ==========

test "getRepoStatus: current repo" {
    const allocator = std.testing.allocator;

    const repo = RepoConfig{
        .name = "zr",
        .url = "git@github.com:yusa-imit/zr.git",
        .path = ".",
        .branch = "main",
        .tags = &.{},
    };

    var status = try getRepoStatus(allocator, &repo);
    defer status.deinit(allocator);

    try std.testing.expect(status.exists);
    try std.testing.expect(status.branch != null);
}

test "getRepoStatus: non-existent repo" {
    const allocator = std.testing.allocator;

    const repo = RepoConfig{
        .name = "fake",
        .url = "git@github.com:fake/fake.git",
        .path = "/this/does/not/exist",
        .branch = "main",
        .tags = &.{},
    };

    var status = try getRepoStatus(allocator, &repo);
    defer status.deinit(allocator);

    try std.testing.expect(!status.exists);
    try std.testing.expect(status.branch == null);
}
