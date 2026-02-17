const std = @import("std");
const loader = @import("config/loader.zig");
const dag_mod = @import("graph/dag.zig");
const topo_sort = @import("graph/topo_sort.zig");
const cycle_detect = @import("graph/cycle_detect.zig");
const scheduler = @import("exec/scheduler.zig");
const process = @import("exec/process.zig");

// Ensure tests in all imported modules are included in test binary
comptime {
    _ = loader;
    _ = dag_mod;
    _ = topo_sort;
    _ = cycle_detect;
    _ = scheduler;
    _ = process;
}

const CONFIG_FILE = "zr.toml";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var out_buf: [8192]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_writer = stdout.writer(&out_buf);

    var err_buf: [4096]u8 = undefined;
    const stderr_file = std.fs.File.stderr();
    var err_writer = stderr_file.writer(&err_buf);

    const result = run(allocator, args, &out_writer.interface, &err_writer.interface);

    // Always flush both writers before exiting
    out_writer.interface.flush() catch {};
    err_writer.interface.flush() catch {};

    if (result) |exit_code| {
        if (exit_code != 0) std.process.exit(exit_code);
    } else |err| {
        return err;
    }
}

/// Inner run function that returns an exit code.
/// Returns 0 for success, non-zero for failure.
fn run(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
) !u8 {
    if (args.len < 2) {
        try printHelp(w);
        return 0;
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        try printHelp(w);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "run")) {
        if (args.len < 3) {
            try ew.print("✗ run: missing task name\n\n  Hint: zr run <task-name>\n", .{});
            return 1;
        }
        const task_name = args[2];
        return cmdRun(allocator, task_name, w, ew);
    } else if (std.mem.eql(u8, cmd, "list")) {
        return cmdList(allocator, w, ew);
    } else if (std.mem.eql(u8, cmd, "graph")) {
        return cmdGraph(allocator, w, ew);
    } else {
        try ew.print("✗ Unknown command: {s}\n\n", .{cmd});
        try printHelp(w);
        return 1;
    }
}

fn printHelp(w: *std.Io.Writer) !void {
    try w.print(
        \\zr v0.0.4 - Zig Task Runner
        \\
        \\Usage:
        \\  zr <command> [arguments]
        \\
        \\Commands:
        \\  run <task>   Run a task and its dependencies
        \\  list         List all available tasks
        \\  graph        Show dependency tree
        \\
        \\Options:
        \\  --help, -h   Show this help message
        \\
        \\Config file: zr.toml (in current directory)
        \\
    , .{});
}

fn loadConfig(
    allocator: std.mem.Allocator,
    err_writer: *std.Io.Writer,
) !?loader.Config {
    return loader.Config.loadFromFile(allocator, CONFIG_FILE) catch |err| {
        switch (err) {
            error.FileNotFound => {
                try err_writer.print(
                    "✗ Config: {s} not found\n\n  Hint: Create a zr.toml file in the current directory\n",
                    .{CONFIG_FILE},
                );
            },
            else => {
                try err_writer.print(
                    "✗ Config: Failed to load {s}: {s}\n",
                    .{ CONFIG_FILE, @errorName(err) },
                );
            },
        }
        return null;
    };
}

fn buildDag(allocator: std.mem.Allocator, config: *const loader.Config) !dag_mod.DAG {
    var dag = dag_mod.DAG.init(allocator);
    errdefer dag.deinit();

    var it = config.tasks.iterator();
    while (it.next()) |entry| {
        const task = entry.value_ptr;
        try dag.addNode(task.name);
        for (task.deps) |dep| {
            try dag.addEdge(task.name, dep);
        }
    }

    return dag;
}

fn cmdRun(
    allocator: std.mem.Allocator,
    task_name: []const u8,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
) !u8 {
    var config = (try loadConfig(allocator, err_writer)) orelse return 1;
    defer config.deinit();

    if (config.tasks.get(task_name) == null) {
        try err_writer.print(
            "✗ run: Task '{s}' not found\n\n  Hint: Run 'zr list' to see available tasks\n",
            .{task_name},
        );
        return 1;
    }

    const task_names = [_][]const u8{task_name};
    var sched_result = scheduler.run(allocator, &config, &task_names, .{}) catch |err| {
        switch (err) {
            error.TaskNotFound => {
                try err_writer.print(
                    "✗ run: A dependency task was not found in config\n",
                    .{},
                );
            },
            error.CycleDetected => {
                try err_writer.print(
                    "✗ run: Cycle detected in task dependencies\n\n  Hint: Check your deps fields for circular references\n",
                    .{},
                );
            },
            else => {
                try err_writer.print("✗ run: Scheduler error: {s}\n", .{@errorName(err)});
            },
        }
        return 1;
    };
    defer sched_result.deinit(allocator);

    // Print results for each task that ran
    for (sched_result.results.items) |task_result| {
        if (task_result.success) {
            try w.print("✓ {s} completed ({d}ms)\n", .{ task_result.task_name, task_result.duration_ms });
        } else {
            try w.print("✗ {s} failed (exit: {d})\n", .{ task_result.task_name, task_result.exit_code });
        }
    }

    return if (sched_result.total_success) 0 else 1;
}

fn cmdList(
    allocator: std.mem.Allocator,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
) !u8 {
    var config = (try loadConfig(allocator, err_writer)) orelse return 1;
    defer config.deinit();

    try w.print("Tasks:\n", .{});

    // Collect task names for sorted output
    var names = std.ArrayList([]const u8){};
    defer names.deinit(allocator);

    var it = config.tasks.keyIterator();
    while (it.next()) |key| {
        try names.append(allocator, key.*);
    }

    // Sort for deterministic output
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    for (names.items) |name| {
        const task = config.tasks.get(name).?;
        if (task.description) |desc| {
            try w.print("  {s:<20} {s}\n", .{ name, desc });
        } else {
            try w.print("  {s}\n", .{name});
        }
    }

    return 0;
}

fn cmdGraph(
    allocator: std.mem.Allocator,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
) !u8 {
    var config = (try loadConfig(allocator, err_writer)) orelse return 1;
    defer config.deinit();

    var dag = try buildDag(allocator, &config);
    defer dag.deinit();

    // Check for cycles first
    var cycle_result = try cycle_detect.detectCycle(allocator, &dag);
    defer cycle_result.deinit(allocator);

    if (cycle_result.has_cycle) {
        try err_writer.print(
            "✗ graph: Cycle detected in dependency graph\n\n  Hint: Check your deps fields for circular references\n",
            .{},
        );
        return 1;
    }

    try w.print("Dependency Graph:\n\n", .{});

    // Get execution levels for structured output
    var levels = try topo_sort.getExecutionLevels(allocator, &dag);
    defer levels.deinit(allocator);

    for (levels.levels.items, 0..) |level, level_idx| {
        try w.print("  Level {d}:\n", .{level_idx});

        // Sort names within level for deterministic output
        var sorted_level = std.ArrayList([]const u8){};
        defer sorted_level.deinit(allocator);

        for (level.items) |name| {
            try sorted_level.append(allocator, name);
        }
        std.mem.sort([]const u8, sorted_level.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        for (sorted_level.items) |name| {
            const task = config.tasks.get(name) orelse continue;
            if (task.deps.len == 0) {
                try w.print("    {s}\n", .{name});
            } else {
                try w.print("    {s} -> [", .{name});
                for (task.deps, 0..) |dep, i| {
                    if (i > 0) try w.print(", ", .{});
                    try w.print("{s}", .{dep});
                }
                try w.print("]\n", .{});
            }
        }
    }

    return 0;
}

test "basic functionality" {
    try std.testing.expect(true);
}
