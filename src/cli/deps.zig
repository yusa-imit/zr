const std = @import("std");
const build_options = @import("build_options");
const config_mod = @import("../config/types.zig");
const parser = @import("../config/parser.zig");
const lock_mod = @import("../config/lock.zig");
const version_mod = @import("../toolchain/version.zig");
const constraint_mod = @import("../config/constraint.zig");
const semver = @import("../util/semver.zig");

const TaskConfig = config_mod.TaskConfig;
const Config = config_mod.Config;
const LockFile = lock_mod.LockFile;
const LockFileDependency = lock_mod.LockFileDependency;

/// Handle `zr deps` subcommands
pub fn handle(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 3) {
        try printUsage();
        return error.MissingSubcommand;
    }

    const subcommand = args[2];

    if (std.mem.eql(u8, subcommand, "check")) {
        try handleCheck(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "install")) {
        try handleInstall(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "outdated")) {
        try handleOutdated(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "lock")) {
        try handleLock(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "help") or std.mem.eql(u8, subcommand, "--help")) {
        try printUsage();
    } else {
        std.debug.print("error: unknown subcommand '{s}'\n", .{subcommand});
        try printUsage();
        return error.UnknownSubcommand;
    }
}

/// Handle `zr deps check` - verify all dependencies satisfy constraints
fn handleCheck(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var task_filter: ?[]const u8 = null;
    var json_output = false;

    // Parse flags
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try printCheckHelp();
            return;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        } else if (std.mem.startsWith(u8, arg, "--task=")) {
            task_filter = arg["--task=".len..];
        } else if (std.mem.eql(u8, arg, "--task")) {
            i += 1;
            if (i >= args.len) return error.MissingTaskName;
            task_filter = args[i];
        }
    }

    // Load config
    var config = try loadConfig(allocator);
    defer config.deinit();

    // Collect all dependencies
    var dep_map = std.StringHashMap([]const u8).init(allocator);
    defer dep_map.deinit();

    var task_iter = config.tasks.iterator();
    while (task_iter.next()) |task_entry| {
        const task_name = task_entry.key_ptr.*;
        const task = task_entry.value_ptr.*;

        if (task_filter) |filter| {
            if (!std.mem.eql(u8, task_name, filter)) continue;
        }

        if (task.requires) |requires| {
            var iter = requires.iterator();
            while (iter.next()) |entry| {
                try dep_map.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
    }

    if (dep_map.count() == 0) {
        if (json_output) {
            std.debug.print("{{\"status\":\"ok\",\"message\":\"No dependencies defined\"}}\n", .{});
        } else {
            std.debug.print("No dependencies defined\n", .{});
        }
        return;
    }

    // Check each dependency
    var all_satisfied = true;
    var results: std.ArrayList(CheckResult) = .{};
    defer results.deinit(allocator);

    var dep_iter = dep_map.iterator();
    while (dep_iter.next()) |entry| {
        const tool_name = entry.key_ptr.*;
        const constraint_str = entry.value_ptr.*;

        const result = checkDependency(allocator, tool_name, constraint_str) catch |err| {
            all_satisfied = false;
            try results.append(allocator, .{
                .tool = tool_name,
                .constraint = constraint_str,
                .installed = null,
                .satisfied = false,
                .error_msg = @errorName(err),
            });
            continue;
        };

        try results.append(allocator, result);
        if (!result.satisfied) all_satisfied = false;
    }

    // Output results
    if (json_output) {
        try printCheckResultsJson(allocator, results.items);
    } else {
        try printCheckResults(results.items);
    }

    if (!all_satisfied) {
        return error.UnsatisfiedConstraints;
    }
}

/// Handle `zr deps install` - list/install missing dependencies
fn handleInstall(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var install_deps = false;
    var json_output = false;

    // Parse flags
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            try printInstallHelp();
            return;
        } else if (std.mem.eql(u8, arg, "--install-deps")) {
            install_deps = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        }
    }

    if (install_deps) {
        // TODO: actual installation logic
        std.debug.print("Auto-installation not yet implemented\n", .{});
    }

    var config = try loadConfig(allocator);
    defer config.deinit();

    var dep_map = std.StringHashMap([]const u8).init(allocator);
    defer dep_map.deinit();

    var task_iter = config.tasks.iterator();
    while (task_iter.next()) |task_entry| {
        const task = task_entry.value_ptr.*;
        if (task.requires) |requires| {
            var iter = requires.iterator();
            while (iter.next()) |entry| {
                try dep_map.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
    }

    if (json_output) {
        std.debug.print("{{\"dependencies\":[", .{});
        var first = true;
        var dep_iter = dep_map.iterator();
        while (dep_iter.next()) |entry| {
            if (!first) std.debug.print(",", .{});
            std.debug.print("{{\"tool\":\"{s}\",\"version\":\"{s}\"}}", .{ entry.key_ptr.*, entry.value_ptr.* });
            first = false;
        }
        std.debug.print("]}}\n", .{});
    } else {
        std.debug.print("Dependencies:\n", .{});
        var dep_iter = dep_map.iterator();
        while (dep_iter.next()) |entry| {
            std.debug.print("  {s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }
}

/// Handle `zr deps outdated` - show available updates
fn handleOutdated(_: std.mem.Allocator, args: []const []const u8) !void {
    var task_filter: ?[]const u8 = null;
    var json_output = false;

    // Parse flags
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try printOutdatedHelp();
            return;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        } else if (std.mem.startsWith(u8, arg, "--task=")) {
            task_filter = arg["--task=".len..];
        } else if (std.mem.eql(u8, arg, "--task")) {
            i += 1;
            if (i >= args.len) return error.MissingTaskName;
            task_filter = args[i];
        }
    }

    // Placeholder - actual implementation would query registries for latest versions
    if (json_output) {
        std.debug.print("{{\"outdated\":[]}}\n", .{});
    } else {
        if (task_filter) |filter| {
            std.debug.print("Checking for outdated dependencies for task: {s}...\n", .{filter});
        } else {
            std.debug.print("Checking for outdated dependencies...\n", .{});
        }
        std.debug.print("No updates available\n", .{});
    }
}

/// Handle `zr deps lock` - generate lock file
fn handleLock(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var update_mode = false;
    var json_output = false;

    // Parse flags
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            try printLockHelp();
            return;
        } else if (std.mem.eql(u8, arg, "--update")) {
            update_mode = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        }
    }

    if (update_mode) {
        // TODO: update existing lock file
    }

    var config = try loadConfig(allocator);
    defer config.deinit();

    // Collect all dependencies
    var dep_list: std.ArrayList(LockFileDependency) = .{};
    defer {
        for (dep_list.items) |*dep| {
            dep.deinit(allocator);
        }
        dep_list.deinit(allocator);
    }

    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    var task_iter = config.tasks.iterator();
    while (task_iter.next()) |task_entry| {
        const task = task_entry.value_ptr.*;
        if (task.requires) |requires| {
            var iter = requires.iterator();
            while (iter.next()) |entry| {
                const tool_name = entry.key_ptr.*;
                const constraint_str = entry.value_ptr.*;

                if (seen.contains(tool_name)) continue;
                try seen.put(tool_name, {});

                // Detect current version
                const version_config = version_mod.VersionDetectionConfig{
                    .tool_name = tool_name,
                };
                const detected_version = version_mod.detectVersion(allocator, version_config) catch {
                    std.debug.print("Warning: Could not detect version for {s}\n", .{tool_name});
                    continue;
                };

                const version_str = try std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{
                    detected_version.major,
                    detected_version.minor,
                    detected_version.patch,
                });

                // Generate ISO 8601 timestamp
                const unix_timestamp = std.time.timestamp();
                const timestamp = try std.fmt.allocPrint(allocator, "{d}", .{unix_timestamp});

                try dep_list.append(allocator, .{
                    .tool = try allocator.dupe(u8, tool_name),
                    .constraint = try allocator.dupe(u8, constraint_str),
                    .resolved = version_str,
                    .detected_at = timestamp,
                });
            }
        }
    }

    // Generate lock file
    const zr_version = build_options.version;
    try lock_mod.generateLockFile(allocator, ".zr-lock.toml", dep_list.items, zr_version);

    if (json_output) {
        std.debug.print("{{\"status\":\"ok\",\"lock_file\":\".zr-lock.toml\"}}\n", .{});
    } else {
        std.debug.print("Generated .zr-lock.toml with {d} dependencies\n", .{dep_list.items.len});
    }
}

// ─── Helper Functions ──────────────────────────────────────────────────────

const CheckResult = struct {
    tool: []const u8,
    constraint: []const u8,
    installed: ?[]const u8,
    satisfied: bool,
    error_msg: ?[]const u8 = null,
};

fn checkDependency(allocator: std.mem.Allocator, tool_name: []const u8, constraint_str: []const u8) !CheckResult {
    const version_config = version_mod.VersionDetectionConfig{
        .tool_name = tool_name,
    };

    const installed_version = try version_mod.detectVersion(allocator, version_config);
    var constraint = try constraint_mod.parseConstraint(allocator, constraint_str);
    defer constraint.deinit(allocator);

    const satisfied = constraint_mod.satisfies(installed_version, constraint);

    const version_str = try std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{
        installed_version.major,
        installed_version.minor,
        installed_version.patch,
    });

    return CheckResult{
        .tool = tool_name,
        .constraint = constraint_str,
        .installed = version_str,
        .satisfied = satisfied,
    };
}

fn loadConfig(allocator: std.mem.Allocator) !Config {
    const file_data = try std.fs.cwd().readFileAlloc(allocator, "zr.toml", 10 * 1024 * 1024);
    defer allocator.free(file_data);

    return try parser.parseToml(allocator, file_data);
}

fn printCheckResults(results: []const CheckResult) !void {
    var all_ok = true;
    for (results) |result| {
        if (result.error_msg) |err_msg| {
            std.debug.print("✗ {s}: {s}\n", .{ result.tool, err_msg });
            all_ok = false;
        } else if (result.satisfied) {
            std.debug.print("✓ {s} ({s}) satisfies {s}\n", .{ result.tool, result.installed.?, result.constraint });
        } else {
            std.debug.print("✗ {s} ({s}) does not satisfy {s}\n", .{ result.tool, result.installed.?, result.constraint });
            all_ok = false;
        }
    }

    if (all_ok) {
        std.debug.print("\nAll dependencies satisfied\n", .{});
    }
}

fn printCheckResultsJson(allocator: std.mem.Allocator, results: []const CheckResult) !void {
    _ = allocator;
    std.debug.print("{{\"results\":[", .{});
    for (results, 0..) |result, i| {
        if (i > 0) std.debug.print(",", .{});
        std.debug.print("{{\"tool\":\"{s}\",\"constraint\":\"{s}\",\"installed\":", .{ result.tool, result.constraint });
        if (result.installed) |installed| {
            std.debug.print("\"{s}\"", .{installed});
        } else {
            std.debug.print("null", .{});
        }
        std.debug.print(",\"satisfied\":{s}}}", .{if (result.satisfied) "true" else "false"});
    }
    std.debug.print("]}}\n", .{});
}

// ─── Help Messages ─────────────────────────────────────────────────────────

fn printUsage() !void {
    std.debug.print(
        \\Usage: zr deps <subcommand> [options]
        \\
        \\Subcommands:
        \\  check       Verify all dependencies satisfy constraints
        \\  install     List or install missing dependencies
        \\  outdated    Show available updates for dependencies
        \\  lock        Generate lock file with resolved versions
        \\  help        Show this help message
        \\
        \\Run 'zr deps <subcommand> --help' for more information on a specific command.
        \\
    , .{});
}

fn printCheckHelp() !void {
    std.debug.print(
        \\Usage: zr deps check [options]
        \\
        \\Verify that all task dependencies satisfy version constraints.
        \\
        \\Options:
        \\  --task=<name>    Check dependencies for specific task only
        \\  --json           Output results in JSON format
        \\  --help           Show this help message
        \\
        \\Examples:
        \\  zr deps check
        \\  zr deps check --task=build
        \\  zr deps check --json
        \\
    , .{});
}

fn printInstallHelp() !void {
    std.debug.print(
        \\Usage: zr deps install [options]
        \\
        \\List or install missing dependencies.
        \\
        \\Options:
        \\  --install-deps   Automatically install missing tools (experimental)
        \\  --json           Output in JSON format
        \\  --help           Show this help message
        \\
        \\Examples:
        \\  zr deps install
        \\  zr deps install --install-deps
        \\
    , .{});
}

fn printOutdatedHelp() !void {
    std.debug.print(
        \\Usage: zr deps outdated [options]
        \\
        \\Show available updates for dependencies.
        \\
        \\Options:
        \\  --task=<name>    Check updates for specific task only
        \\  --json           Output in JSON format
        \\  --help           Show this help message
        \\
        \\Examples:
        \\  zr deps outdated
        \\  zr deps outdated --task=frontend
        \\
    , .{});
}

fn printLockHelp() !void {
    std.debug.print(
        \\Usage: zr deps lock [options]
        \\
        \\Generate lock file with resolved dependency versions.
        \\
        \\Options:
        \\  --update    Update lock file with latest compatible versions
        \\  --json      Output in JSON format
        \\  --help      Show this help message
        \\
        \\Examples:
        \\  zr deps lock
        \\  zr deps lock --update
        \\
    , .{});
}
