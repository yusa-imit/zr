const std = @import("std");
const types = @import("../config/types.zig");
const loader = @import("../config/loader.zig");
const repos_mod = @import("../config/repos.zig");
const sync_mod = @import("sync.zig");

/// Directory for synthetic workspace storage (relative to HOME).
const SYNTHETIC_DIR = ".zr/synthetic-workspace";

/// Metadata for a synthetic workspace built from multi-repo.
pub const SyntheticWorkspace = struct {
    /// Name of the workspace (from zr-repos.toml [workspace] name).
    name: []const u8,
    /// Absolute path to the directory containing all synced repos.
    root_path: []const u8,
    /// List of member paths (relative to root_path).
    members: [][]const u8,
    /// Dependency map (project name -> list of dependencies).
    dependencies: std.StringHashMap([]const []const u8),

    pub fn deinit(self: *SyntheticWorkspace, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.root_path);
        for (self.members) |m| allocator.free(m);
        allocator.free(self.members);

        var it = self.dependencies.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |dep| allocator.free(dep);
            allocator.free(entry.value_ptr.*);
        }
        self.dependencies.deinit();
    }
};

/// Build a synthetic workspace from a multi-repo configuration.
/// This unifies all repos into a single workspace structure.
pub fn buildSyntheticWorkspace(
    allocator: std.mem.Allocator,
    repo_config_path: []const u8,
) !SyntheticWorkspace {
    // Load repo configuration
    var repo_config = try repos_mod.loadRepoConfig(allocator, repo_config_path);
    defer repo_config.deinit(allocator);

    // Sync all repos first
    const sync_options = sync_mod.SyncOptions{
        .clone_missing = false,
        .pull = true,
        .verbose = false,
    };

    const statuses = try sync_mod.syncRepos(allocator, &repo_config, sync_options);
    defer {
        for (statuses) |*status| {
            if (status.message) |msg| allocator.free(msg);
        }
        allocator.free(statuses);
    }

    // Check for failures
    for (statuses) |status| {
        if (status.state == .failed) {
            return error.SyncFailed;
        }
    }

    // Determine root path (parent of all repo paths)
    const root_path = try getRootPath(allocator, repo_config.repos);
    errdefer allocator.free(root_path);

    // Build member list (each repo is a member)
    var members = std.ArrayList([]const u8){};
    errdefer {
        for (members.items) |m| allocator.free(m);
        members.deinit(allocator);
    }

    for (repo_config.repos) |repo| {
        const member_path = try allocator.dupe(u8, repo.path);
        try members.append(allocator, member_path);
    }

    // Build dependency map
    var dependencies = std.StringHashMap([]const []const u8).init(allocator);
    errdefer {
        var it = dependencies.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |dep| allocator.free(dep);
            allocator.free(entry.value_ptr.*);
        }
        dependencies.deinit();
    }

    // Copy dependencies from repo config
    var dep_it = repo_config.dependencies.iterator();
    while (dep_it.next()) |entry| {
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        const deps_copy = try allocator.alloc([]const u8, entry.value_ptr.*.len);
        for (entry.value_ptr.*, 0..) |dep, i| {
            deps_copy[i] = try allocator.dupe(u8, dep);
        }
        try dependencies.put(key, deps_copy);
    }

    const workspace_name = if (repo_config.name) |name|
        try allocator.dupe(u8, name)
    else
        try allocator.dupe(u8, "synthetic-workspace");

    return SyntheticWorkspace{
        .name = workspace_name,
        .root_path = root_path,
        .members = try members.toOwnedSlice(allocator),
        .dependencies = dependencies,
    };
}

/// Save synthetic workspace metadata to cache.
pub fn saveSyntheticWorkspace(
    allocator: std.mem.Allocator,
    workspace: *const SyntheticWorkspace,
) !void {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ home, SYNTHETIC_DIR });
    defer allocator.free(cache_dir);

    // Create cache directory
    std.fs.cwd().makePath(cache_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Build metadata JSON
    const metadata_path = try std.fmt.allocPrint(allocator, "{s}/metadata.json", .{cache_dir});
    defer allocator.free(metadata_path);

    const file = try std.fs.cwd().createFile(metadata_path, .{});
    defer file.close();

    // Build JSON string
    var json = std.ArrayList(u8){};
    defer json.deinit(allocator);

    try json.appendSlice(allocator, "{");
    try json.writer(allocator).print("\"name\":\"{s}\",", .{workspace.name});
    try json.writer(allocator).print("\"root_path\":\"{s}\",", .{workspace.root_path});
    try json.appendSlice(allocator, "\"members\":[");
    for (workspace.members, 0..) |m, i| {
        if (i > 0) try json.appendSlice(allocator, ",");
        try json.writer(allocator).print("\"{s}\"", .{m});
    }
    try json.appendSlice(allocator, "]");
    try json.appendSlice(allocator, "}");

    try file.writeAll(json.items);
}

/// Load synthetic workspace metadata from cache.
pub fn loadSyntheticWorkspace(allocator: std.mem.Allocator) !?SyntheticWorkspace {
    const home = std.posix.getenv("HOME") orelse return null;
    const metadata_path = try std.fmt.allocPrint(allocator, "{s}/{s}/metadata.json", .{ home, SYNTHETIC_DIR });
    defer allocator.free(metadata_path);

    const file = std.fs.cwd().openFile(metadata_path, .{}) catch |err| {
        if (err == error.FileNotFound) return null;
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(content);

    // Simple JSON parsing (extract name, root_path, members)
    var workspace_name: ?[]const u8 = null;
    var root_path: ?[]const u8 = null;
    var members = std.ArrayList([]const u8){};
    defer {
        if (workspace_name == null) {
            for (members.items) |m| allocator.free(m);
            members.deinit(allocator);
        }
    }

    // Very basic JSON parsing (just for this simple structure)
    // "name":"value" extraction
    if (std.mem.indexOf(u8, content, "\"name\":\"")) |idx| {
        const start = idx + "\"name\":\"".len;
        if (std.mem.indexOf(u8, content[start..], "\"")) |end| {
            workspace_name = try allocator.dupe(u8, content[start .. start + end]);
        }
    }

    if (std.mem.indexOf(u8, content, "\"root_path\":\"")) |idx| {
        const start = idx + "\"root_path\":\"".len;
        if (std.mem.indexOf(u8, content[start..], "\"")) |end| {
            root_path = try allocator.dupe(u8, content[start .. start + end]);
        }
    }

    // Parse members array
    if (std.mem.indexOf(u8, content, "\"members\":[")) |idx| {
        const start = idx + "\"members\":[".len;
        if (std.mem.indexOf(u8, content[start..], "]")) |end| {
            const members_str = content[start .. start + end];
            var it = std.mem.splitScalar(u8, members_str, ',');
            while (it.next()) |item| {
                const trimmed = std.mem.trim(u8, item, " \t\r\n\"");
                if (trimmed.len > 0) {
                    try members.append(allocator, try allocator.dupe(u8, trimmed));
                }
            }
        }
    }

    if (workspace_name == null or root_path == null) {
        if (workspace_name) |name| allocator.free(name);
        if (root_path) |path| allocator.free(path);
        return null;
    }

    return SyntheticWorkspace{
        .name = workspace_name.?,
        .root_path = root_path.?,
        .members = try members.toOwnedSlice(allocator),
        .dependencies = std.StringHashMap([]const []const u8).init(allocator),
    };
}

/// Check if a synthetic workspace is currently active.
pub fn isSyntheticWorkspaceActive(allocator: std.mem.Allocator) !bool {
    var workspace = try loadSyntheticWorkspace(allocator);
    if (workspace) |*ws| {
        ws.deinit(allocator);
        return true;
    }
    return false;
}

/// Clear synthetic workspace cache.
pub fn clearSyntheticWorkspace(allocator: std.mem.Allocator) !void {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ home, SYNTHETIC_DIR });
    defer allocator.free(cache_dir);

    std.fs.cwd().deleteTree(cache_dir) catch |err| {
        if (err != error.FileNotFound) return err;
    };
}

/// Determine the root path (parent directory common to all repos).
/// For simplicity, we use the current working directory as root.
fn getRootPath(allocator: std.mem.Allocator, repos: []const types.RepoConfig) ![]const u8 {
    _ = repos; // Not used in this simple implementation
    // In a real implementation, you'd find the common prefix of all repo paths
    // For now, just use cwd
    return std.fs.cwd().realpathAlloc(allocator, ".") catch try allocator.dupe(u8, ".");
}

// ========== TESTS ==========

test "SyntheticWorkspace: init and deinit" {
    const allocator = std.testing.allocator;

    const members = try allocator.alloc([]const u8, 2);
    members[0] = try allocator.dupe(u8, "repo1");
    members[1] = try allocator.dupe(u8, "repo2");

    const deps = std.StringHashMap([]const []const u8).init(allocator);

    var workspace = SyntheticWorkspace{
        .name = try allocator.dupe(u8, "test"),
        .root_path = try allocator.dupe(u8, "/tmp"),
        .members = members,
        .dependencies = deps,
    };
    defer workspace.deinit(allocator);

    try std.testing.expectEqualStrings("test", workspace.name);
    try std.testing.expectEqualStrings("/tmp", workspace.root_path);
    try std.testing.expectEqual(@as(usize, 2), workspace.members.len);
}

test "isSyntheticWorkspaceActive: returns false when no cache" {
    const allocator = std.testing.allocator;

    // Clear any existing cache
    clearSyntheticWorkspace(allocator) catch {};

    const active = try isSyntheticWorkspaceActive(allocator);
    try std.testing.expect(!active);
}

test "loadSyntheticWorkspace: returns null when no cache" {
    const allocator = std.testing.allocator;

    // Clear any existing cache
    clearSyntheticWorkspace(allocator) catch {};

    const workspace = try loadSyntheticWorkspace(allocator);
    try std.testing.expect(workspace == null);
}
