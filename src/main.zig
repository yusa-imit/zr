const std = @import("std");
const loader = @import("config/loader.zig");
const dag_mod = @import("graph/dag.zig");
const topo_sort = @import("graph/topo_sort.zig");
const cycle_detect = @import("graph/cycle_detect.zig");
const scheduler = @import("exec/scheduler.zig");
const process = @import("exec/process.zig");
const color = @import("output/color.zig");

// Ensure tests in all imported modules are included in test binary
comptime {
    _ = loader;
    _ = dag_mod;
    _ = topo_sort;
    _ = cycle_detect;
    _ = scheduler;
    _ = process;
    _ = color;
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

    const use_color = color.isTty(stdout);
    const result = run(allocator, args, &out_writer.interface, &err_writer.interface, use_color);

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
    use_color: bool,
) !u8 {
    if (args.len < 2) {
        try printHelp(w, use_color);
        return 0;
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        try printHelp(w, use_color);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "run")) {
        if (args.len < 3) {
            try color.printError(ew, use_color, "run: missing task name\n\n  Hint: zr run <task-name>\n", .{});
            return 1;
        }
        const task_name = args[2];
        return cmdRun(allocator, task_name, w, ew, use_color);
    } else if (std.mem.eql(u8, cmd, "list")) {
        return cmdList(allocator, w, ew, use_color);
    } else if (std.mem.eql(u8, cmd, "graph")) {
        return cmdGraph(allocator, w, ew, use_color);
    } else {
        try color.printError(ew, use_color, "Unknown command: {s}\n\n", .{cmd});
        try printHelp(w, use_color);
        return 1;
    }
}

fn printHelp(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "zr v0.0.4", .{});
    try w.print(" - Zig Task Runner\n\n", .{});
    try color.printBold(w, use_color, "Usage:\n", .{});
    try w.print("  zr <command> [arguments]\n\n", .{});
    try color.printBold(w, use_color, "Commands:\n", .{});
    try w.print("  run <task>   Run a task and its dependencies\n", .{});
    try w.print("  list         List all available tasks\n", .{});
    try w.print("  graph        Show dependency tree\n\n", .{});
    try color.printBold(w, use_color, "Options:\n", .{});
    try w.print("  --help, -h   Show this help message\n\n", .{});
    try color.printDim(w, use_color, "Config file: zr.toml (in current directory)\n", .{});
}

fn loadConfig(
    allocator: std.mem.Allocator,
    err_writer: *std.Io.Writer,
) !?loader.Config {
    // Color is disabled for config errors since we don't have a TTY handle here;
    // callers should pass use_color if needed. For simplicity, detect directly.
    const use_color = color.isTty(std.fs.File.stderr());
    return loader.Config.loadFromFile(allocator, CONFIG_FILE) catch |err| {
        switch (err) {
            error.FileNotFound => {
                try color.printError(err_writer, use_color,
                    "Config: {s} not found\n\n  Hint: Create a zr.toml file in the current directory\n",
                    .{CONFIG_FILE},
                );
            },
            else => {
                try color.printError(err_writer, use_color,
                    "Config: Failed to load {s}: {s}\n",
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
    use_color: bool,
) !u8 {
    var config = (try loadConfig(allocator, err_writer)) orelse return 1;
    defer config.deinit();

    if (config.tasks.get(task_name) == null) {
        try color.printError(err_writer, use_color,
            "run: Task '{s}' not found\n\n  Hint: Run 'zr list' to see available tasks\n",
            .{task_name},
        );
        return 1;
    }

    const task_names = [_][]const u8{task_name};
    var sched_result = scheduler.run(allocator, &config, &task_names, .{}) catch |err| {
        switch (err) {
            error.TaskNotFound => {
                try color.printError(err_writer, use_color,
                    "run: A dependency task was not found in config\n", .{});
            },
            error.CycleDetected => {
                try color.printError(err_writer, use_color,
                    "run: Cycle detected in task dependencies\n\n  Hint: Check your deps fields for circular references\n",
                    .{},
                );
            },
            else => {
                try color.printError(err_writer, use_color,
                    "run: Scheduler error: {s}\n", .{@errorName(err)});
            },
        }
        return 1;
    };
    defer sched_result.deinit(allocator);

    // Print results for each task that ran
    for (sched_result.results.items) |task_result| {
        if (task_result.success) {
            try color.printSuccess(w, use_color,
                "{s} ", .{task_result.task_name});
            try color.printDim(w, use_color,
                "({d}ms)\n", .{task_result.duration_ms});
        } else {
            try color.printError(w, use_color,
                "{s} ", .{task_result.task_name});
            try color.printDim(w, use_color,
                "(exit: {d})\n", .{task_result.exit_code});
        }
    }

    return if (sched_result.total_success) 0 else 1;
}

fn cmdList(
    allocator: std.mem.Allocator,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var config = (try loadConfig(allocator, err_writer)) orelse return 1;
    defer config.deinit();

    try color.printHeader(w, use_color, "Tasks:", .{});

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
        try w.print("  ", .{});
        try color.printInfo(w, use_color, "{s:<20}", .{name});
        if (task.description) |desc| {
            try color.printDim(w, use_color, " {s}", .{desc});
        }
        try w.print("\n", .{});
    }

    return 0;
}

fn cmdGraph(
    allocator: std.mem.Allocator,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    var config = (try loadConfig(allocator, err_writer)) orelse return 1;
    defer config.deinit();

    var dag = try buildDag(allocator, &config);
    defer dag.deinit();

    // Check for cycles first
    var cycle_result = try cycle_detect.detectCycle(allocator, &dag);
    defer cycle_result.deinit(allocator);

    if (cycle_result.has_cycle) {
        try color.printError(err_writer, use_color,
            "graph: Cycle detected in dependency graph\n\n  Hint: Check your deps fields for circular references\n",
            .{},
        );
        return 1;
    }

    try color.printHeader(w, use_color, "Dependency Graph:", .{});
    try w.print("\n", .{});

    // Get execution levels for structured output
    var levels = try topo_sort.getExecutionLevels(allocator, &dag);
    defer levels.deinit(allocator);

    for (levels.levels.items, 0..) |level, level_idx| {
        try color.printDim(w, use_color, "  Level {d}:\n", .{level_idx});

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
            try w.print("    ", .{});
            try color.printInfo(w, use_color, "{s}", .{name});
            if (task.deps.len > 0) {
                try color.printDim(w, use_color, " -> [", .{});
                for (task.deps, 0..) |dep, i| {
                    if (i > 0) try color.printDim(w, use_color, ", ", .{});
                    try color.printDim(w, use_color, "{s}", .{dep});
                }
                try color.printDim(w, use_color, "]", .{});
            }
            try w.print("\n", .{});
        }
    }

    return 0;
}

test "basic functionality" {
    try std.testing.expect(true);
}
