const std = @import("std");
const sailor = @import("sailor");
const loader = @import("../config/loader.zig");
const common = @import("common.zig");
const color = @import("../output/color.zig");
const run_cmd = @import("run.zig");
const workspace_mod = @import("workspace.zig");
const affected_util = @import("../util/affected.zig");

/// `zr affected <task> [options]`
/// Run a task on affected workspace members based on git changes.
///
/// Options:
///   --base <ref>               Git reference to compare against (default: HEAD)
///   --include-dependents       Also run on projects that depend on affected ones
///   --exclude-self             Exclude directly affected projects (only run on dependents)
///   --include-dependencies     Also run on dependencies of affected projects
///   --list                     Only list affected projects without running tasks
pub fn cmdAffected(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    profile_name: ?[]const u8,
    dry_run: bool,
    max_jobs: u32,
    config_path: []const u8,
    json_output: bool,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    if (args.len < 1) {
        try printHelp(ew, use_color);
        return 1;
    }

    // Parse options
    var base_ref: []const u8 = "HEAD";
    var include_dependents = false;
    var exclude_self = false;
    var include_dependencies = false;
    var list_only = false;
    var task_name: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--base")) {
            if (i + 1 >= args.len) {
                try color.printError(ew, use_color, "affected: --base requires a git reference\n\n  Hint: zr affected build --base origin/main\n", .{});
                return 1;
            }
            i += 1;
            base_ref = args[i];
        } else if (std.mem.eql(u8, arg, "--include-dependents")) {
            include_dependents = true;
        } else if (std.mem.eql(u8, arg, "--exclude-self")) {
            exclude_self = true;
        } else if (std.mem.eql(u8, arg, "--include-dependencies")) {
            include_dependencies = true;
        } else if (std.mem.eql(u8, arg, "--list")) {
            list_only = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(w, use_color);
            return 0;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            // This is the task name
            if (task_name == null) {
                task_name = arg;
            } else {
                try color.printError(ew, use_color, "affected: unexpected argument '{s}'\n\n  Hint: zr affected <task> [options]\n", .{arg});
                return 1;
            }
        } else {
            try color.printError(ew, use_color, "affected: unknown option '{s}'\n\n  Hint: run 'zr affected --help' for usage\n", .{arg});
            return 1;
        }
    }

    if (task_name == null and !list_only) {
        try color.printError(ew, use_color, "affected: missing task name\n\n  Hint: zr affected <task> [options]\n  Or:   zr affected --list [options]\n", .{});
        return 1;
    }

    // Load config to check if this is a workspace
    var cfg = (try common.loadConfig(allocator, config_path, profile_name, ew, use_color)) orelse return 1;
    defer cfg.deinit();

    if (cfg.workspace == null) {
        try color.printError(ew, use_color, "affected: not a workspace project\n\n  Hint: define [workspace] in {s} to use affected detection\n", .{config_path});
        return 1;
    }

    // Resolve workspace members
    const members = try workspace_mod.resolveWorkspaceMembers(allocator, cfg.workspace.?, common.CONFIG_FILE);
    defer {
        for (members) |m| allocator.free(m);
        allocator.free(members);
    }

    if (members.len == 0) {
        try color.printError(ew, use_color, "affected: no workspace members found\n\n  Hint: check your [workspace] members patterns\n", .{});
        return 1;
    }

    // Get current working directory for git operations
    const cwd = std.fs.cwd().realpathAlloc(allocator, ".") catch ".";
    defer allocator.free(cwd);

    // Detect affected projects
    var affected_result = affected_util.detectAffected(allocator, base_ref, members, cwd) catch |err| {
        try color.printError(ew, use_color, "affected: failed to detect changes: {s}\n\n  Hint: ensure git is installed and this is a git repository\n", .{@errorName(err)});
        return 1;
    };
    defer affected_result.deinit(allocator);

    // Build dependency map from workspace members for expansion
    var dep_map = std.StringHashMap([]const []const u8).init(allocator);
    defer {
        var dep_it = dep_map.iterator();
        while (dep_it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |dep| allocator.free(dep);
            allocator.free(entry.value_ptr.*);
        }
        dep_map.deinit();
    }

    for (members) |member_path| {
        const member_cfg_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ member_path, common.CONFIG_FILE });
        defer allocator.free(member_cfg_path);

        var member_cfg = loader.loadFromFile(allocator, member_cfg_path) catch continue;
        defer member_cfg.deinit();

        if (member_cfg.workspace) |member_ws| {
            if (member_ws.member_dependencies.len > 0) {
                const deps_copy = try allocator.alloc([]const u8, member_ws.member_dependencies.len);
                for (member_ws.member_dependencies, 0..) |dep, dep_idx| {
                    deps_copy[dep_idx] = try allocator.dupe(u8, dep);
                }
                const key = try allocator.dupe(u8, member_path);
                try dep_map.put(key, deps_copy);
            }
        }
    }

    // Expand affected projects to include dependents if requested
    if (include_dependents) {
        try affected_util.expandWithDependents(allocator, &affected_result, dep_map);
    }

    // Build final project list
    var final_projects = std.ArrayList([]const u8){};
    defer {
        for (final_projects.items) |p| allocator.free(p);
        final_projects.deinit(allocator);
    }

    if (exclude_self) {
        // Only include dependents, not the directly affected projects
        for (members) |m| {
            if (affected_result.contains(m)) {
                // Check if this was in the original affected set
                var is_original = false;
                var it = affected_result.projects.iterator();
                while (it.next()) |entry| {
                    if (std.mem.eql(u8, entry.key_ptr.*, m)) {
                        is_original = true;
                        break;
                    }
                }
                // Only include if it's a dependent (added by expansion), not original
                if (!is_original) {
                    try final_projects.append(allocator, try allocator.dupe(u8, m));
                }
            }
        }
    } else {
        // Include all affected (original + dependents if expanded)
        for (members) |m| {
            if (affected_result.contains(m)) {
                try final_projects.append(allocator, try allocator.dupe(u8, m));
            }
        }
    }

    // Handle --include-dependencies: add dependencies of affected projects
    if (include_dependencies) {
        var deps_to_add = std.ArrayList([]const u8){};
        defer {
            for (deps_to_add.items) |d| allocator.free(d);
            deps_to_add.deinit(allocator);
        }

        for (final_projects.items) |proj| {
            if (dep_map.get(proj)) |deps| {
                for (deps) |dep| {
                    // Check if already in final_projects
                    var already_added = false;
                    for (final_projects.items) |fp| {
                        if (std.mem.eql(u8, fp, dep)) {
                            already_added = true;
                            break;
                        }
                    }
                    if (!already_added) {
                        try deps_to_add.append(allocator, try allocator.dupe(u8, dep));
                    }
                }
            }
        }

        for (deps_to_add.items) |dep| {
            try final_projects.append(allocator, try allocator.dupe(u8, dep));
        }
    }

    if (final_projects.items.len == 0) {
        if (list_only) {
            if (!json_output) {
                try color.printSuccess(w, use_color, "No affected projects found\n", .{});
            } else {
                try w.print("{{\"affected\":[]}}\n", .{});
            }
            return 0;
        } else {
            try color.printSuccess(w, use_color, "No affected projects — nothing to run\n", .{});
            return 0;
        }
    }

    // List mode: just print affected projects
    if (list_only) {
        if (json_output) {
            const JsonArr = sailor.fmt.JsonArray(*std.Io.Writer);
            try w.writeAll("{\"affected\":");
            var arr = try JsonArr.init(w);
            for (final_projects.items) |proj| {
                try arr.addString(proj);
            }
            try arr.end();
            try w.writeAll("}\n");
        } else {
            try color.printHeader(w, use_color, "Affected projects ({d}):\n", .{final_projects.items.len});
            for (final_projects.items) |proj| {
                try w.print("  • {s}\n", .{proj});
            }
        }
        return 0;
    }

    // Run task on affected projects
    // Use workspace run logic with filtered members
    if (!json_output) {
        try color.printHeader(w, use_color, "Running task '{s}' on {d} affected project(s)...\n\n", .{ task_name.?, final_projects.items.len });
    }

    // Delegate to workspace run with filtered members
    return workspace_mod.cmdWorkspaceRunFiltered(
        allocator,
        task_name.?,
        final_projects.items,
        profile_name,
        dry_run,
        max_jobs,
        config_path,
        json_output,
        w,
        ew,
        use_color,
    );
}

fn printHelp(w: *std.Io.Writer, use_color: bool) !void {
    try color.printHeader(w, use_color, "zr affected — Run tasks on affected workspace members\n\n", .{});
    try w.print(
        \\Usage:
        \\  zr affected <task> [options]
        \\  zr affected --list [options]
        \\
        \\Options:
        \\  --base <ref>               Git reference to compare against (default: HEAD)
        \\  --include-dependents       Also run on projects that depend on affected ones
        \\  --exclude-self             Exclude directly affected projects (only run on dependents)
        \\  --include-dependencies     Also run on dependencies of affected projects
        \\  --list                     Only list affected projects without running tasks
        \\  --help, -h                 Show this help message
        \\
        \\Examples:
        \\  zr affected build                          # Run build on projects changed since HEAD
        \\  zr affected test --base origin/main        # Run test on projects changed since origin/main
        \\  zr affected lint --include-dependents      # Run lint on affected + their dependents
        \\  zr affected deploy --exclude-self          # Run deploy only on dependents of affected
        \\  zr affected --list --base main             # Just list affected projects
        \\
        \\Global flags (before 'affected'):
        \\  --jobs, -j <N>            Max parallel tasks
        \\  --dry-run, -n             Show what would run without executing
        \\  --profile, -p <name>      Activate a named profile
        \\  --config <path>           Config file path
        \\  --format, -f <fmt>        Output format: text or json
        \\
    , .{});
}

test "affected: help prints" {
    // Test that printHelp compiles and runs without error
    const file = std.fs.File.stdout();
    var buf: [1024]u8 = undefined;
    var writer = file.writer(&buf);
    // Call printHelp - it will write to stdout but we just care it doesn't crash
    _ = printHelp(&writer.interface, false) catch {};
}
