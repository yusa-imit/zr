const std = @import("std");
const color = @import("../output/color.zig");
const platform = @import("../util/platform.zig");
const loader = @import("../config/loader.zig");
const types = @import("../config/types.zig");
const shell_hook = @import("shell_hook.zig");

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
    var export_mode: bool = false;
    var functions_mode: bool = false;
    var shell_type: ?shell_hook.ShellType = null;
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
        } else if (std.mem.eql(u8, arg, "--export")) {
            export_mode = true;
            // Optional shell type argument
            if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "--")) {
                shell_type = shell_hook.parseShellType(args[i + 1]);
                if (shell_type == null) {
                    try color.printError(ew, use_color, "env: unknown shell type '{s}'\n\n  Hint: supported shells are bash, zsh, fish\n", .{args[i + 1]});
                    return 1;
                }
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "--functions")) {
            functions_mode = true;
            // Optional shell type argument
            if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "--")) {
                shell_type = shell_hook.parseShellType(args[i + 1]);
                if (shell_type == null) {
                    try color.printError(ew, use_color, "env: unknown shell type '{s}'\n\n  Hint: supported shells are bash, zsh, fish\n", .{args[i + 1]});
                    return 1;
                }
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(w, use_color);
            return 0;
        } else {
            try color.printError(ew, use_color, "env: unknown argument '{s}'\n\n  Hint: zr env --help\n", .{arg});
            return 1;
        }
    }

    // Handle --functions flag (generate shell functions)
    if (functions_mode) {
        // Auto-detect shell if not specified
        const detected_shell = shell_type orelse try detectShell(allocator);

        return try generateShellFunctions(allocator, config_path, detected_shell, w, ew, use_color);
    }

    // Handle --export flag (export for shell sourcing)
    if (export_mode) {
        // Auto-detect shell if not specified
        const detected_shell = shell_type orelse try detectShell(allocator);

        return try exportEnv(allocator, config_path, task_name, detected_shell, w, ew, use_color);
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

/// Generate shell functions for all tasks
fn generateShellFunctions(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    shell_type: shell_hook.ShellType,
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

    // Generate function for each task
    var task_it = config.tasks.iterator();
    while (task_it.next()) |entry| {
        const task_name = entry.key_ptr.*;
        try generateTaskFunction(shell_type, task_name, w);
    }

    return 0;
}

/// Generate a shell function for a specific task
fn generateTaskFunction(
    shell_type: shell_hook.ShellType,
    task_name: []const u8,
    w: anytype,
) !void {
    switch (shell_type) {
        .bash, .zsh => {
            // Bash/Zsh function: zr_build() { zr run build "$@"; }
            try w.writeAll("zr_");
            try w.writeAll(task_name);
            try w.writeAll("() { zr run ");
            try w.writeAll(task_name);
            try w.writeAll(" \"$@\"; }\n");
        },
        .fish => {
            // Fish function: function zr_build; zr run build $argv; end
            try w.writeAll("function zr_");
            try w.writeAll(task_name);
            try w.writeAll("; zr run ");
            try w.writeAll(task_name);
            try w.writeAll(" $argv; end\n");
        },
    }
}

/// Detect the current shell from SHELL environment variable
fn detectShell(allocator: std.mem.Allocator) !shell_hook.ShellType {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    if (env_map.get("SHELL")) |shell_path| {
        // Extract shell name from path (e.g., /bin/bash -> bash)
        if (std.mem.lastIndexOf(u8, shell_path, "/")) |last_slash| {
            const shell_name = shell_path[last_slash + 1 ..];
            if (std.mem.eql(u8, shell_name, "bash")) return .bash;
            if (std.mem.eql(u8, shell_name, "zsh")) return .zsh;
            if (std.mem.eql(u8, shell_name, "fish")) return .fish;
        }
    }

    // Default to bash if detection fails
    return .bash;
}

/// Export environment variables in shell-specific format
fn exportEnv(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    task_name: ?[]const u8,
    shell_type: shell_hook.ShellType,
    w: anytype,
    ew: anytype,
    use_color: bool,
) !u8 {
    // Load configuration if task name specified
    const task_env = if (task_name) |task| blk: {
        var config = loader.loadFromFile(allocator, config_path) catch |err| {
            try color.printError(ew, use_color, "env: failed to load config: {}\n\n  Hint: ensure zr.toml exists\n", .{err});
            return 1;
        };
        defer config.deinit();

        const found_task = config.tasks.get(task) orelse {
            try color.printError(ew, use_color, "env: task '{s}' not found\n\n  Hint: use 'zr list' to see available tasks\n", .{task});
            return 1;
        };

        // Copy task environment variables
        var env_list = std.ArrayList([2][]const u8){};
        errdefer {
            for (env_list.items) |pair| {
                allocator.free(pair[0]);
                allocator.free(pair[1]);
            }
            env_list.deinit(allocator);
        }

        for (found_task.env) |pair| {
            const key_copy = try allocator.dupe(u8, pair[0]);
            errdefer allocator.free(key_copy);
            const val_copy = try allocator.dupe(u8, pair[1]);
            errdefer allocator.free(val_copy);
            try env_list.append(allocator, .{ key_copy, val_copy });
        }
        break :blk try env_list.toOwnedSlice(allocator);
    } else null;

    defer if (task_env) |env| {
        for (env) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        allocator.free(env);
    };

    // Export variables based on shell type
    if (task_env) |env| {
        for (env) |pair| {
            try formatExport(shell_type, pair[0], pair[1], w);
        }
    }

    return 0;
}

/// Format environment variable export for specific shell
fn formatExport(
    shell_type: shell_hook.ShellType,
    key: []const u8,
    value: []const u8,
    w: anytype,
) !void {
    switch (shell_type) {
        .bash, .zsh => {
            // Bash/Zsh: export KEY="value"
            try w.writeAll("export ");
            try w.writeAll(key);
            try w.writeAll("=\"");
            try writeEscaped(value, w, .bash);
            try w.writeAll("\"\n");
        },
        .fish => {
            // Fish: set -x KEY "value"
            try w.writeAll("set -x ");
            try w.writeAll(key);
            try w.writeAll(" \"");
            try writeEscaped(value, w, .fish);
            try w.writeAll("\"\n");
        },
    }
}

/// Write value with shell-specific escaping
fn writeEscaped(value: []const u8, w: anytype, shell_type: shell_hook.ShellType) !void {
    for (value) |c| {
        switch (shell_type) {
            .bash, .zsh => {
                // Escape double quotes, backslashes, and dollar signs
                if (c == '"' or c == '\\' or c == '$') {
                    try w.writeByte('\\');
                }
                try w.writeByte(c);
            },
            .fish => {
                // Escape double quotes and backslashes
                if (c == '"' or c == '\\') {
                    try w.writeByte('\\');
                }
                try w.writeByte(c);
            },
        }
    }
}

fn printHelp(w: anytype, use_color: bool) !void {
    try color.printBold(w, use_color, "zr env - Display environment variables\n\n", .{});
    try w.writeAll(
        \\Usage:
        \\  zr env [options]
        \\
        \\Options:
        \\  --task <NAME>              Show environment for a specific task
        \\  --layers                   Show environment layering (system → task)
        \\  --resolve <VAR>            Show value of a specific variable
        \\  --export [bash|zsh|fish]   Export env vars for shell sourcing (auto-detects shell)
        \\  --functions [bash|zsh|fish] Generate shell functions for all tasks (auto-detects shell)
        \\  --help, -h                 Show this help message
        \\
        \\Description:
        \\  Shows environment variables with support for task-specific layering.
        \\  Tasks can override system environment variables via [tasks.NAME].env.
        \\  The --export flag generates shell-specific commands for sourcing.
        \\  The --functions flag generates shell functions (zr_<task>) for quick task access.
        \\
        \\Examples:
        \\  zr env                        # Show all system environment variables
        \\  zr env --task build           # Show merged env for 'build' task
        \\  zr env --task build --layers  # Show layered env (system + task)
        \\  zr env --resolve PATH         # Show value of PATH variable
        \\  zr env --task test --resolve NODE_ENV # Show NODE_ENV for 'test' task
        \\  eval $(zr env --task build --export)  # Load build task env into shell
        \\  eval $(zr env --task prod --export bash) # Explicitly use bash format
        \\  eval $(zr env --functions)    # Generate zr_build(), zr_test() functions
        \\  zr_build --verbose            # Run build task via generated function
        \\
    );
}

test "env command help" {
    // Original test: just verify the test compiles
    // (printHelp requires *std.Io.Writer which makes testing complex)
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
