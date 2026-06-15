const std = @import("std");
const loader = @import("../config/loader.zig");
const color = @import("../output/color.zig");

/// Handle `zr secrets <subcommand>` commands.
/// Dispatches to secretsListCommand or secretsCheckCommand based on args[0].
pub fn secretsCommand(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    config_path: []const u8,
    use_color: bool,
) !u8 {
    if (args.len < 2) {
        try color.printError(ew, use_color, "secrets: missing subcommand\n\n  Hint: zr secrets list|check\n", .{});
        return 1;
    }

    const subcmd = args[1];

    if (std.mem.eql(u8, subcmd, "--help") or std.mem.eql(u8, subcmd, "-h")) {
        try color.printInfo(w, use_color,
            "Usage: zr secrets <SUBCOMMAND>\n\n" ++
            "Manage task secrets and environment variables (v1.98.0).\n\n" ++
            "SUBCOMMANDS:\n" ++
            "  list                  List all tasks with secrets declared\n" ++
            "  check                 Validate all secrets; exit 0 if all available, 1 if any missing\n\n" ++
            "GLOBAL OPTIONS:\n" ++
            "  -h, --help            Show this help\n\n" ++
            "EXAMPLES:\n" ++
            "  zr secrets list                   # Show all tasks with secrets and their status\n" ++
            "  zr secrets check                  # Validate all secrets are available\n",
            .{},
        );
        return 0;
    }

    if (std.mem.eql(u8, subcmd, "list")) {
        return try secretsListCommand(allocator, args[2..], w, ew, config_path, use_color);
    } else if (std.mem.eql(u8, subcmd, "check")) {
        return try secretsCheckCommand(allocator, args[2..], w, ew, config_path, use_color);
    } else {
        try color.printError(ew, use_color, "secrets: unknown subcommand '{s}'\n\n  Hint: zr secrets list|check\n", .{subcmd});
        return 1;
    }
}

/// List all tasks with secrets declared, showing their names and set/missing status.
/// Exit code: 0 (always, even if some secrets are missing)
fn secretsListCommand(
    allocator: std.mem.Allocator,
    _args: []const []const u8,
    w: *std.Io.Writer,
    _ew: *std.Io.Writer,
    config_path: []const u8,
    use_color: bool,
) !u8 {
    _ = _args;
    _ = _ew;

    // Load config
    var config = try loader.loadFromFile(allocator, config_path);
    defer config.deinit();

    // Collect all tasks with secrets
    var has_secrets = false;
    var iter = config.tasks.iterator();
    while (iter.next()) |entry| {
        const task = entry.value_ptr;
        if (task.secrets) |secrets| {
            if (secrets.len > 0) {
                has_secrets = true;
                break;
            }
        }
    }

    if (!has_secrets) {
        try w.print("No tasks with secrets declared.\n", .{});
        return 0;
    }

    try color.printBold(w, use_color, "Secrets:\n", .{});

    // List each task with its secrets
    var iter2 = config.tasks.iterator();
    while (iter2.next()) |entry| {
        const task = entry.value_ptr;
        if (task.secrets) |secrets| {
            if (secrets.len > 0) {
                try w.print("  {s}\n", .{entry.key_ptr.*});
                for (secrets) |secret_name| {
                    // Check if the secret is set
                    const is_set = if (std.process.getEnvVarOwned(allocator, secret_name)) |val| blk: {
                        allocator.free(val);
                        break :blk true;
                    } else |_| false;

                    if (is_set) {
                        try color.printSuccess(w, use_color, "    [✓] {s} (set)\n", .{secret_name});
                    } else {
                        try color.printWarning(w, use_color, "    [✗] {s} (missing)\n", .{secret_name});
                    }
                }
            }
        }
    }

    return 0;
}

/// Validate all secrets across all tasks.
/// Exit code: 0 if all secrets are available, 1 if any are missing.
fn secretsCheckCommand(
    allocator: std.mem.Allocator,
    _args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    config_path: []const u8,
    use_color: bool,
) !u8 {
    _ = _args;

    // Load config
    var config = try loader.loadFromFile(allocator, config_path);
    defer config.deinit();

    // Collect all missing secrets across all tasks
    const TaskSecrets = struct {
        task_name: []const u8,
        secrets: [][]const u8,
    };
    var missing_by_task = std.ArrayList(TaskSecrets){};
    defer {
        for (missing_by_task.items) |item| {
            allocator.free(item.secrets);
        }
        missing_by_task.deinit(allocator);
    }

    var has_any_missing = false;
    var iter = config.tasks.iterator();
    while (iter.next()) |entry| {
        const task = entry.value_ptr;
        if (task.secrets) |secrets| {
            if (secrets.len > 0) {
                var task_missing = std.ArrayList([]const u8){};
                for (secrets) |secret_name| {
                    if (std.process.getEnvVarOwned(allocator, secret_name)) |val| {
                        allocator.free(val);
                    } else |_| {
                        task_missing.append(allocator, secret_name) catch {};
                        has_any_missing = true;
                    }
                }

                if (task_missing.items.len > 0) {
                    const owned_secrets = task_missing.toOwnedSlice(allocator) catch {
                        task_missing.deinit(allocator);
                        continue;
                    };
                    missing_by_task.append(allocator, .{
                        .task_name = entry.key_ptr.*,
                        .secrets = owned_secrets,
                    }) catch {
                        allocator.free(owned_secrets);
                    };
                } else {
                    task_missing.deinit(allocator);
                }
            }
        }
    }

    if (!has_any_missing) {
        try color.printSuccess(w, use_color, "All secrets available.\n", .{});
        return 0;
    }

    // Report missing secrets
    try color.printError(ew, use_color, "Missing secrets:\n", .{});
    for (missing_by_task.items) |item| {
        try color.printWarning(ew, use_color, "  {s}:\n", .{item.task_name});
        for (item.secrets) |secret_name| {
            try ew.print("    - {s}\n", .{secret_name});
        }
    }

    return 1;
}
