const std = @import("std");
const types = @import("../config/types.zig");
const RepoWorkspaceConfig = types.RepoWorkspaceConfig;
const repo_graph = @import("graph.zig");
const RepoGraph = repo_graph.RepoGraph;
const loader = @import("../config/loader.zig");
const exec = @import("../exec/scheduler.zig");
const color = @import("../output/color.zig");

/// Options for cross-repo task execution.
pub const RunOptions = struct {
    /// Only run on affected repositories (git diff-based).
    affected: bool = false,
    /// Base reference for affected detection.
    affected_base: ?[]const u8 = null,
    /// Filter to specific repositories (comma-separated names).
    repos: ?[]const u8 = null,
    /// Filter by tags (comma-separated).
    tags: ?[]const u8 = null,
    /// Verbose output.
    verbose: bool = false,
    /// Number of parallel jobs (0 = auto).
    jobs: usize = 0,
    /// No color output.
    no_color: bool = false,
    /// Dry run (show execution plan only).
    dry_run: bool = false,
};

/// Result of running a task in a repository.
pub const RepoTaskResult = struct {
    /// Repository name.
    repo_name: []const u8,
    /// Task name.
    task_name: []const u8,
    /// Success status.
    success: bool,
    /// Duration in milliseconds.
    duration_ms: u64,
    /// Error message (if failed).
    error_message: ?[]const u8,

    pub fn deinit(self: *RepoTaskResult, allocator: std.mem.Allocator) void {
        allocator.free(self.repo_name);
        allocator.free(self.task_name);
        if (self.error_message) |msg| allocator.free(msg);
    }
};

/// Run a task across multiple repositories.
///
/// This function:
/// 1. Loads the multi-repo configuration
/// 2. Builds the cross-repo dependency graph
/// 3. Filters repositories based on options (affected, repos, tags)
/// 4. Executes the task in topological order (respecting dependencies)
///
/// Returns a list of results (one per repository).
pub fn runTaskAcrossRepos(
    allocator: std.mem.Allocator,
    workspace_config: *const RepoWorkspaceConfig,
    task_name: []const u8,
    options: RunOptions,
    w: anytype,
    ew: anytype,
) ![]RepoTaskResult {
    // Build dependency graph
    var graph = try repo_graph.buildRepoGraph(allocator, workspace_config);
    defer graph.deinit();

    // Get execution order (topological sort)
    const sorted_repos = try repo_graph.topologicalSort(&graph, allocator);
    defer {
        for (sorted_repos) |name| allocator.free(name);
        allocator.free(sorted_repos);
    }

    // Filter repositories based on options
    var filtered_repos = std.ArrayList([]const u8){};
    defer filtered_repos.deinit(allocator);

    for (sorted_repos) |repo_name| {
        if (try shouldRunInRepo(allocator, &graph, repo_name, options)) {
            try filtered_repos.append(allocator, repo_name);
        }
    }

    if (filtered_repos.items.len == 0) {
        try w.writeAll("No repositories matched the filter criteria\n");
        return try allocator.alloc(RepoTaskResult, 0);
    }

    // Print execution plan
    const use_color = !options.no_color;
    if (options.verbose or options.dry_run) {
        if (use_color) try w.writeAll(color.Code.cyan);
        try w.print("Execution order ({d} repositories):\n", .{filtered_repos.items.len});
        if (use_color) try w.writeAll(color.Code.reset);

        for (filtered_repos.items, 0..) |repo_name, i| {
            if (use_color) try w.writeAll(color.Code.dim);
            try w.print("  {d}. {s}\n", .{ i + 1, repo_name });
            if (use_color) try w.writeAll(color.Code.reset);
        }
        try w.writeAll("\n");
    }

    if (options.dry_run) {
        return try allocator.alloc(RepoTaskResult, 0);
    }

    // Execute task in each repository
    var results = std.ArrayList(RepoTaskResult){};
    errdefer {
        for (results.items) |*r| r.deinit(allocator);
        results.deinit(allocator);
    }

    for (filtered_repos.items) |repo_name| {
        const node = graph.nodes.get(repo_name) orelse continue;

        if (options.verbose) {
            if (use_color) try w.writeAll(color.Code.blue);
            try w.print("Running task '{s}' in repository '{s}'...\n", .{ task_name, repo_name });
            if (use_color) try w.writeAll(color.Code.reset);
        }

        const result = try runTaskInRepo(
            allocator,
            node.path,
            task_name,
            options,
            w,
            ew,
        );

        if (result.success) {
            if (use_color) try w.writeAll(color.Code.green);
            try w.print("✓ {s}/{s} completed in {d}ms\n", .{ repo_name, task_name, result.duration_ms });
            if (use_color) try w.writeAll(color.Code.reset);
        } else {
            if (use_color) try w.writeAll(color.Code.red);
            try w.print("✗ {s}/{s} failed: {s}\n", .{
                repo_name,
                task_name,
                result.error_message orelse "unknown error",
            });
            if (use_color) try w.writeAll(color.Code.reset);
        }

        try results.append(allocator, result);
    }

    return try results.toOwnedSlice(allocator);
}

/// Check if a repository has git changes compared to a base reference.
fn hasGitChanges(
    allocator: std.mem.Allocator,
    repo_path: []const u8,
    base_ref: []const u8,
) !bool {
    // Check for uncommitted changes first (working directory + staged)
    {
        const args = [_][]const u8{ "git", "diff", "--quiet" };
        var child = std.process.Child.init(&args, allocator);
        child.cwd = repo_path;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        child.spawn() catch return false;
        const term = child.wait() catch return false;
        if (term == .Exited and term.Exited == 1) {
            return true; // Has uncommitted changes
        }
    }

    // Check for staged changes
    {
        const args = [_][]const u8{ "git", "diff", "--quiet", "--cached" };
        var child = std.process.Child.init(&args, allocator);
        child.cwd = repo_path;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        child.spawn() catch return false;
        const term = child.wait() catch return false;
        if (term == .Exited and term.Exited == 1) {
            return true; // Has staged changes
        }
    }

    // Check for committed changes between base_ref and HEAD
    // Only check if base_ref is not HEAD (to avoid HEAD...HEAD comparison)
    if (!std.mem.eql(u8, base_ref, "HEAD")) {
        const diff_spec = try std.fmt.allocPrint(allocator, "{s}...HEAD", .{base_ref});
        defer allocator.free(diff_spec);

        const args = [_][]const u8{ "git", "diff", "--quiet", diff_spec };
        var child = std.process.Child.init(&args, allocator);
        child.cwd = repo_path;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        child.spawn() catch return false;
        const term = child.wait() catch return false;
        if (term == .Exited and term.Exited == 1) {
            return true; // Has committed changes
        }
    }

    return false;
}

/// Determine if a task should run in a specific repository.
fn shouldRunInRepo(
    allocator: std.mem.Allocator,
    graph: *const RepoGraph,
    repo_name: []const u8,
    options: RunOptions,
) !bool {
    const node = graph.nodes.get(repo_name) orelse return false;

    // Filter by explicit repo list
    if (options.repos) |repos_str| {
        var found = false;
        var iter = std.mem.tokenizeScalar(u8, repos_str, ',');
        while (iter.next()) |repo| {
            if (std.mem.eql(u8, std.mem.trim(u8, repo, " "), repo_name)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }

    // Filter by tags
    if (options.tags) |tags_str| {
        var required_tags = std.ArrayList([]const u8){};
        defer required_tags.deinit(allocator);

        var iter = std.mem.tokenizeScalar(u8, tags_str, ',');
        while (iter.next()) |tag| {
            try required_tags.append(allocator, std.mem.trim(u8, tag, " "));
        }

        // Check if repo has at least one of the required tags
        var has_tag = false;
        for (node.tags) |repo_tag| {
            for (required_tags.items) |req_tag| {
                if (std.mem.eql(u8, repo_tag, req_tag)) {
                    has_tag = true;
                    break;
                }
            }
            if (has_tag) break;
        }
        if (!has_tag) return false;
    }

    // Filter by affected (git diff-based)
    if (options.affected) {
        const base_ref = options.affected_base orelse "origin/main";

        // Get changed files in this repo
        const repo_path = node.path;
        const changed = try hasGitChanges(allocator, repo_path, base_ref);

        return changed;
    }

    return true;
}

/// Run a task in a single repository.
fn runTaskInRepo(
    allocator: std.mem.Allocator,
    repo_path: []const u8,
    task_name: []const u8,
    options: RunOptions,
    w: anytype,
    ew: anytype,
) !RepoTaskResult {
    _ = options;
    _ = w;
    _ = ew;
    const start_time = std.time.milliTimestamp();

    // Load config from repo
    const config_path = try std.fs.path.join(allocator, &.{ repo_path, "zr.toml" });
    defer allocator.free(config_path);

    var config = loader.loadFromFile(allocator, config_path) catch |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "failed to load config: {s}", .{@errorName(err)});
        return RepoTaskResult{
            .repo_name = try allocator.dupe(u8, std.fs.path.basename(repo_path)),
            .task_name = try allocator.dupe(u8, task_name),
            .success = false,
            .duration_ms = @intCast(std.time.milliTimestamp() - start_time),
            .error_message = error_msg,
        };
    };
    defer config.deinit();

    // Find task in config
    const task = config.tasks.get(task_name) orelse {
        const error_msg = try std.fmt.allocPrint(allocator, "task '{s}' not found", .{task_name});
        return RepoTaskResult{
            .repo_name = try allocator.dupe(u8, std.fs.path.basename(repo_path)),
            .task_name = try allocator.dupe(u8, task_name),
            .success = false,
            .duration_ms = @intCast(std.time.milliTimestamp() - start_time),
            .error_message = error_msg,
        };
    };

    // Execute task using scheduler
    const cwd = try std.fs.path.resolve(allocator, &.{repo_path});
    defer allocator.free(cwd);

    var process = std.process.Child.init(&.{ "sh", "-c", task.cmd }, allocator);
    process.cwd = cwd;

    // Set environment variables
    var maybe_env_map: ?std.process.EnvMap = null;
    defer if (maybe_env_map) |*m| m.deinit();

    if (task.env.len > 0) {
        maybe_env_map = try std.process.getEnvMap(allocator);

        // Add task env vars
        for (task.env) |kv| {
            try maybe_env_map.?.put(kv[0], kv[1]);
        }

        process.env_map = &maybe_env_map.?;
    }

    // Capture stdout/stderr
    process.stdout_behavior = .Pipe;
    process.stderr_behavior = .Pipe;

    const spawn_result = process.spawn();
    if (spawn_result) |_| {
        // Wait for completion
        const term = process.wait() catch |err| {
            const error_msg = try std.fmt.allocPrint(allocator, "wait failed: {s}", .{@errorName(err)});
            return RepoTaskResult{
                .repo_name = try allocator.dupe(u8, std.fs.path.basename(repo_path)),
                .task_name = try allocator.dupe(u8, task_name),
                .success = false,
                .duration_ms = @intCast(std.time.milliTimestamp() - start_time),
                .error_message = error_msg,
            };
        };

        const success = switch (term) {
            .Exited => |code| code == 0,
            else => false,
        };

        const duration_ms: u64 = @intCast(std.time.milliTimestamp() - start_time);

        return RepoTaskResult{
            .repo_name = try allocator.dupe(u8, std.fs.path.basename(repo_path)),
            .task_name = try allocator.dupe(u8, task_name),
            .success = success,
            .duration_ms = duration_ms,
            .error_message = if (!success) try std.fmt.allocPrint(allocator, "exit code: {}", .{term}) else null,
        };
    } else |err| {
        const error_msg = try std.fmt.allocPrint(allocator, "spawn failed: {s}", .{@errorName(err)});
        return RepoTaskResult{
            .repo_name = try allocator.dupe(u8, std.fs.path.basename(repo_path)),
            .task_name = try allocator.dupe(u8, task_name),
            .success = false,
            .duration_ms = @intCast(std.time.milliTimestamp() - start_time),
            .error_message = error_msg,
        };
    }
}

// ============================================================================
// TESTS
// ============================================================================

test "RunOptions defaults" {
    const options = RunOptions{};
    try std.testing.expectEqual(false, options.affected);
    try std.testing.expectEqual(null, options.affected_base);
    try std.testing.expectEqual(null, options.repos);
    try std.testing.expectEqual(null, options.tags);
    try std.testing.expectEqual(false, options.verbose);
    try std.testing.expectEqual(@as(usize, 0), options.jobs);
}

test "shouldRunInRepo - no filters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var graph = RepoGraph.init(allocator);
    defer graph.deinit();

    const node = repo_graph.RepoGraphNode{
        .name = try allocator.dupe(u8, "test-repo"),
        .dependencies = &.{},
        .dependents = &.{},
        .tags = &.{},
        .path = try allocator.dupe(u8, "/tmp/test-repo"),
    };
    try graph.nodes.put(node.name, node);

    const options = RunOptions{};
    const result = try shouldRunInRepo(allocator, &graph, "test-repo", options);
    try std.testing.expectEqual(true, result);
}

test "shouldRunInRepo - filter by repo name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var graph = RepoGraph.init(allocator);
    defer graph.deinit();

    const node1 = repo_graph.RepoGraphNode{
        .name = try allocator.dupe(u8, "repo-a"),
        .dependencies = &.{},
        .dependents = &.{},
        .tags = &.{},
        .path = try allocator.dupe(u8, "/tmp/repo-a"),
    };
    try graph.nodes.put(node1.name, node1);

    const node2 = repo_graph.RepoGraphNode{
        .name = try allocator.dupe(u8, "repo-b"),
        .dependencies = &.{},
        .dependents = &.{},
        .tags = &.{},
        .path = try allocator.dupe(u8, "/tmp/repo-b"),
    };
    try graph.nodes.put(node2.name, node2);

    var options = RunOptions{ .repos = "repo-a,repo-b" };

    const result_a = try shouldRunInRepo(allocator, &graph, "repo-a", options);
    try std.testing.expectEqual(true, result_a);

    const result_b = try shouldRunInRepo(allocator, &graph, "repo-b", options);
    try std.testing.expectEqual(true, result_b);

    // Test exclusion
    options.repos = "repo-a";
    const result_excluded = try shouldRunInRepo(allocator, &graph, "repo-b", options);
    try std.testing.expectEqual(false, result_excluded);
}

test "shouldRunInRepo - filter by tags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var graph = RepoGraph.init(allocator);
    defer graph.deinit();

    var tags_backend = try allocator.alloc([]const u8, 1);
    tags_backend[0] = try allocator.dupe(u8, "backend");

    const node1 = repo_graph.RepoGraphNode{
        .name = try allocator.dupe(u8, "api"),
        .dependencies = &.{},
        .dependents = &.{},
        .tags = tags_backend,
        .path = try allocator.dupe(u8, "/tmp/api"),
    };
    try graph.nodes.put(node1.name, node1);

    var tags_frontend = try allocator.alloc([]const u8, 1);
    tags_frontend[0] = try allocator.dupe(u8, "frontend");

    const node2 = repo_graph.RepoGraphNode{
        .name = try allocator.dupe(u8, "web"),
        .dependencies = &.{},
        .dependents = &.{},
        .tags = tags_frontend,
        .path = try allocator.dupe(u8, "/tmp/web"),
    };
    try graph.nodes.put(node2.name, node2);

    const options = RunOptions{ .tags = "backend" };

    const result_api = try shouldRunInRepo(allocator, &graph, "api", options);
    try std.testing.expectEqual(true, result_api);

    const result_web = try shouldRunInRepo(allocator, &graph, "web", options);
    try std.testing.expectEqual(false, result_web);
}

test "hasGitChanges - repo with changes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create a temporary directory for testing
    const tmp_dir = std.testing.tmpDir(.{});
    var dir = tmp_dir.dir;

    // Initialize git repo
    {
        const args = [_][]const u8{ "git", "init" };
        var child = std.process.Child.init(&args, allocator);
        var buf: [1024]u8 = undefined;
        const path = try dir.realpath(".", &buf);
        child.cwd = path;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        try child.spawn();
        _ = try child.wait();
    }

    // Configure git user for this repo
    {
        const args = [_][]const u8{ "git", "config", "user.name", "Test User" };
        var child = std.process.Child.init(&args, allocator);
        var buf: [1024]u8 = undefined;
        const path = try dir.realpath(".", &buf);
        child.cwd = path;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        try child.spawn();
        _ = try child.wait();
    }
    {
        const args = [_][]const u8{ "git", "config", "user.email", "test@example.com" };
        var child = std.process.Child.init(&args, allocator);
        var buf: [1024]u8 = undefined;
        const path = try dir.realpath(".", &buf);
        child.cwd = path;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        try child.spawn();
        _ = try child.wait();
    }

    // Create initial commit
    {
        const file = try dir.createFile("test.txt", .{});
        defer file.close();
        try file.writeAll("initial");
    }
    {
        const args = [_][]const u8{ "git", "add", "test.txt" };
        var child = std.process.Child.init(&args, allocator);
        var buf: [1024]u8 = undefined;
        const path = try dir.realpath(".", &buf);
        child.cwd = path;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        try child.spawn();
        _ = try child.wait();
    }
    {
        const args = [_][]const u8{ "git", "commit", "-m", "initial" };
        var child = std.process.Child.init(&args, allocator);
        var buf: [1024]u8 = undefined;
        const path = try dir.realpath(".", &buf);
        child.cwd = path;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        try child.spawn();
        _ = try child.wait();
    }

    // Make a change
    {
        const file = try dir.createFile("test.txt", .{});
        defer file.close();
        try file.writeAll("changed");
    }

    var buf: [1024]u8 = undefined;
    const path = try dir.realpath(".", &buf);

    // Check if there are changes (should be true)
    const has_changes = try hasGitChanges(allocator, path, "HEAD");
    try std.testing.expectEqual(true, has_changes);
}

test "hasGitChanges - repo without changes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create a temporary directory for testing
    const tmp_dir = std.testing.tmpDir(.{});
    var dir = tmp_dir.dir;

    // Initialize git repo
    {
        const args = [_][]const u8{ "git", "init" };
        var child = std.process.Child.init(&args, allocator);
        var buf: [1024]u8 = undefined;
        const path = try dir.realpath(".", &buf);
        child.cwd = path;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        try child.spawn();
        _ = try child.wait();
    }

    // Configure git user for this repo
    {
        const args = [_][]const u8{ "git", "config", "user.name", "Test User" };
        var child = std.process.Child.init(&args, allocator);
        var buf: [1024]u8 = undefined;
        const path = try dir.realpath(".", &buf);
        child.cwd = path;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        try child.spawn();
        _ = try child.wait();
    }
    {
        const args = [_][]const u8{ "git", "config", "user.email", "test@example.com" };
        var child = std.process.Child.init(&args, allocator);
        var buf: [1024]u8 = undefined;
        const path = try dir.realpath(".", &buf);
        child.cwd = path;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        try child.spawn();
        _ = try child.wait();
    }

    // Create initial commit
    {
        const file = try dir.createFile("test.txt", .{});
        defer file.close();
        try file.writeAll("initial");
    }
    {
        const args = [_][]const u8{ "git", "add", "test.txt" };
        var child = std.process.Child.init(&args, allocator);
        var buf: [1024]u8 = undefined;
        const path = try dir.realpath(".", &buf);
        child.cwd = path;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        try child.spawn();
        _ = try child.wait();
    }
    {
        const args = [_][]const u8{ "git", "commit", "-m", "initial" };
        var child = std.process.Child.init(&args, allocator);
        var buf: [1024]u8 = undefined;
        const path = try dir.realpath(".", &buf);
        child.cwd = path;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        try child.spawn();
        _ = try child.wait();
    }

    var buf: [1024]u8 = undefined;
    const path = try dir.realpath(".", &buf);

    // Check if there are changes (should be false - no changes made)
    const has_changes = try hasGitChanges(allocator, path, "HEAD");
    try std.testing.expectEqual(false, has_changes);
}
