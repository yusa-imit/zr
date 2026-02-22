const std = @import("std");
const types = @import("types.zig");
const config_types = @import("../config/types.zig");
const config_loader = @import("../config/loader.zig");
const platform = @import("../util/platform.zig");

const ProjectContext = types.ProjectContext;
const PackageNode = types.PackageNode;
const PackageTaskInfo = types.PackageTaskInfo;
const TaskInfo = types.TaskInfo;
const ToolchainInfo = types.ToolchainInfo;

/// Generate project context metadata
pub fn generateContext(allocator: std.mem.Allocator, scope: ?[]const u8) !ProjectContext {
    var ctx = ProjectContext.init(allocator);
    errdefer ctx.deinit();

    // Load config
    var config = config_loader.loadFromFile(allocator, "zr.toml") catch |err| {
        std.debug.print("warning: failed to load zr.toml: {s}\n", .{@errorName(err)});
        return ctx;
    };
    defer config.deinit();

    // Collect project graph
    try collectProjectGraph(allocator, &ctx.project_graph, &config, scope);

    // Collect task catalog
    try collectTaskCatalog(allocator, &ctx, &config, scope);

    // Collect toolchain info
    try collectToolchains(allocator, &ctx, &config);

    // Collect ownership mapping (from CODEOWNERS if exists)
    try collectOwnership(allocator, &ctx);

    // Collect recent changes
    try collectRecentChanges(allocator, &ctx);

    return ctx;
}

/// Collect project dependency graph
fn collectProjectGraph(
    allocator: std.mem.Allocator,
    graph: *types.ProjectGraph,
    config: *const config_types.Config,
    scope: ?[]const u8,
) !void {
    // If workspace is configured, use workspace members
    if (config.workspace) |ws| {
        for (ws.members) |member_path| {
            // Filter by scope if specified
            if (scope) |s| {
                if (!std.mem.startsWith(u8, member_path, s)) {
                    continue;
                }
            }

            // Extract package name from path
            const name = std.fs.path.basename(member_path);

            // Create package node
            var node = try PackageNode.init(allocator, name, member_path);
            errdefer node.deinit();

            // Try to load member's zr.toml to get dependencies
            const member_config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{member_path});
            defer allocator.free(member_config_path);

            var member_config = config_loader.loadFromFile(allocator, member_config_path) catch continue;
            defer member_config.deinit();
            {

                // Extract dependencies from metadata
                if (member_config.metadata) |metadata| {
                    for (metadata.dependencies) |dep| {
                        try node.dependencies.append(allocator, try allocator.dupe(u8, dep));
                    }

                    for (metadata.tags) |tag| {
                        try node.tags.append(allocator, try allocator.dupe(u8, tag));
                    }
                }
            }

            try graph.packages.append(allocator, node);
        }
    } else {
        // Single project mode - add root project
        const name = try getCurrentProjectName(allocator);
        defer allocator.free(name);

        var node = try PackageNode.init(allocator, name, ".");
        errdefer node.deinit();

        // Extract tags from metadata
        if (config.metadata) |metadata| {
            for (metadata.tags) |tag| {
                try node.tags.append(allocator, try allocator.dupe(u8, tag));
            }
        }

        try graph.packages.append(allocator, node);
    }
}

/// Collect task catalog from workspace members
fn collectTaskCatalog(
    allocator: std.mem.Allocator,
    ctx: *ProjectContext,
    config: *const config_types.Config,
    scope: ?[]const u8,
) !void {
    if (config.workspace) |ws| {
        // Workspace mode - collect tasks from each member
        for (ws.members) |member_path| {
            // Filter by scope
            if (scope) |s| {
                if (!std.mem.startsWith(u8, member_path, s)) {
                    continue;
                }
            }

            const name = std.fs.path.basename(member_path);
            var pkg_info = try PackageTaskInfo.init(allocator, name);
            errdefer pkg_info.deinit();

            // Load member config
            const member_config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{member_path});
            defer allocator.free(member_config_path);

            var member_config = config_loader.loadFromFile(allocator, member_config_path) catch continue;
            defer member_config.deinit();
            {

                // Collect tasks
                var task_iter = member_config.tasks.iterator();
                while (task_iter.next()) |entry| {
                    const task_name = entry.key_ptr.*;
                    const task_def = entry.value_ptr.*;

                    var task_info = try TaskInfo.init(
                        allocator,
                        task_name,
                        task_def.cmd,
                        task_def.description,
                    );
                    errdefer task_info.deinit();

                    // Add dependencies
                    for (task_def.deps) |dep| {
                        try task_info.dependencies.append(allocator, try allocator.dupe(u8, dep));
                    }

                    try pkg_info.tasks.append(allocator, task_info);
                }
            }

            try ctx.task_catalog.append(allocator, pkg_info);
        }
    } else {
        // Single project mode
        const name = try getCurrentProjectName(allocator);
        defer allocator.free(name);

        var pkg_info = try PackageTaskInfo.init(allocator, name);
        errdefer pkg_info.deinit();

        // Collect tasks from current config
        var task_iter = config.tasks.iterator();
        while (task_iter.next()) |entry| {
            const task_name = entry.key_ptr.*;
            const task_def = entry.value_ptr.*;

            var task_info = try TaskInfo.init(
                allocator,
                task_name,
                task_def.cmd,
                task_def.description,
            );
            errdefer task_info.deinit();

            // Add dependencies
            for (task_def.deps) |dep| {
                try task_info.dependencies.append(allocator, try allocator.dupe(u8, dep));
            }

            try pkg_info.tasks.append(allocator, task_info);
        }

        try ctx.task_catalog.append(allocator, pkg_info);
    }
}

/// Collect toolchain information
fn collectToolchains(
    allocator: std.mem.Allocator,
    ctx: *ProjectContext,
    config: *const config_types.Config,
) !void {
    const toolchains = config.toolchains;
    if (toolchains.tools.len > 0) {
        for (toolchains.tools) |spec| {
            const name_str = switch (spec.kind) {
                .node => "node",
                .python => "python",
                .zig => "zig",
                .go => "go",
                .rust => "rust",
                .deno => "deno",
                .bun => "bun",
                .java => "java",
            };

            const version_str = try std.fmt.allocPrint(
                allocator,
                "{d}.{d}.{d}",
                .{ spec.version.major, spec.version.minor, spec.version.patch orelse 0 },
            );

            try ctx.toolchains.append(allocator, .{
                .name = try allocator.dupe(u8, name_str),
                .version = version_str,
                .install_path = null, // Could be populated by checking ~/.zr/tools
            });
        }
    }
}

/// Collect ownership mapping from CODEOWNERS file
fn collectOwnership(allocator: std.mem.Allocator, ctx: *ProjectContext) !void {
    // Try to read CODEOWNERS file
    const codeowners_paths = [_][]const u8{
        ".github/CODEOWNERS",
        "CODEOWNERS",
        "docs/CODEOWNERS",
    };

    for (codeowners_paths) |path| {
        const file = std.fs.cwd().openFile(path, .{}) catch continue;
        defer file.close();

        const content = file.readToEndAlloc(allocator, 1024 * 1024) catch continue;
        defer allocator.free(content);

        // Parse CODEOWNERS format
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            // Parse: <path> <owner1> <owner2> ...
            var parts = std.mem.tokenizeAny(u8, trimmed, " \t");
            const file_path = parts.next() orelse continue;

            var owners = std.ArrayList([]const u8){};
            errdefer {
                for (owners.items) |owner| {
                    allocator.free(owner);
                }
                owners.deinit(allocator);
            }

            while (parts.next()) |owner| {
                try owners.append(allocator, try allocator.dupe(u8, owner));
            }

            if (owners.items.len > 0) {
                try ctx.ownership_mapping.append(allocator, .{
                    .path = try allocator.dupe(u8, file_path),
                    .owners = owners,
                });
            } else {
                owners.deinit(allocator);
            }
        }

        // Successfully parsed CODEOWNERS, no need to check other paths
        break;
    }
}

/// Collect recent changes from git
fn collectRecentChanges(allocator: std.mem.Allocator, ctx: *ProjectContext) !void {
    // Get recent commits (last 7 days by default)
    const days = ctx.recent_changes.time_range_days;
    const since_arg = try std.fmt.allocPrint(allocator, "--since={d} days ago", .{days});
    defer allocator.free(since_arg);

    const argv = [_][]const u8{ "git", "log", since_arg, "--oneline" };

    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return; // Git not available or not a git repo

    const stdout = child.stdout.?.readToEndAlloc(allocator, 10 * 1024 * 1024) catch return;
    defer allocator.free(stdout);

    _ = child.wait() catch return;

    // Count commits
    var line_count: usize = 0;
    var lines = std.mem.splitScalar(u8, stdout, '\n');
    while (lines.next()) |line| {
        if (line.len > 0) {
            line_count += 1;
        }
    }

    ctx.recent_changes.commit_count = line_count;

    // TODO: Could parse git diff to get affected files/packages
    // For now, just report commit count
}

/// Get current project name from directory or git
fn getCurrentProjectName(allocator: std.mem.Allocator) ![]const u8 {
    // Try to get from git remote
    const argv = [_][]const u8{ "git", "remote", "get-url", "origin" };

    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return allocator.dupe(u8, "unknown");

    const stdout = child.stdout.?.readToEndAlloc(allocator, 1024) catch {
        _ = child.wait() catch {};
        return allocator.dupe(u8, "unknown");
    };
    defer allocator.free(stdout);

    _ = child.wait() catch return allocator.dupe(u8, "unknown");

        // Parse repo name from URL
        // e.g., git@github.com:user/repo.git -> repo
        const trimmed = std.mem.trim(u8, stdout, " \t\r\n");
        if (std.mem.lastIndexOfScalar(u8, trimmed, '/')) |slash_idx| {
            const after_slash = trimmed[slash_idx + 1 ..];
            if (std.mem.endsWith(u8, after_slash, ".git")) {
                return allocator.dupe(u8, after_slash[0 .. after_slash.len - 4]);
            }
            return allocator.dupe(u8, after_slash);
        }

    // Fallback to current directory name
    const cwd = std.fs.cwd().realpathAlloc(allocator, ".") catch return allocator.dupe(u8, "unknown");
    defer allocator.free(cwd);

    const basename = std.fs.path.basename(cwd);
    return allocator.dupe(u8, basename);
}

test "generateContext basic" {
    const allocator = std.testing.allocator;

    var ctx = ProjectContext.init(allocator);
    defer ctx.deinit();

    // Just test that init/deinit works
    try std.testing.expect(ctx.task_catalog.items.len == 0);
}
