const std = @import("std");
const color = @import("../output/color.zig");
const repos_parser = @import("../config/repos.zig");
const sync = @import("../multirepo/sync.zig");
const status = @import("../multirepo/status.zig");
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
    } else if (std.mem.eql(u8, sub, "help") or std.mem.eql(u8, sub, "--help") or std.mem.eql(u8, sub, "-h") or sub.len == 0) {
        try printHelp(w, use_color);
        return 0;
    } else {
        try color.printError(ew, use_color,
            "repo: unknown subcommand '{s}'\n\n  Hint: zr repo sync | zr repo status\n", .{sub});
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

fn printHelp(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "zr repo", .{});
    try w.print(" - Multi-repository management\n\n", .{});
    try color.printBold(w, use_color, "Usage:\n", .{});
    try w.print("  zr repo <command> [options]\n\n", .{});
    try color.printBold(w, use_color, "Commands:\n", .{});
    try w.print("  sync         Sync all repositories (clone missing, pull updates)\n", .{});
    try w.print("  status       Show git status of all repositories\n", .{});
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
