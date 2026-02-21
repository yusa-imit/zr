const std = @import("std");
const types = @import("../config/types.zig");
const RepoConfig = types.RepoConfig;
const RepoWorkspaceConfig = types.RepoWorkspaceConfig;

/// Sync options for multi-repo operations.
pub const SyncOptions = struct {
    /// Only clone repos that are not already checked out.
    clone_missing: bool = false,
    /// Pull updates for existing repos.
    pull: bool = true,
    /// Verbose output.
    verbose: bool = false,
};

/// Sync status for a single repository.
pub const RepoStatus = struct {
    name: []const u8,
    state: enum {
        cloned, // Successfully cloned
        pulled, // Successfully pulled
        unchanged, // Already up-to-date
        skipped, // Skipped (already exists and clone_missing=true)
        failed, // Operation failed
    },
    message: ?[]const u8 = null,
};

/// Sync all repositories in the workspace.
pub fn syncRepos(allocator: std.mem.Allocator, config: *const RepoWorkspaceConfig, options: SyncOptions) ![]RepoStatus {
    var statuses = std.ArrayList(RepoStatus){};
    errdefer {
        for (statuses.items) |*status| {
            if (status.message) |msg| allocator.free(msg);
        }
        statuses.deinit(allocator);
    }

    for (config.repos) |repo| {
        const status = try syncSingleRepo(allocator, &repo, options);
        try statuses.append(allocator, status);
    }

    return try statuses.toOwnedSlice(allocator);
}

/// Sync a single repository (clone or pull).
fn syncSingleRepo(allocator: std.mem.Allocator, repo: *const RepoConfig, options: SyncOptions) !RepoStatus {
    // Check if repo already exists
    const exists = checkRepoExists(repo.path);

    if (exists and options.clone_missing) {
        return RepoStatus{
            .name = repo.name,
            .state = .skipped,
            .message = try allocator.dupe(u8, "already exists, skipped"),
        };
    }

    if (!exists) {
        // Clone the repository
        if (options.verbose) {
            std.debug.print("Cloning {s} from {s} to {s}...\n", .{ repo.name, repo.url, repo.path });
        }

        const result = cloneRepo(allocator, repo);
        return if (result) |_|
            RepoStatus{
                .name = repo.name,
                .state = .cloned,
                .message = try allocator.dupe(u8, "cloned successfully"),
            }
        else |err|
            RepoStatus{
                .name = repo.name,
                .state = .failed,
                .message = try std.fmt.allocPrint(allocator, "clone failed: {s}", .{@errorName(err)}),
            };
    } else if (options.pull) {
        // Pull updates
        if (options.verbose) {
            std.debug.print("Pulling {s} in {s}...\n", .{ repo.name, repo.path });
        }

        const result = pullRepo(allocator, repo);
        return if (result) |pulled|
            if (pulled)
                RepoStatus{
                    .name = repo.name,
                    .state = .pulled,
                    .message = try allocator.dupe(u8, "pulled successfully"),
                }
            else
                RepoStatus{
                    .name = repo.name,
                    .state = .unchanged,
                    .message = try allocator.dupe(u8, "already up-to-date"),
                }
        else |err|
            RepoStatus{
                .name = repo.name,
                .state = .failed,
                .message = try std.fmt.allocPrint(allocator, "pull failed: {s}", .{@errorName(err)}),
            };
    }

    return RepoStatus{
        .name = repo.name,
        .state = .unchanged,
        .message = try allocator.dupe(u8, "no operation"),
    };
}

fn checkRepoExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn cloneRepo(allocator: std.mem.Allocator, repo: *const RepoConfig) !void {
    var argv = std.ArrayList([]const u8){};
    defer argv.deinit(allocator);

    try argv.append(allocator, "git");
    try argv.append(allocator, "clone");
    try argv.append(allocator, "-b");
    try argv.append(allocator, repo.branch);
    try argv.append(allocator, repo.url);
    try argv.append(allocator, repo.path);

    var child = std.process.Child.init(argv.items, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    const term = try child.spawnAndWait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) return error.GitCloneFailed;
        },
        else => return error.GitCloneFailed,
    }
}

fn pullRepo(allocator: std.mem.Allocator, repo: *const RepoConfig) !bool {
    var argv = std.ArrayList([]const u8){};
    defer argv.deinit(allocator);

    try argv.append(allocator, "git");
    try argv.append(allocator, "-C");
    try argv.append(allocator, repo.path);
    try argv.append(allocator, "pull");
    try argv.append(allocator, "origin");
    try argv.append(allocator, repo.branch);

    var child = std.process.Child.init(argv.items, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(stdout);

    const term = try child.wait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) return error.GitPullFailed;
            // Check if already up-to-date
            return !std.mem.containsAtLeast(u8, stdout, 1, "Already up to date");
        },
        else => return error.GitPullFailed,
    }
}

// ========== TESTS ==========

test "checkRepoExists: existing directory" {
    const exists = checkRepoExists(".");
    try std.testing.expect(exists);
}

test "checkRepoExists: non-existing directory" {
    const exists = checkRepoExists("/this/does/not/exist/hopefully");
    try std.testing.expect(!exists);
}
