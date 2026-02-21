const std = @import("std");
const types = @import("types.zig");
const RepoConfig = types.RepoConfig;
const RepoWorkspaceConfig = types.RepoWorkspaceConfig;

/// Load and parse a zr-repos.toml file.
pub fn loadRepoConfig(allocator: std.mem.Allocator, path: []const u8) !RepoWorkspaceConfig {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(content);

    return try parseRepoConfig(allocator, content);
}

/// Parse zr-repos.toml content into RepoWorkspaceConfig (manual line-by-line parser).
pub fn parseRepoConfig(allocator: std.mem.Allocator, content: []const u8) !RepoWorkspaceConfig {
    var config = RepoWorkspaceConfig.init(allocator);
    errdefer config.deinit(allocator);

    var lines = std.mem.splitScalar(u8, content, '\n');

    // Workspace name
    var workspace_name: ?[]const u8 = null;

    // Current repo being built (non-owning slices)
    var current_repo_name: ?[]const u8 = null;
    var repo_url: ?[]const u8 = null;
    var repo_path: ?[]const u8 = null;
    var repo_branch: ?[]const u8 = "main";
    var repo_tags = std.ArrayList([]const u8){};
    defer repo_tags.deinit(allocator);

    // Accumulated repos (owned)
    var repos_list = std.ArrayList(RepoConfig).init(allocator);
    defer repos_list.deinit();

    // Current deps section parsing
    var in_deps_section = false;
    var current_dep_repo: ?[]const u8 = null;
    var dep_list = std.ArrayList([]const u8){};
    defer dep_list.deinit(allocator);

    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        // Section headers
        if (line[0] == '[') {
            // Flush pending repo
            if (current_repo_name) |name| {
                try flushRepo(allocator, &repos_list, name, repo_url orelse return error.MissingRepoUrl, repo_path orelse return error.MissingRepoPath, repo_branch orelse "main", &repo_tags);
                current_repo_name = null;
                repo_url = null;
                repo_path = null;
                repo_branch = "main";
                repo_tags.clearRetainingCapacity();
            }

            // Flush pending dep entry
            if (current_dep_repo) |dep_repo| {
                try flushDep(allocator, &config.dependencies, dep_repo, &dep_list);
                current_dep_repo = null;
                dep_list.clearRetainingCapacity();
            }

            if (std.mem.startsWith(u8, line, "[workspace]")) {
                in_deps_section = false;
                continue;
            } else if (std.mem.startsWith(u8, line, "[repos.")) {
                in_deps_section = false;
                const name_start = "[repos.".len;
                const name_end = std.mem.indexOf(u8, line[name_start..], "]") orelse continue;
                current_repo_name = line[name_start .. name_start + name_end];
            } else if (std.mem.startsWith(u8, line, "[deps]")) {
                in_deps_section = true;
            }
            continue;
        }

        // Key-value pairs
        const eq_idx = std.mem.indexOf(u8, line, "=") orelse continue;
        const key = std.mem.trim(u8, line[0..eq_idx], " \t");
        const val = std.mem.trim(u8, line[eq_idx + 1 ..], " \t");

        if (current_repo_name != null) {
            // Inside [repos.X]
            if (std.mem.eql(u8, key, "url")) {
                repo_url = stripQuotes(val);
            } else if (std.mem.eql(u8, key, "path")) {
                repo_path = stripQuotes(val);
            } else if (std.mem.eql(u8, key, "branch")) {
                repo_branch = stripQuotes(val);
            } else if (std.mem.eql(u8, key, "tags")) {
                try parseTags(&repo_tags, val);
            }
        } else if (in_deps_section) {
            // Inside [deps]
            if (current_dep_repo) |dep_repo| {
                if (!std.mem.eql(u8, dep_repo, key)) {
                    // New dep entry, flush previous
                    try flushDep(allocator, &config.dependencies, dep_repo, &dep_list);
                    dep_list.clearRetainingCapacity();
                    current_dep_repo = key;
                    try parseDeps(&dep_list, val);
                } else {
                    try parseDeps(&dep_list, val);
                }
            } else {
                current_dep_repo = key;
                try parseDeps(&dep_list, val);
            }
        } else {
            // Top-level or [workspace]
            if (std.mem.eql(u8, key, "name")) {
                workspace_name = stripQuotes(val);
            }
        }
    }

    // Flush final repo
    if (current_repo_name) |name| {
        try flushRepo(allocator, &repos_list, name, repo_url orelse return error.MissingRepoUrl, repo_path orelse return error.MissingRepoPath, repo_branch orelse "main", &repo_tags);
    }

    // Flush final dep
    if (current_dep_repo) |dep_repo| {
        try flushDep(allocator, &config.dependencies, dep_repo, &dep_list);
    }

    if (workspace_name) |name| {
        config.name = try allocator.dupe(u8, name);
    }

    config.repos = try repos_list.toOwnedSlice();

    return config;
}

fn stripQuotes(s: []const u8) []const u8 {
    var stripped = s;
    if (stripped.len >= 2 and stripped[0] == '"' and stripped[stripped.len - 1] == '"') {
        stripped = stripped[1 .. stripped.len - 1];
    }
    return stripped;
}

fn parseTags(tags: *std.ArrayList([]const u8), val: []const u8) !void {
    // Parse array: ["tag1", "tag2"]
    var trimmed = std.mem.trim(u8, val, " \t");
    if (trimmed.len < 2 or trimmed[0] != '[' or trimmed[trimmed.len - 1] != ']') return;
    trimmed = trimmed[1 .. trimmed.len - 1];

    var it = std.mem.splitScalar(u8, trimmed, ',');
    while (it.next()) |item| {
        const tag = stripQuotes(std.mem.trim(u8, item, " \t"));
        if (tag.len > 0) {
            try tags.append(tag);
        }
    }
}

fn parseDeps(deps: *std.ArrayList([]const u8), val: []const u8) !void {
    // Parse array: ["dep1", "dep2"]
    var trimmed = std.mem.trim(u8, val, " \t");
    if (trimmed.len < 2 or trimmed[0] != '[' or trimmed[trimmed.len - 1] != ']') return;
    trimmed = trimmed[1 .. trimmed.len - 1];

    var it = std.mem.splitScalar(u8, trimmed, ',');
    while (it.next()) |item| {
        const dep = stripQuotes(std.mem.trim(u8, item, " \t"));
        if (dep.len > 0) {
            try deps.append(dep);
        }
    }
}

fn flushRepo(allocator: std.mem.Allocator, repos: *std.ArrayList(RepoConfig), name: []const u8, url: []const u8, path: []const u8, branch: []const u8, tags: *std.ArrayList([]const u8)) !void {
    var repo = RepoConfig{
        .name = try allocator.dupe(u8, name),
        .url = try allocator.dupe(u8, url),
        .path = try allocator.dupe(u8, path),
        .branch = try allocator.dupe(u8, branch),
        .tags = &.{},
    };
    errdefer repo.deinit(allocator);

    // Dupe tags
    if (tags.items.len > 0) {
        const tags_owned = try allocator.alloc([]const u8, tags.items.len);
        for (tags.items, 0..) |tag, i| {
            tags_owned[i] = try allocator.dupe(u8, tag);
        }
        repo.tags = tags_owned;
    }

    try repos.append(repo);
}

fn flushDep(allocator: std.mem.Allocator, dependencies: *std.StringHashMap([][]const u8), repo_name: []const u8, deps: *std.ArrayList([]const u8)) !void {
    if (deps.items.len == 0) return;

    const deps_owned = try allocator.alloc([]const u8, deps.items.len);
    for (deps.items, 0..) |dep, i| {
        deps_owned[i] = try allocator.dupe(u8, dep);
    }

    try dependencies.put(try allocator.dupe(u8, repo_name), deps_owned);
}

// ========== TESTS ==========

test "parseRepoConfig: basic multi-repo config" {
    const allocator = std.testing.allocator;

    const content =
        \\[workspace]
        \\name = "acme-platform"
        \\
        \\[repos.api]
        \\url = "git@github.com:acme/api.git"
        \\path = "../api"
        \\branch = "main"
        \\tags = ["backend", "core"]
        \\
        \\[repos.frontend]
        \\url = "git@github.com:acme/frontend.git"
        \\path = "../frontend"
        \\
        \\[repos.shared-lib]
        \\url = "git@github.com:acme/shared-lib.git"
        \\path = "../shared-lib"
        \\tags = ["lib", "core"]
        \\
        \\[deps]
        \\api = ["shared-lib"]
        \\frontend = ["shared-lib", "api"]
    ;

    var config = try parseRepoConfig(allocator, content);
    defer config.deinit(allocator);

    // Check workspace name
    try std.testing.expect(config.name != null);
    try std.testing.expectEqualStrings("acme-platform", config.name.?);

    // Check repos count
    try std.testing.expectEqual(@as(usize, 3), config.repos.len);

    // Check api repo
    const api = findRepo(config.repos, "api").?;
    try std.testing.expectEqualStrings("git@github.com:acme/api.git", api.url);
    try std.testing.expectEqualStrings("../api", api.path);
    try std.testing.expectEqualStrings("main", api.branch);
    try std.testing.expectEqual(@as(usize, 2), api.tags.len);

    // Check frontend repo (branch default)
    const frontend = findRepo(config.repos, "frontend").?;
    try std.testing.expectEqualStrings("main", frontend.branch);
    try std.testing.expectEqual(@as(usize, 0), frontend.tags.len);

    // Check dependencies
    try std.testing.expectEqual(@as(usize, 2), config.dependencies.count());

    const api_deps = config.dependencies.get("api").?;
    try std.testing.expectEqual(@as(usize, 1), api_deps.len);
    try std.testing.expectEqualStrings("shared-lib", api_deps[0]);

    const frontend_deps = config.dependencies.get("frontend").?;
    try std.testing.expectEqual(@as(usize, 2), frontend_deps.len);
    try std.testing.expectEqualStrings("shared-lib", frontend_deps[0]);
    try std.testing.expectEqualStrings("api", frontend_deps[1]);
}

test "parseRepoConfig: minimal config" {
    const allocator = std.testing.allocator;

    const content =
        \\[repos.myrepo]
        \\url = "git@github.com:user/repo.git"
        \\path = "./repo"
    ;

    var config = try parseRepoConfig(allocator, content);
    defer config.deinit(allocator);

    try std.testing.expect(config.name == null);
    try std.testing.expectEqual(@as(usize, 1), config.repos.len);
    try std.testing.expectEqual(@as(usize, 0), config.dependencies.count());

    const repo = config.repos[0];
    try std.testing.expectEqualStrings("myrepo", repo.name);
    try std.testing.expectEqualStrings("git@github.com:user/repo.git", repo.url);
    try std.testing.expectEqualStrings("./repo", repo.path);
    try std.testing.expectEqualStrings("main", repo.branch); // default
}

test "parseRepoConfig: missing required field" {
    const allocator = std.testing.allocator;

    const content =
        \\[repos.myrepo]
        \\url = "git@github.com:user/repo.git"
    ;

    const result = parseRepoConfig(allocator, content);
    try std.testing.expectError(error.MissingRepoPath, result);
}

fn findRepo(repos: []RepoConfig, name: []const u8) ?RepoConfig {
    for (repos) |repo| {
        if (std.mem.eql(u8, repo.name, name)) return repo;
    }
    return null;
}
