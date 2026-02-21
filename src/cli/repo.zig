const std = @import("std");
const color = @import("../output/color.zig");
const repos_parser = @import("../config/repos.zig");
const sync = @import("../multirepo/sync.zig");
const status = @import("../multirepo/status.zig");
const repo_graph = @import("../multirepo/graph.zig");
const common = @import("common.zig");

/// Main entry point for `zr repo` command.
pub fn cmdRepo(
    allocator: std.mem.Allocator,
    sub: []const u8,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    if (std.mem.eql(u8, sub, "sync")) {
        return cmdRepoSync(allocator, args, w, ew, use_color);
    } else if (std.mem.eql(u8, sub, "status")) {
        return cmdRepoStatus(allocator, args, w, ew, use_color);
    } else if (std.mem.eql(u8, sub, "graph")) {
        return cmdRepoGraph(allocator, args, w, ew, use_color);
    } else if (std.mem.eql(u8, sub, "help") or std.mem.eql(u8, sub, "--help") or std.mem.eql(u8, sub, "-h") or sub.len == 0) {
        try printHelp(w, use_color);
        return 0;
    } else {
        try color.printError(ew, use_color,
            "repo: unknown subcommand '{s}'\n\n  Hint: zr repo sync | zr repo status | zr repo graph\n", .{sub});
        return 1;
    }
}

/// `zr repo sync` - sync all repositories (clone missing, pull updates)
fn cmdRepoSync(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    // Parse options
    var options = sync.SyncOptions{};
    var repos_file: []const u8 = "zr-repos.toml";

    // Skip first arg (it's "repo") and second arg (it's "sync")
    var i: usize = 3; // args[0] = zr, args[1] = repo, args[2] = sync
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--clone-missing")) {
            options.clone_missing = true;
        } else if (std.mem.eql(u8, arg, "--no-pull")) {
            options.pull = false;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            options.verbose = true;
        } else if (std.mem.eql(u8, arg, "--config") or std.mem.eql(u8, arg, "-c")) {
            if (i + 1 < args.len) {
                repos_file = args[i + 1];
                i += 1;
            } else {
                try color.printError(ew, use_color, "--config: missing file path\n", .{});
                return 1;
            }
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printSyncHelp(w, use_color);
            return 0;
        } else {
            try color.printError(ew, use_color, "Unknown option: {s}\n", .{arg});
            return 1;
        }
    }

    // Load zr-repos.toml
    var config = repos_parser.loadRepoConfig(allocator, repos_file) catch |err| {
        try color.printError(ew, use_color,
            "Failed to load {s}: {s}\n\n  Hint: Create a zr-repos.toml file with [[repos]] entries\n",
            .{ repos_file, @errorName(err) });
        return 1;
    };
    defer config.deinit(allocator);

    if (config.repos.len == 0) {
        if (use_color) try w.writeAll(color.Code.yellow);
        try w.print("No repositories defined in {s}\n", .{repos_file});
        if (use_color) try w.writeAll(color.Code.reset);
        return 0;
    }

    // Sync repos
    const statuses = sync.syncRepos(allocator, &config, options) catch |err| {
        try color.printError(ew, use_color, "Sync failed: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer {
        for (statuses) |*s| {
            if (s.message) |msg| allocator.free(msg);
        }
        allocator.free(statuses);
    }

    // Print results
    try color.printBold(w, use_color, "\nRepository Sync Results:\n", .{});
    try w.print("\n", .{});

    var cloned: u32 = 0;
    var pulled: u32 = 0;
    var unchanged: u32 = 0;
    var skipped: u32 = 0;
    var failed: u32 = 0;

    for (statuses) |s| {
        const icon = switch (s.state) {
            .cloned => "✓",
            .pulled => "↑",
            .unchanged => "=",
            .skipped => "-",
            .failed => "✗",
        };

        const state_code = switch (s.state) {
            .cloned => color.Code.green,
            .pulled => color.Code.cyan,
            .unchanged => color.Code.dim,
            .skipped => color.Code.yellow,
            .failed => color.Code.red,
        };

        if (use_color) try w.writeAll(state_code);
        try w.print("  {s} ", .{icon});
        if (use_color) try w.writeAll(color.Code.reset);

        try color.printBold(w, use_color, "{s:<20}", .{s.name});

        const state_str = switch (s.state) {
            .cloned => "cloned",
            .pulled => "pulled",
            .unchanged => "up-to-date",
            .skipped => "skipped",
            .failed => "failed",
        };

        if (use_color) try w.writeAll(state_code);
        try w.print(" {s}", .{state_str});
        if (use_color) try w.writeAll(color.Code.reset);

        if (s.message) |msg| {
            try color.printDim(w, use_color, " ({s})", .{msg});
        }
        try w.print("\n", .{});

        switch (s.state) {
            .cloned => cloned += 1,
            .pulled => pulled += 1,
            .unchanged => unchanged += 1,
            .skipped => skipped += 1,
            .failed => failed += 1,
        }
    }

    try w.print("\n", .{});
    try color.printDim(w, use_color, "Summary: ", .{});
    if (cloned > 0) {
        if (use_color) try w.writeAll(color.Code.green);
        try w.print("{d} cloned  ", .{cloned});
        if (use_color) try w.writeAll(color.Code.reset);
    }
    if (pulled > 0) {
        if (use_color) try w.writeAll(color.Code.cyan);
        try w.print("{d} pulled  ", .{pulled});
        if (use_color) try w.writeAll(color.Code.reset);
    }
    if (unchanged > 0) try color.printDim(w, use_color, "{d} unchanged  ", .{unchanged});
    if (skipped > 0) {
        if (use_color) try w.writeAll(color.Code.yellow);
        try w.print("{d} skipped  ", .{skipped});
        if (use_color) try w.writeAll(color.Code.reset);
    }
    if (failed > 0) {
        if (use_color) try ew.writeAll(color.Code.red);
        try ew.print("{d} failed  ", .{failed});
        if (use_color) try ew.writeAll(color.Code.reset);
    }
    try w.print("\n", .{});

    return if (failed > 0) 1 else 0;
}

/// `zr repo status` - show git status of all repositories
fn cmdRepoStatus(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    // Parse options
    var repos_file: []const u8 = "zr-repos.toml";
    var verbose = false;

    var i: usize = 3; // args[0] = zr, args[1] = repo, args[2] = status
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--config") or std.mem.eql(u8, arg, "-c")) {
            if (i + 1 < args.len) {
                repos_file = args[i + 1];
                i += 1;
            } else {
                try color.printError(ew, use_color, "--config: missing file path\n", .{});
                return 1;
            }
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printStatusHelp(w, use_color);
            return 0;
        } else {
            try color.printError(ew, use_color, "Unknown option: {s}\n", .{arg});
            return 1;
        }
    }

    // Load zr-repos.toml
    var config = repos_parser.loadRepoConfig(allocator, repos_file) catch |err| {
        try color.printError(ew, use_color,
            "Failed to load {s}: {s}\n\n  Hint: Create a zr-repos.toml file with [[repos]] entries\n",
            .{ repos_file, @errorName(err) });
        return 1;
    };
    defer config.deinit(allocator);

    if (config.repos.len == 0) {
        if (use_color) try w.writeAll(color.Code.yellow);
        try w.print("No repositories defined in {s}\n", .{repos_file});
        if (use_color) try w.writeAll(color.Code.reset);
        return 0;
    }

    // Get statuses
    const statuses = status.getRepoStatuses(allocator, &config) catch |err| {
        try color.printError(ew, use_color, "Status check failed: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer {
        for (statuses) |*s| {
            var s_mut = s.*;
            s_mut.deinit(allocator);
        }
        allocator.free(statuses);
    }

    // Print results
    try color.printBold(w, use_color, "\nRepository Status:\n", .{});
    try w.print("\n", .{});

    var has_issues = false;

    for (statuses) |s| {
        if (!s.exists) {
            try color.printError(ew, use_color, "  ✗ ", .{});
            try color.printBold(w, use_color, "{s:<20}", .{s.name});
            try color.printError(ew, use_color, " not found\n", .{});
            has_issues = true;
            continue;
        }

        const icon: []const u8 = if (s.clean) "✓" else "⚠";
        const icon_code = if (s.clean) color.Code.green else color.Code.yellow;

        if (use_color) try w.writeAll(icon_code);
        try w.print("  {s} ", .{icon});
        if (use_color) try w.writeAll(color.Code.reset);

        try color.printBold(w, use_color, "{s:<20}", .{s.name});

        if (s.branch) |branch| {
            if (use_color) try w.writeAll(color.Code.cyan);
            try w.print(" {s}", .{branch});
            if (use_color) try w.writeAll(color.Code.reset);
        }

        if (s.ahead > 0 or s.behind > 0) {
            try w.print(" [", .{});
            if (s.ahead > 0) {
                if (use_color) try w.writeAll(color.Code.green);
                try w.print("↑{d}", .{s.ahead});
                if (use_color) try w.writeAll(color.Code.reset);
            }
            if (s.ahead > 0 and s.behind > 0) try w.print(" ", .{});
            if (s.behind > 0) {
                if (use_color) try w.writeAll(color.Code.red);
                try w.print("↓{d}", .{s.behind});
                if (use_color) try w.writeAll(color.Code.reset);
            }
            try w.print("]", .{});
        }

        if (verbose or !s.clean) {
            if (s.modified > 0) {
                if (use_color) try w.writeAll(color.Code.yellow);
                try w.print(" {d} modified", .{s.modified});
                if (use_color) try w.writeAll(color.Code.reset);
            }
            if (s.untracked > 0) {
                try color.printDim(w, use_color, " {d} untracked", .{s.untracked});
            }
        }

        try w.print("\n", .{});

        if (!s.clean) {
            has_issues = true;
        }
    }

    try w.print("\n", .{});

    return if (has_issues) 1 else 0;
}

/// `zr repo graph` - show cross-repo dependency graph
fn cmdRepoGraph(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    // Parse options
    var repos_file: []const u8 = "zr-repos.toml";
    var format: []const u8 = "ascii";
    var filter_tags = std.ArrayList([]const u8){};
    defer filter_tags.deinit(allocator);

    var i: usize = 3; // args[0] = zr, args[1] = repo, args[2] = graph
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--config") or std.mem.eql(u8, arg, "-c")) {
            if (i + 1 < args.len) {
                repos_file = args[i + 1];
                i += 1;
            } else {
                try color.printError(ew, use_color, "--config: missing file path\n", .{});
                return 1;
            }
        } else if (std.mem.eql(u8, arg, "--format") or std.mem.eql(u8, arg, "-f")) {
            if (i + 1 < args.len) {
                format = args[i + 1];
                i += 1;
            } else {
                try color.printError(ew, use_color, "--format: missing format (ascii, dot, json)\n", .{});
                return 1;
            }
        } else if (std.mem.eql(u8, arg, "--tags")) {
            if (i + 1 < args.len) {
                const tags_str = args[i + 1];
                var tags_iter = std.mem.splitScalar(u8, tags_str, ',');
                while (tags_iter.next()) |tag| {
                    try filter_tags.append(allocator, tag);
                }
                i += 1;
            } else {
                try color.printError(ew, use_color, "--tags: missing tag list (comma-separated)\n", .{});
                return 1;
            }
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printGraphHelp(w, use_color);
            return 0;
        } else {
            try color.printError(ew, use_color, "Unknown option: {s}\n", .{arg});
            return 1;
        }
    }

    // Validate format
    if (!std.mem.eql(u8, format, "ascii") and !std.mem.eql(u8, format, "dot") and !std.mem.eql(u8, format, "json")) {
        try color.printError(ew, use_color, "Unknown format: {s} (use ascii, dot, or json)\n", .{format});
        return 1;
    }

    // Load zr-repos.toml
    var config = repos_parser.loadRepoConfig(allocator, repos_file) catch |err| {
        try color.printError(ew, use_color,
            "Failed to load {s}: {s}\n\n  Hint: Create a zr-repos.toml file with [[repos]] entries\n",
            .{ repos_file, @errorName(err) });
        return 1;
    };
    defer config.deinit(allocator);

    if (config.repos.len == 0) {
        if (use_color) try w.writeAll(color.Code.yellow);
        try w.print("No repositories defined in {s}\n", .{repos_file});
        if (use_color) try w.writeAll(color.Code.reset);
        return 0;
    }

    // Build graph
    var graph = repo_graph.buildRepoGraph(allocator, &config) catch |err| {
        try color.printError(ew, use_color, "Failed to build graph: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer graph.deinit();

    // Check for cycles
    const cycle = try repo_graph.detectCycles(&graph, allocator);
    if (cycle) |cycle_path| {
        defer {
            for (cycle_path) |name| allocator.free(name);
            allocator.free(cycle_path);
        }
        try color.printError(ew, use_color, "Cycle detected in dependency graph:\n", .{});
        for (cycle_path) |name| {
            try ew.print("  → {s}\n", .{name});
        }
        return 1;
    }

    // Apply tag filter if specified
    var filtered_repos: ?[][]const u8 = null;
    defer {
        if (filtered_repos) |repos| {
            for (repos) |name| allocator.free(name);
            allocator.free(repos);
        }
    }

    if (filter_tags.items.len > 0) {
        filtered_repos = try repo_graph.filterByTags(&graph, filter_tags.items, allocator);
        if (filtered_repos.?.len == 0) {
            try color.printError(ew, use_color, "No repositories match the specified tags\n", .{});
            return 1;
        }
    }

    // Output graph in requested format
    if (std.mem.eql(u8, format, "ascii")) {
        try printAsciiGraph(w, &graph, filtered_repos, use_color);
    } else if (std.mem.eql(u8, format, "dot")) {
        try printDotGraph(w, &graph, filtered_repos);
    } else if (std.mem.eql(u8, format, "json")) {
        try printJsonGraph(w, &graph, filtered_repos);
    }

    return 0;
}

fn printAsciiGraph(w: *std.Io.Writer, graph: *const repo_graph.RepoGraph, filter: ?[][]const u8, use_color: bool) !void {
    const allocator = graph.allocator;

    // Get topological sort for ordering
    const sorted = try repo_graph.topologicalSort(graph, allocator);
    defer {
        for (sorted) |name| allocator.free(name);
        allocator.free(sorted);
    }

    try color.printBold(w, use_color, "\nRepository Dependency Graph:\n\n", .{});

    for (sorted) |repo_name| {
        // Skip if filtered
        if (filter) |f| {
            var should_include = false;
            for (f) |fname| {
                if (std.mem.eql(u8, repo_name, fname)) {
                    should_include = true;
                    break;
                }
            }
            if (!should_include) continue;
        }

        const node = graph.nodes.get(repo_name) orelse continue;

        if (use_color) try w.writeAll(color.Code.cyan);
        try w.print("  {s}", .{repo_name});
        if (use_color) try w.writeAll(color.Code.reset);

        if (node.tags.len > 0) {
            try color.printDim(w, use_color, " [", .{});
            for (node.tags, 0..) |tag, i| {
                if (i > 0) try w.print(", ", .{});
                try color.printDim(w, use_color, "{s}", .{tag});
            }
            try color.printDim(w, use_color, "]", .{});
        }

        try w.print("\n", .{});

        if (node.dependencies.len > 0) {
            for (node.dependencies, 0..) |dep, i| {
                const is_last = i == node.dependencies.len - 1;
                const prefix = if (is_last) "    └─ " else "    ├─ ";
                try color.printDim(w, use_color, "{s}", .{prefix});
                try w.print("{s}\n", .{dep});
            }
        } else {
            try color.printDim(w, use_color, "    (no dependencies)\n", .{});
        }
    }

    try w.print("\n", .{});
}

fn printDotGraph(w: *std.Io.Writer, graph: *const repo_graph.RepoGraph, filter: ?[][]const u8) !void {
    try w.print("digraph repos {{\n", .{});
    try w.print("  rankdir=LR;\n", .{});
    try w.print("  node [shape=box];\n\n", .{});

    var it = graph.nodes.iterator();
    while (it.next()) |entry| {
        const repo_name = entry.key_ptr.*;
        const node = entry.value_ptr;

        // Skip if filtered
        if (filter) |f| {
            var should_include = false;
            for (f) |fname| {
                if (std.mem.eql(u8, repo_name, fname)) {
                    should_include = true;
                    break;
                }
            }
            if (!should_include) continue;
        }

        // Node declaration
        try w.print("  \"{s}\"", .{repo_name});
        if (node.tags.len > 0) {
            try w.print(" [label=\"{s}\\n[", .{repo_name});
            for (node.tags, 0..) |tag, i| {
                if (i > 0) try w.print(", ", .{});
                try w.print("{s}", .{tag});
            }
            try w.print("]\"]", .{});
        }
        try w.print(";\n", .{});

        // Edges
        for (node.dependencies) |dep| {
            try w.print("  \"{s}\" -> \"{s}\";\n", .{ repo_name, dep });
        }
    }

    try w.print("}}\n", .{});
}

fn printJsonGraph(w: *std.Io.Writer, graph: *const repo_graph.RepoGraph, filter: ?[][]const u8) !void {
    try w.print("{{\n", .{});
    try w.print("  \"repositories\": [\n", .{});

    var it = graph.nodes.iterator();
    var first = true;
    while (it.next()) |entry| {
        const repo_name = entry.key_ptr.*;
        const node = entry.value_ptr;

        // Skip if filtered
        if (filter) |f| {
            var should_include = false;
            for (f) |fname| {
                if (std.mem.eql(u8, repo_name, fname)) {
                    should_include = true;
                    break;
                }
            }
            if (!should_include) continue;
        }

        if (!first) try w.print(",\n", .{});
        first = false;

        try w.print("    {{\n", .{});
        try w.print("      \"name\": \"{s}\",\n", .{repo_name});
        try w.print("      \"path\": \"{s}\",\n", .{node.path});
        try w.print("      \"tags\": [", .{});
        for (node.tags, 0..) |tag, i| {
            if (i > 0) try w.print(", ", .{});
            try w.print("\"{s}\"", .{tag});
        }
        try w.print("],\n", .{});
        try w.print("      \"dependencies\": [", .{});
        for (node.dependencies, 0..) |dep, i| {
            if (i > 0) try w.print(", ", .{});
            try w.print("\"{s}\"", .{dep});
        }
        try w.print("],\n", .{});
        try w.print("      \"dependents\": [", .{});
        for (node.dependents, 0..) |dep, i| {
            if (i > 0) try w.print(", ", .{});
            try w.print("\"{s}\"", .{dep});
        }
        try w.print("]\n", .{});
        try w.print("    }}", .{});
    }

    try w.print("\n  ]\n", .{});
    try w.print("}}\n", .{});
}

fn printHelp(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "zr repo", .{});
    try w.print(" - Multi-repository management\n\n", .{});
    try color.printBold(w, use_color, "Usage:\n", .{});
    try w.print("  zr repo <command> [options]\n\n", .{});
    try color.printBold(w, use_color, "Commands:\n", .{});
    try w.print("  sync         Sync all repositories (clone missing, pull updates)\n", .{});
    try w.print("  status       Show git status of all repositories\n", .{});
    try w.print("  graph        Show cross-repo dependency graph\n", .{});
    try w.print("\n", .{});
    try color.printDim(w, use_color, "For more help on a command: zr repo <command> --help\n", .{});
}

fn printSyncHelp(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "zr repo sync", .{});
    try w.print(" - Sync all repositories\n\n", .{});
    try color.printBold(w, use_color, "Usage:\n", .{});
    try w.print("  zr repo sync [options]\n\n", .{});
    try color.printBold(w, use_color, "Options:\n", .{});
    try w.print("  --clone-missing     Only clone repos that don't exist (skip pull)\n", .{});
    try w.print("  --no-pull           Don't pull updates for existing repos\n", .{});
    try w.print("  --verbose, -v       Show detailed output\n", .{});
    try w.print("  --config, -c <path> Path to zr-repos.toml (default: zr-repos.toml)\n", .{});
    try w.print("  --help, -h          Show this help message\n", .{});
}

fn printStatusHelp(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "zr repo status", .{});
    try w.print(" - Show git status of all repositories\n\n", .{});
    try color.printBold(w, use_color, "Usage:\n", .{});
    try w.print("  zr repo status [options]\n\n", .{});
    try color.printBold(w, use_color, "Options:\n", .{});
    try w.print("  --verbose, -v       Show detailed file counts for all repos\n", .{});
    try w.print("  --config, -c <path> Path to zr-repos.toml (default: zr-repos.toml)\n", .{});
    try w.print("  --help, -h          Show this help message\n", .{});
}

fn printGraphHelp(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "zr repo graph", .{});
    try w.print(" - Show cross-repo dependency graph\n\n", .{});
    try color.printBold(w, use_color, "Usage:\n", .{});
    try w.print("  zr repo graph [options]\n\n", .{});
    try color.printBold(w, use_color, "Options:\n", .{});
    try w.print("  --format, -f <fmt>  Output format: ascii (default), dot, json\n", .{});
    try w.print("  --tags <tags>       Filter repos by tags (comma-separated)\n", .{});
    try w.print("  --config, -c <path> Path to zr-repos.toml (default: zr-repos.toml)\n", .{});
    try w.print("  --help, -h          Show this help message\n", .{});
    try w.print("\n", .{});
    try color.printBold(w, use_color, "Examples:\n", .{});
    try w.print("  zr repo graph              # ASCII tree view\n", .{});
    try w.print("  zr repo graph -f dot       # Graphviz DOT format\n", .{});
    try w.print("  zr repo graph -f json      # JSON format\n", .{});
    try w.print("  zr repo graph --tags=api   # Only repos tagged 'api'\n", .{});
}

// ============================================================================
// Tests
// ============================================================================

test "repo command help" {
    const t = std.testing;
    var buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var w = stdout.writer(&buf);
    var ew = stdout.writer(&buf);

    const result = try cmdRepo(t.allocator, "help", &[_][]const u8{}, &w.interface, &ew.interface, false);
    try t.expectEqual(@as(u8, 0), result);
}
