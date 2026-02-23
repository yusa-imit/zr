const std = @import("std");
const color = @import("../output/color.zig");
const platform = @import("../util/platform.zig");
const loader = @import("../config/loader.zig");
const types = @import("../config/types.zig");

/// Display environment variables from the system
pub fn cmdEnv(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    config_path: []const u8,
    w: anytype,
    ew: anytype,
    use_color: bool,
) !u8 {
    // Parse arguments
    var resolve_var: ?[]const u8 = null;
    var task_name: ?[]const u8 = null;
    var show_layers: bool = false;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--resolve")) {
            if (i + 1 < args.len) {
                resolve_var = args[i + 1];
                i += 1;
            } else {
                try color.printError(ew, use_color, "env: --resolve requires a variable name\n\n  Hint: zr env --resolve VAR_NAME\n", .{});
                return 1;
            }
        } else if (std.mem.eql(u8, arg, "--task")) {
            if (i + 1 < args.len) {
                task_name = args[i + 1];
                i += 1;
            } else {
                try color.printError(ew, use_color, "env: --task requires a task name\n\n  Hint: zr env --task TASK_NAME\n", .{});
                return 1;
            }
        } else if (std.mem.eql(u8, arg, "--layers")) {
            show_layers = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(w, use_color);
            return 0;
        } else {
            try color.printError(ew, use_color, "env: unknown argument '{s}'\n\n  Hint: zr env --help\n", .{arg});
            return 1;
        }
    }

    // Get system environment
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    // Handle --task flag (show task-specific environment)
    if (task_name) |task| {
        return try displayTaskEnv(allocator, config_path, task, resolve_var, show_layers, w, ew, use_color);
    }

    // Handle --resolve flag (show single variable)
    if (resolve_var) |var_name| {
        if (env_map.get(var_name)) |value| {
            try color.printBold(w, use_color, "{s}", .{var_name});
            try w.writeAll("=");
            try color.printSuccess(w, use_color, "{s}\n", .{value});
        } else {
            try color.printError(ew, use_color, "Variable '{s}' not found in environment\n", .{var_name});
            return 1;
        }
        return 0;
    }

    // Display all environment variables
    try displayEnv(allocator, &env_map, w, use_color);
    return 0;
}

fn displayEnv(
    allocator: std.mem.Allocator,
    env_map: *std.process.EnvMap,
    w: anytype,
    use_color: bool,
) !void {
    try color.printBold(w, use_color, "Environment:\n\n", .{});

    // Collect and sort keys
    var keys = std.ArrayList([]const u8){};
    defer keys.deinit(allocator);

    var it = env_map.iterator();
    while (it.next()) |entry| {
        try keys.append(allocator, entry.key_ptr.*);
    }

    std.mem.sort([]const u8, keys.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    // Print variables
    for (keys.items) |key| {
        const value = env_map.get(key).?;
        try color.printSuccess(w, use_color, "  {s}", .{key});
        try w.writeAll("=");
        try color.printDim(w, use_color, "{s}\n", .{value});
    }
}

/// Display task-specific environment with layering
fn displayTaskEnv(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    task_name: []const u8,
    resolve_var: ?[]const u8,
    show_layers: bool,
    w: anytype,
    ew: anytype,
    use_color: bool,
) !u8 {
    // Load configuration
    var config = loader.loadFromFile(allocator, config_path) catch |err| {
        try color.printError(ew, use_color, "env: failed to load config: {}\n\n  Hint: ensure zr.toml exists\n", .{err});
        return 1;
    };
    defer config.deinit();

    // Find the task
    const task = config.tasks.get(task_name) orelse {
        try color.printError(ew, use_color, "env: task '{s}' not found\n\n  Hint: use 'zr list' to see available tasks\n", .{task_name});
        return 1;
    };

    // Get system environment
    var system_env = try std.process.getEnvMap(allocator);
    defer system_env.deinit();

    // Build merged environment (system + task-specific)
    var merged_env = std.StringArrayHashMap([]const u8).init(allocator);
    defer merged_env.deinit();

    // Layer 1: System environment
    var sys_it = system_env.iterator();
    while (sys_it.next()) |entry| {
        try merged_env.put(entry.key_ptr.*, entry.value_ptr.*);
    }

    // Layer 2: Task-specific overrides
    for (task.env) |pair| {
        try merged_env.put(pair[0], pair[1]);
    }

    // Handle --resolve flag for specific variable
    if (resolve_var) |var_name| {
        if (merged_env.get(var_name)) |value| {
            try color.printBold(w, use_color, "{s}", .{var_name});
            try w.writeAll("=");
            try color.printSuccess(w, use_color, "{s}\n", .{value});

            // Show source layer if requested
            if (show_layers) {
                const from_task = blk: {
                    for (task.env) |pair| {
                        if (std.mem.eql(u8, pair[0], var_name)) break :blk true;
                    }
                    break :blk false;
                };
                try color.printDim(w, use_color, "  (from: {s})\n", .{if (from_task) "task" else "system"});
            }
        } else {
            try color.printError(ew, use_color, "Variable '{s}' not found in task '{s}' environment\n", .{ var_name, task_name });
            return 1;
        }
        return 0;
    }

    // Display layered environment for task
    if (show_layers) {
        try color.printBold(w, use_color, "Environment for task '{s}' (layered):\n\n", .{task_name});

        // Show system layer
        try color.printDim(w, use_color, "Layer 1: System Environment ({} variables)\n", .{system_env.count()});

        // Show task layer
        if (task.env.len > 0) {
            try color.printDim(w, use_color, "Layer 2: Task Overrides ({} variables)\n\n", .{task.env.len});

            try color.printBold(w, use_color, "Task-specific variables:\n", .{});
            for (task.env) |pair| {
                try w.writeAll("  ");
                try color.printSuccess(w, use_color, "{s}", .{pair[0]});
                try w.writeAll("=");
                try color.printDim(w, use_color, "{s}\n", .{pair[1]});
            }
            try w.writeAll("\n");
        } else {
            try color.printDim(w, use_color, "Layer 2: Task Overrides (none)\n\n", .{});
        }
    } else {
        try color.printBold(w, use_color, "Environment for task '{s}':\n\n", .{task_name});
    }

    // Collect and sort all keys
    var keys = std.ArrayList([]const u8){};
    defer keys.deinit(allocator);

    var merged_it = merged_env.iterator();
    while (merged_it.next()) |entry| {
        try keys.append(allocator, entry.key_ptr.*);
    }

    std.mem.sort([]const u8, keys.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    // Print merged environment
    if (!show_layers) {
        for (keys.items) |key| {
            const value = merged_env.get(key).?;

            // Highlight task-specific overrides
            const is_override = blk: {
                for (task.env) |pair| {
                    if (std.mem.eql(u8, pair[0], key)) break :blk true;
                }
                break :blk false;
            };

            try w.writeAll("  ");
            if (is_override) {
                try color.printSuccess(w, use_color, "{s}", .{key});
                try w.writeAll("=");
                try color.printBold(w, use_color, "{s}", .{value});
                try color.printDim(w, use_color, " (task)\n", .{});
            } else {
                try color.printDim(w, use_color, "{s}", .{key});
                try w.writeAll("=");
                try color.printDim(w, use_color, "{s}\n", .{value});
            }
        }
    }

    return 0;
}

fn printHelp(w: anytype, use_color: bool) !void {
    try color.printBold(w, use_color, "zr env - Display environment variables\n\n", .{});
    try w.writeAll(
        \\Usage:
        \\  zr env [options]
        \\
        \\Options:
        \\  --task <NAME>      Show environment for a specific task
        \\  --layers           Show environment layering (system → task)
        \\  --resolve <VAR>    Show value of a specific variable
        \\  --help, -h         Show this help message
        \\
        \\Description:
        \\  Shows environment variables with support for task-specific layering.
        \\  Tasks can override system environment variables via [tasks.NAME].env.
        \\
        \\Examples:
        \\  zr env                      # Show all system environment variables
        \\  zr env --task build         # Show merged env for 'build' task
        \\  zr env --task build --layers # Show layered env (system + task)
        \\  zr env --resolve PATH       # Show value of PATH variable
        \\  zr env --task test --resolve NODE_ENV # Show NODE_ENV for 'test' task
        \\
    );
}

test "env command help" {
    const testing = std.testing;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(testing.allocator);

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var w = stdout.writer(&out_buf);

    try printHelp(&w.interface, false);

    try testing.expect(true); // Just ensure it compiles
}

test "env task-specific display" {
    const testing = std.testing;

    // Create a temporary zr.toml with task env
    const tmp_dir = testing.tmpDir(.{});
    var dir = try tmp_dir.dir.makeOpenPath(".", .{});
    defer dir.close();

    const config_content =
        \\[tasks.build]
        \\cmd = "echo build"
        \\env = [["NODE_ENV", "production"], ["DEBUG", "true"]]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\env = [["NODE_ENV", "test"]]
        \\
    ;

    try dir.writeFile(.{ .sub_path = "zr.toml", .data = config_content });

    // Get the temp path
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const temp_path = try tmp_dir.dir.realpath(".", &path_buf);
    const config_path = try std.fmt.allocPrint(testing.allocator, "{s}/zr.toml", .{temp_path});
    defer testing.allocator.free(config_path);

    // Test loading the config
    var config = try loader.loadFromFile(testing.allocator, config_path);
    defer config.deinit();

    // Verify task env is loaded
    const build_task = config.tasks.get("build").?;
    try testing.expectEqual(@as(usize, 2), build_task.env.len);
    try testing.expectEqualStrings("NODE_ENV", build_task.env[0][0]);
    try testing.expectEqualStrings("production", build_task.env[0][1]);

    const test_task = config.tasks.get("test").?;
    try testing.expectEqual(@as(usize, 1), test_task.env.len);
    try testing.expectEqualStrings("NODE_ENV", test_task.env[0][0]);
    try testing.expectEqualStrings("test", test_task.env[0][1]);
}

test "env display with task overrides" {
    const testing = std.testing;

    // Create test environment map
    var env_map = std.StringArrayHashMap([]const u8).init(testing.allocator);
    defer env_map.deinit();

    try env_map.put("PATH", "/usr/bin");
    try env_map.put("HOME", "/home/user");
    try env_map.put("NODE_ENV", "development");

    // Simulate task overrides
    const task_env = [_][2][]const u8{
        .{ "NODE_ENV", "production" },
        .{ "DEBUG", "true" },
    };

    // Build merged environment
    var merged = std.StringArrayHashMap([]const u8).init(testing.allocator);
    defer merged.deinit();

    // Add system vars
    var it = env_map.iterator();
    while (it.next()) |entry| {
        try merged.put(entry.key_ptr.*, entry.value_ptr.*);
    }

    // Apply task overrides
    for (task_env) |pair| {
        try merged.put(pair[0], pair[1]);
    }

    // Verify NODE_ENV was overridden
    try testing.expectEqualStrings("production", merged.get("NODE_ENV").?);

    // Verify DEBUG was added
    try testing.expectEqualStrings("true", merged.get("DEBUG").?);

    // Verify system vars still present
    try testing.expectEqualStrings("/usr/bin", merged.get("PATH").?);
    try testing.expectEqualStrings("/home/user", merged.get("HOME").?);
}
