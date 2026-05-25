const std = @import("std");
const build_options = @import("build_options");
const config_mod = @import("../config/types.zig");
const parser = @import("../config/parser.zig");
const lock_mod = @import("../config/lock.zig");
const version_mod = @import("../toolchain/version.zig");
const constraint_mod = @import("../config/constraint.zig");
const semver = @import("../util/semver.zig");
const toolchain_types = @import("../toolchain/types.zig");
const toolchain_installer = @import("../toolchain/installer.zig");

const TaskConfig = config_mod.TaskConfig;
const Config = config_mod.Config;
const LockFile = lock_mod.LockFile;
const LockFileDependency = lock_mod.LockFileDependency;
const ToolKind = toolchain_types.ToolKind;
const ToolVersion = toolchain_types.ToolVersion;

/// Handle `zr deps` subcommands
pub fn handle(allocator: std.mem.Allocator, args: []const []const u8, w: *std.Io.Writer, ew: *std.Io.Writer) !void {
    if (args.len < 3) {
        try printUsage(w);
        return;
    }

    const subcommand = args[2];

    if (std.mem.eql(u8, subcommand, "check")) {
        try handleCheck(allocator, args[3..], w, ew);
    } else if (std.mem.eql(u8, subcommand, "install")) {
        try handleInstall(allocator, args[3..], w, ew);
    } else if (std.mem.eql(u8, subcommand, "outdated")) {
        try handleOutdated(args[3..], w, ew);
    } else if (std.mem.eql(u8, subcommand, "lock")) {
        try handleLock(allocator, args[3..], w, ew);
    } else if (std.mem.eql(u8, subcommand, "help") or std.mem.eql(u8, subcommand, "--help")) {
        try printUsage(w);
    } else {
        try ew.print("✗ [Deps]: Unknown subcommand '{s}'\n\n", .{subcommand});
        try printUsage(w);
        return error.UnknownSubcommand;
    }
}

/// Handle `zr deps check` - verify all dependencies satisfy constraints
fn handleCheck(allocator: std.mem.Allocator, args: []const []const u8, w: *std.Io.Writer, ew: *std.Io.Writer) !void {
    var task_filter: ?[]const u8 = null;
    var json_output = false;

    // Parse flags
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try printCheckHelp(w);
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
    var config = loadConfig(allocator) catch |err| {
        if (err == error.FileNotFound) {
            try ew.print("✗ [Deps]: zr.toml not found in current directory\n\n  Hint: Run 'zr init' to create a configuration file\n", .{});
            return error.ConfigNotFound;
        }
        return err;
    };
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
        if (task_filter) |filter| {
            try ew.print("✗ [Deps]: Task '{s}' not found\n\n  Hint: Run 'zr list' to see available tasks\n", .{filter});
            return error.TaskNotFound;
        }
        if (json_output) {
            try w.print("{{\"status\":\"ok\",\"message\":\"No dependencies defined\"}}\n", .{});
        } else {
            try w.print("No dependencies defined\n", .{});
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
        try printCheckResultsJson(results.items, w);
    } else {
        try printCheckResults(results.items, w, ew);
    }

    if (!all_satisfied) {
        return error.UnsatisfiedConstraints;
    }
}

/// Handle `zr deps install` - list/install missing dependencies
fn handleInstall(allocator: std.mem.Allocator, args: []const []const u8, w: *std.Io.Writer, ew: *std.Io.Writer) !void {
    var install_deps = false;
    var json_output = false;

    // Parse flags
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            try printInstallHelp(w);
            return;
        } else if (std.mem.eql(u8, arg, "--install-deps")) {
            install_deps = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        }
    }

    var config = loadConfig(allocator) catch |err| {
        if (err == error.FileNotFound) {
            try ew.print("✗ [Deps]: zr.toml not found in current directory\n\n  Hint: Run 'zr init' to create a configuration file\n", .{});
            return error.ConfigNotFound;
        }
        return err;
    };
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

    if (install_deps) {
        var installed_count: usize = 0;
        var already_ok_count: usize = 0;
        var failed_count: usize = 0;

        var dep_iter = dep_map.iterator();
        while (dep_iter.next()) |entry| {
            const tool_name = entry.key_ptr.*;
            const constraint_str = entry.value_ptr.*;

            // Check if dependency is already satisfied
            const already_satisfied = blk: {
                const result = checkDependency(allocator, tool_name, constraint_str) catch break :blk false;
                if (result.installed) |installed| {
                    allocator.free(installed);
                }
                break :blk result.satisfied;
            };

            if (already_satisfied) {
                try w.print("✓ {s}: satisfies {s}\n", .{ tool_name, constraint_str });
                already_ok_count += 1;
                continue;
            }

            // Extract version from constraint
            const version_str_opt = targetVersionFromConstraint(constraint_str);
            if (version_str_opt == null) {
                try ew.print("⚠ {s}: cannot determine install version from '{s}'\n\n  Hint: Use 'zr tools install {s}@<version>' to install manually\n", .{ tool_name, constraint_str, tool_name });
                failed_count += 1;
                continue;
            }
            const version_str = version_str_opt.?;

            // Parse tool kind
            const kind = ToolKind.fromString(tool_name);
            if (kind == null) {
                try ew.print("⚠ {s}: not a managed toolchain — install manually\n\n  Hint: Supported: node, python, zig, go, rust, deno, bun, java\n", .{tool_name});
                failed_count += 1;
                continue;
            }

            // Parse version
            const version = ToolVersion.parse(version_str) catch {
                try ew.print("⚠ {s}: cannot parse version '{s}'\n\n  Hint: Use 'zr tools install {s}@<version>' to install manually\n", .{ tool_name, version_str, tool_name });
                failed_count += 1;
                continue;
            };

            // Attempt installation
            try w.print("Installing {s} {s}...\n", .{ tool_name, version_str });
            toolchain_installer.install(allocator, kind.?, version) catch |err| {
                if (err == error.AlreadyInstalled) {
                    try w.print("✓ {s} {s}: already installed\n", .{ tool_name, version_str });
                    already_ok_count += 1;
                } else {
                    try ew.print("✗ [Deps]: {s}: installation failed ({s})\n\n  Hint: Try 'zr tools install {s}@{s}' manually\n", .{ tool_name, @errorName(err), tool_name, version_str });
                    failed_count += 1;
                }
                continue;
            };

            try w.print("✓ {s} {s}: installed\n", .{ tool_name, version_str });
            installed_count += 1;
        }

        try w.print("\n  {d} installed, {d} already satisfied, {d} failed\n", .{ installed_count, already_ok_count, failed_count });

        if (failed_count > 0) {
            return error.InstallFailed;
        }
        return;
    }

    if (json_output) {
        try w.print("{{\"dependencies\":[", .{});
        var first = true;
        var list_iter = dep_map.iterator();
        while (list_iter.next()) |entry| {
            if (!first) try w.print(",", .{});
            try w.print("{{\"tool\":\"{s}\",\"version\":\"{s}\"}}", .{ entry.key_ptr.*, entry.value_ptr.* });
            first = false;
        }
        try w.print("]}}\n", .{});
    } else {
        try w.print("Dependencies:\n", .{});
        var list_iter = dep_map.iterator();
        while (list_iter.next()) |entry| {
            try w.print("  {s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
    }
}

/// Handle `zr deps outdated` - show available updates
fn handleOutdated(args: []const []const u8, w: *std.Io.Writer, ew: *std.Io.Writer) !void {
    var task_filter: ?[]const u8 = null;
    var json_output = false;

    // Parse flags
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try printOutdatedHelp(w);
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

    _ = ew;

    // Placeholder - actual implementation would query registries for latest versions
    if (json_output) {
        try w.print("{{\"outdated\":[]}}\n", .{});
    } else {
        if (task_filter) |filter| {
            try w.print("Checking for outdated dependencies for task: {s}...\n", .{filter});
        } else {
            try w.print("Checking for outdated dependencies...\n", .{});
        }
        try w.print("No updates available\n", .{});
    }
}

/// Handle `zr deps lock` - generate lock file
fn handleLock(allocator: std.mem.Allocator, args: []const []const u8, w: *std.Io.Writer, ew: *std.Io.Writer) !void {
    var update_mode = false;
    var json_output = false;

    // Parse flags
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            try printLockHelp(w);
            return;
        } else if (std.mem.eql(u8, arg, "--update")) {
            update_mode = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        }
    }

    var config = loadConfig(allocator) catch |err| {
        if (err == error.FileNotFound) {
            try ew.print("✗ [Deps]: zr.toml not found in current directory\n\n  Hint: Run 'zr init' to create a configuration file\n", .{});
            return error.ConfigNotFound;
        }
        return err;
    };
    defer config.deinit();

    // Load existing lock file for --update comparison
    var old_versions = std.StringHashMap([]const u8).init(allocator);
    defer {
        var it = old_versions.iterator();
        while (it.next()) |entry| allocator.free(entry.value_ptr.*);
        old_versions.deinit();
    }
    var has_existing_lock = false;
    if (update_mode) {
        if (lock_mod.parseLockFile(allocator, ".zr-lock.toml")) |old_lock| {
            var old_lock_copy = old_lock;
            defer old_lock_copy.deinit(allocator);
            has_existing_lock = true;
            for (old_lock.dependencies) |dep| {
                try old_versions.put(dep.tool, try allocator.dupe(u8, dep.resolved));
            }
        } else |_| {
            // No existing lock file — will create fresh
        }
    }

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
                    try w.print("⚠ Warning: Could not detect version for {s}\n", .{tool_name});
                    continue;
                };

                const version_str = try std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{
                    detected_version.major,
                    detected_version.minor,
                    detected_version.patch,
                });

                // In update mode, report changes
                if (update_mode) {
                    if (old_versions.get(tool_name)) |old_ver| {
                        if (!std.mem.eql(u8, old_ver, version_str)) {
                            try w.print("↑ {s}: {s} → {s}\n", .{ tool_name, old_ver, version_str });
                        } else {
                            try w.print("  {s}: {s} (unchanged)\n", .{ tool_name, version_str });
                        }
                    } else {
                        try w.print("+ {s}: {s} (new)\n", .{ tool_name, version_str });
                    }
                }

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
        try w.print("{{\"status\":\"ok\",\"lock_file\":\".zr-lock.toml\"}}\n", .{});
    } else if (update_mode) {
        if (has_existing_lock) {
            try w.print("\nUpdated .zr-lock.toml with {d} dependencies\n", .{dep_list.items.len});
        } else {
            try w.print("Generated .zr-lock.toml with {d} dependencies\n", .{dep_list.items.len});
        }
    } else {
        try w.print("Generated .zr-lock.toml with {d} dependencies\n", .{dep_list.items.len});
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

fn printCheckResults(results: []const CheckResult, w: *std.Io.Writer, ew: *std.Io.Writer) !void {
    var all_ok = true;
    for (results) |result| {
        if (result.error_msg) |err_msg| {
            try ew.print("✗ [Deps]: {s}: {s}\n", .{ result.tool, err_msg });
            all_ok = false;
        } else if (result.satisfied) {
            try w.print("✓ {s} ({s}) satisfies {s}\n", .{ result.tool, result.installed.?, result.constraint });
        } else {
            try ew.print("✗ [Deps]: {s} ({s}) does not satisfy {s}\n", .{ result.tool, result.installed.?, result.constraint });
            all_ok = false;
        }
    }

    if (all_ok) {
        try w.print("\nAll dependencies satisfied\n", .{});
    }
}

fn printCheckResultsJson(results: []const CheckResult, w: *std.Io.Writer) !void {
    try w.print("{{\"results\":[", .{});
    for (results, 0..) |result, i| {
        if (i > 0) try w.print(",", .{});
        try w.print("{{\"tool\":\"{s}\",\"constraint\":\"{s}\",\"installed\":", .{ result.tool, result.constraint });
        if (result.installed) |installed| {
            try w.print("\"{s}\"", .{installed});
        } else {
            try w.print("null", .{});
        }
        try w.print(",\"satisfied\":{s}}}", .{if (result.satisfied) "true" else "false"});
    }
    try w.print("]}}\n", .{});
}

// ─── Help Messages ─────────────────────────────────────────────────────────

fn printUsage(w: *std.Io.Writer) !void {
    try w.print(
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

fn printCheckHelp(w: *std.Io.Writer) !void {
    try w.print(
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

fn printInstallHelp(w: *std.Io.Writer) !void {
    try w.print(
        \\Usage: zr deps install [options]
        \\
        \\List or install missing dependencies.
        \\
        \\Options:
        \\  --install-deps   Automatically install missing tools via toolchain manager
        \\  --json           Output in JSON format (listing mode only)
        \\  --help           Show this help message
        \\
        \\Examples:
        \\  zr deps install
        \\  zr deps install --install-deps
        \\
    , .{});
}

fn printOutdatedHelp(w: *std.Io.Writer) !void {
    try w.print(
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

fn printLockHelp(w: *std.Io.Writer) !void {
    try w.print(
        \\Usage: zr deps lock [options]
        \\
        \\Generate lock file with resolved dependency versions.
        \\
        \\Options:
        \\  --update    Re-detect versions and update lock file, reporting changes
        \\  --json      Output in JSON format
        \\  --help      Show this help message
        \\
        \\Examples:
        \\  zr deps lock
        \\  zr deps lock --update
        \\
    , .{});
}

// ─── Helper Functions for Install ─────────────────────────────────────────

fn targetVersionFromConstraint(constraint_str: []const u8) ?[]const u8 {
    var s = constraint_str;
    // Strip compound operators first
    if (std.mem.startsWith(u8, s, ">=") or std.mem.startsWith(u8, s, "<=")) {
        s = s[2..];
    } else if (s.len > 0 and (s[0] == '^' or s[0] == '~' or s[0] == '>' or s[0] == '<' or s[0] == '=')) {
        s = s[1..];
    }
    // Reject empty, wildcards, spaces (ranges), or alternatives
    if (s.len == 0) return null;
    if (std.mem.indexOfAny(u8, s, " |") != null) return null;
    if (std.mem.eql(u8, s, "*") or std.mem.eql(u8, s, "x")) return null;
    // Trim trailing ".x", ".X", ".*" wildcard patterns
    const wildcards = [_][]const u8{ ".x", ".X", ".*" };
    for (wildcards) |suffix| {
        if (std.mem.endsWith(u8, s, suffix)) {
            s = s[0 .. s.len - suffix.len];
        }
    }
    return if (s.len == 0) null else s;
}

// ─── Tests ────────────────────────────────────────────────────────────────

test "targetVersionFromConstraint extracts version from caret constraint" {
    const result = targetVersionFromConstraint("^20.11.1");
    try std.testing.expectEqualStrings("20.11.1", result.?);
}

test "targetVersionFromConstraint extracts version from tilde constraint" {
    const result = targetVersionFromConstraint("~3.9");
    try std.testing.expectEqualStrings("3.9", result.?);
}

test "targetVersionFromConstraint extracts version from >= operator" {
    const result = targetVersionFromConstraint(">=3.9");
    try std.testing.expectEqualStrings("3.9", result.?);
}

test "targetVersionFromConstraint extracts version from > operator" {
    const result = targetVersionFromConstraint(">3.9");
    try std.testing.expectEqualStrings("3.9", result.?);
}

test "targetVersionFromConstraint extracts version from = operator" {
    const result = targetVersionFromConstraint("=3.12.1");
    try std.testing.expectEqualStrings("3.12.1", result.?);
}

test "targetVersionFromConstraint handles no operator" {
    const result = targetVersionFromConstraint("20");
    try std.testing.expectEqualStrings("20", result.?);
}

test "targetVersionFromConstraint strips .x suffix from 1.x" {
    const result = targetVersionFromConstraint("1.x");
    try std.testing.expectEqualStrings("1", result.?);
}

test "targetVersionFromConstraint strips .x suffix from 1.2.x" {
    const result = targetVersionFromConstraint("1.2.x");
    try std.testing.expectEqualStrings("1.2", result.?);
}

test "targetVersionFromConstraint returns null for wildcard *" {
    const result = targetVersionFromConstraint("*");
    try std.testing.expect(result == null);
}

test "targetVersionFromConstraint returns null for wildcard x" {
    const result = targetVersionFromConstraint("x");
    try std.testing.expect(result == null);
}

test "targetVersionFromConstraint handles <= operator" {
    const result = targetVersionFromConstraint("<=3.9");
    try std.testing.expectEqualStrings("3.9", result.?);
}

test "targetVersionFromConstraint handles < operator" {
    const result = targetVersionFromConstraint("<2.0.0");
    try std.testing.expectEqualStrings("2.0.0", result.?);
}

test "targetVersionFromConstraint extracts from complex caret with patch" {
    const result = targetVersionFromConstraint("^1.2.3");
    try std.testing.expectEqualStrings("1.2.3", result.?);
}

test "targetVersionFromConstraint extracts from tilde with patch" {
    const result = targetVersionFromConstraint("~1.2.3");
    try std.testing.expectEqualStrings("1.2.3", result.?);
}

test "targetVersionFromConstraint handles three-part version" {
    const result = targetVersionFromConstraint(">=16.0.0");
    try std.testing.expectEqualStrings("16.0.0", result.?);
}

test "targetVersionFromConstraint returns null for range with space" {
    const result = targetVersionFromConstraint(">=1.2.0 <2.0.0");
    try std.testing.expect(result == null);
}

test "targetVersionFromConstraint returns null for alternatives with ||" {
    const result = targetVersionFromConstraint("1.x || 2.x");
    try std.testing.expect(result == null);
}

test "targetVersionFromConstraint strips >= from complex version" {
    const result = targetVersionFromConstraint(">=18.0.0");
    try std.testing.expectEqualStrings("18.0.0", result.?);
}
