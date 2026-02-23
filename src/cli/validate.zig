/// Validate zr.toml configuration file.
/// Checks for syntax errors, schema violations, and structural issues.
const std = @import("std");
const color = @import("../output/color.zig");
const common = @import("common.zig");
const loader = @import("../config/loader.zig");
const graph = @import("../graph/dag.zig");

pub const ValidateOptions = struct {
    /// Enable strict mode (warn about unused tasks, missing descriptions)
    strict: bool = false,
    /// Show full schema reference
    show_schema: bool = false,
};

/// Validate the configuration file.
pub fn cmdValidate(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    options: ValidateOptions,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    // Show schema if requested
    if (options.show_schema) {
        try printSchema(w, use_color);
        return 0;
    }

    // Try to load and parse the config file
    var config = common.loadConfig(
        allocator,
        config_path,
        null, // no profile for validation
        err_writer,
        use_color,
    ) catch {
        // Loading failed - error already printed by loadConfig
        try color.printError(err_writer, use_color, "\n✗ Configuration validation failed\n", .{});
        return 1;
    } orelse {
        // loadConfig returned null - error already printed
        try color.printError(err_writer, use_color, "\n✗ Configuration validation failed\n", .{});
        return 1;
    };
    defer config.deinit();

    var error_count: u32 = 0;
    var warning_count: u32 = 0;

    // Validate task definitions
    var task_iter = config.tasks.iterator();
    while (task_iter.next()) |entry| {
        const task_name = entry.key_ptr.*;
        const task = entry.value_ptr;

        // Check task name validity (no spaces, reasonable length)
        if (std.mem.indexOf(u8, task_name, " ") != null) {
            try color.printError(err_writer, use_color,
                "✗ Task '{s}': name contains spaces\n  Hint: Use underscores or hyphens instead\n\n",
                .{task_name},
            );
            error_count += 1;
        }

        if (task_name.len > 64) {
            try color.printError(err_writer, use_color,
                "✗ Task '{s}': name too long ({d} characters, max 64)\n\n",
                .{ task_name, task_name.len },
            );
            error_count += 1;
        }

        // Check that task has cmd or deps
        const has_cmd = task.cmd.len > 0;
        const has_deps = task.deps.len > 0;

        if (!has_cmd and !has_deps) {
            try color.printError(err_writer, use_color,
                "✗ Task '{s}': must have 'cmd' or 'deps'\n  Hint: Add a command to execute or dependencies to orchestrate\n\n",
                .{task_name},
            );
            error_count += 1;
        }

        // Check for whitespace-only commands
        if (has_cmd) {
            const trimmed = std.mem.trim(u8, task.cmd, &std.ascii.whitespace);
            if (trimmed.len == 0) {
                try color.printError(err_writer, use_color,
                    "✗ Task '{s}': command is empty or whitespace-only\n  Hint: Remove 'cmd' field or provide a valid command\n\n",
                    .{task_name},
                );
                error_count += 1;
            }
        }

        // Validate dependency references
        for (task.deps) |dep_name| {
            if (config.tasks.get(dep_name) == null) {
                try color.printError(err_writer, use_color,
                    "✗ Task '{s}': dependency '{s}' not found\n  Hint: Check task name spelling or add the missing task\n\n",
                    .{ task_name, dep_name },
                );
                error_count += 1;
            }
        }

        // Strict mode: warn about missing descriptions
        if (options.strict and task.description == null and has_cmd) {
            if (use_color) try err_writer.writeAll(color.Code.bright_yellow);
            try err_writer.print("⚠ Task '{s}': missing description (--strict)\n", .{task_name});
            if (use_color) try err_writer.writeAll(color.Code.reset);
            try color.printDim(err_writer, use_color, "  Hint: Add 'description = \"...\"' for better documentation\n\n", .{});
            warning_count += 1;
        }
    }

    // Validate workflow definitions
    var workflow_iter = config.workflows.iterator();
    while (workflow_iter.next()) |entry| {
        const workflow_name = entry.key_ptr.*;
        const workflow = entry.value_ptr;

        // Check workflow has stages
        if (workflow.stages.len == 0) {
            try color.printError(err_writer, use_color,
                "✗ Workflow '{s}': no stages defined\n  Hint: Add at least one [[workflows.{s}.stages]] section\n\n",
                .{ workflow_name, workflow_name },
            );
            error_count += 1;
        }

        // Validate stage task references and check for duplicates
        for (workflow.stages, 0..) |stage, i| {
            // Track tasks in this stage to detect duplicates
            var stage_tasks = std.StringHashMap(void).init(allocator);
            defer stage_tasks.deinit();

            for (stage.tasks) |task_name| {
                if (config.tasks.get(task_name) == null) {
                    try color.printError(err_writer, use_color,
                        "✗ Workflow '{s}', stage {d}: task '{s}' not found\n  Hint: Check task name spelling or add the missing task\n\n",
                        .{ workflow_name, i, task_name },
                    );
                    error_count += 1;
                }

                // Check for duplicate task in this stage
                if (stage_tasks.contains(task_name)) {
                    try color.printError(err_writer, use_color,
                        "✗ Workflow '{s}', stage {d}: task '{s}' appears multiple times\n  Hint: Remove duplicate task references\n\n",
                        .{ workflow_name, i, task_name },
                    );
                    error_count += 1;
                } else {
                    try stage_tasks.put(task_name, {});
                }
            }
        }
    }

    // Check for circular dependencies using DAG
    var all_task_names = std.ArrayList([]const u8){};
    defer all_task_names.deinit(allocator);

    var all_tasks_iter = config.tasks.iterator();
    while (all_tasks_iter.next()) |entry| {
        try all_task_names.append(allocator, entry.key_ptr.*);
    }

    // Build DAG to detect cycles
    var dag = graph.DAG.init(allocator);
    defer dag.deinit();

    for (all_task_names.items) |task_name| {
        const task = config.tasks.get(task_name).?;
        for (task.deps) |dep_name| {
            dag.addEdge(task_name, dep_name) catch |err| {
                if (err == error.CycleDetected) {
                    try color.printError(err_writer, use_color,
                        "✗ Circular dependency detected involving task '{s}'\n  Hint: Review your task dependencies to break the cycle\n\n",
                        .{task_name},
                    );
                    error_count += 1;
                } else {
                    return err;
                }
            };
        }
    }

    // Strict mode: check for unused tasks (tasks that are never dependencies)
    if (options.strict) {
        var referenced_tasks = std.StringHashMap(void).init(allocator);
        defer referenced_tasks.deinit();

        // Mark all tasks referenced in dependencies
        var dep_iter = config.tasks.iterator();
        while (dep_iter.next()) |entry| {
            for (entry.value_ptr.deps) |dep_name| {
                try referenced_tasks.put(dep_name, {});
            }
        }

        // Mark all tasks referenced in workflows
        var wf_iter = config.workflows.iterator();
        while (wf_iter.next()) |entry| {
            for (entry.value_ptr.stages) |stage| {
                for (stage.tasks) |task_name| {
                    try referenced_tasks.put(task_name, {});
                }
            }
        }

        // Warn about tasks that are never referenced
        var unused_iter = config.tasks.iterator();
        while (unused_iter.next()) |entry| {
            const task_name = entry.key_ptr.*;
            if (!referenced_tasks.contains(task_name) and entry.value_ptr.deps.len == 0) {
                // Task is standalone (not referenced anywhere, has no deps)
                // This is not necessarily bad, but worth noting in strict mode
                if (use_color) try err_writer.writeAll(color.Code.bright_yellow);
                try err_writer.print("⚠ Task '{s}': not referenced by any other task or workflow (--strict)\n", .{task_name});
                if (use_color) try err_writer.writeAll(color.Code.reset);
                try color.printDim(err_writer, use_color, "  This is fine if it's meant to be run directly via 'zr run {s}'\n\n", .{task_name});
                warning_count += 1;
            }
        }
    }

    // Print summary
    try w.writeAll("\n");

    if (error_count == 0 and warning_count == 0) {
        try color.printSuccess(w, use_color, "✓ Configuration valid\n\n", .{});

        const task_count = config.tasks.count();
        const workflow_count = config.workflows.count();

        try color.printDim(w, use_color, "  Tasks:     {d}\n", .{task_count});
        try color.printDim(w, use_color, "  Workflows: {d}\n", .{workflow_count});

        if (config.workspace) |workspace| {
            try color.printDim(w, use_color, "  Workspace: {d} members\n", .{workspace.members.len});
        }

        try w.writeAll("\n");
        return 0;
    } else if (error_count == 0) {
        // Only warnings
        if (use_color) try w.writeAll(color.Code.bright_yellow);
        try w.print("✓ Configuration valid with {d} warning(s)\n\n", .{warning_count});
        if (use_color) try w.writeAll(color.Code.reset);
        return 0;
    } else {
        // Has errors
        try color.printError(w, use_color, "✗ Configuration validation failed\n\n", .{});
        try color.printError(w, use_color, "  Errors:   {d}\n", .{error_count});

        if (warning_count > 0) {
            if (use_color) try w.writeAll(color.Code.bright_yellow);
            try w.print("  Warnings: {d}\n", .{warning_count});
            if (use_color) try w.writeAll(color.Code.reset);
        }

        try w.writeAll("\n");
        try color.printDim(w, use_color, "  Hint: Fix the errors above and run 'zr validate' again\n", .{});
        return 1;
    }
}

/// Print full schema reference.
fn printSchema(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "zr.toml Schema Reference\n\n", .{});

    try w.writeAll(
        \\[tasks.<name>]
        \\cmd = "command to execute"           # Required (or deps)
        \\description = "task description"     # Optional
        \\cwd = "working directory"            # Optional (default: config dir)
        \\deps = ["task1", "task2"]            # Optional
        \\deps_serial = true                   # Optional (run deps sequentially)
        \\env = { KEY = "value" }              # Optional
        \\timeout = "30s"                      # Optional (s, m, h)
        \\retry = 3                            # Optional (default: 0)
        \\allow_failure = true                 # Optional (default: false)
        \\condition = "platform == 'linux'"    # Optional (expression)
        \\cache = "hash"                       # Optional (fingerprint, hash, none)
        \\max_concurrent = 2                   # Optional (limit parallel instances)
        \\max_cpu = 2                          # Optional (CPU core limit)
        \\max_memory = "512MB"                 # Optional (memory limit)
        \\
        \\[tasks.<name>.matrix]                # Optional (Cartesian product)
        \\os = ["linux", "macos", "windows"]
        \\node = ["18", "20"]
        \\
        \\[workflows.<name>]
        \\description = "workflow description" # Optional
        \\fail_fast = true                     # Optional (default: false)
        \\
        \\[[workflows.<name>.stages]]
        \\tasks = ["task1", "task2"]           # Required
        \\
        \\[workspace]                          # Optional (monorepo)
        \\members = ["packages/*"]             # Glob patterns
        \\
        \\[profiles.<name>]                    # Optional
        \\env = { KEY = "value" }              # Per-profile overrides
        \\
        \\[resources]                          # Optional (global limits)
        \\max_total_memory = "4GB"
        \\max_cpu_percent = 80
        \\
        \\[plugins.<name>]                     # Optional
        \\source = "git:https://..."           # Plugin source
        \\version = "1.0.0"
        \\
    );

    try w.writeAll("\n");
    try color.printDim(w, use_color, "For full documentation, see: docs/PRD.md\n", .{});
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "cmdValidate: valid config returns success" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\description = "Build the project"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\deps = ["build"]
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_w = std.Io.Writer.fixed(&err_buf);

    const result = try cmdValidate(allocator, config_path, .{}, &out_w, &err_w, false);

    try std.testing.expectEqual(@as(u8, 0), result);
}

test "cmdValidate: missing dependency fails validation" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\deps = ["nonexistent"]
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_w = std.Io.Writer.fixed(&err_buf);

    const result = try cmdValidate(allocator, config_path, .{}, &out_w, &err_w, false);

    try std.testing.expectEqual(@as(u8, 1), result);
}

test "cmdValidate: task with spaces in name warns" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks."bad task"]
        \\cmd = "echo test"
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_w = std.Io.Writer.fixed(&err_buf);

    const result = try cmdValidate(allocator, config_path, .{}, &out_w, &err_w, false);

    // Should fail due to spaces in task name
    try std.testing.expectEqual(@as(u8, 1), result);
}

test "cmdValidate: workflow with invalid task reference fails" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[workflows.test]
        \\[[workflows.test.stages]]
        \\tasks = ["build", "nonexistent"]
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_w = std.Io.Writer.fixed(&err_buf);

    const result = try cmdValidate(allocator, config_path, .{}, &out_w, &err_w, false);

    // Should fail due to nonexistent task in workflow
    try std.testing.expectEqual(@as(u8, 1), result);
}

test "cmdValidate: strict mode warns about missing descriptions" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_w = std.Io.Writer.fixed(&err_buf);

    const result = try cmdValidate(allocator, config_path, .{ .strict = true }, &out_w, &err_w, false);

    // Should succeed with warnings
    try std.testing.expectEqual(@as(u8, 0), result);

    // Check that warning was printed
    const err_str = err_buf[0..err_w.end];
    try std.testing.expect(std.mem.indexOf(u8, err_str, "missing description") != null);
}

test "cmdValidate: schema output" {
    const allocator = std.testing.allocator;

    var out_buf: [8192]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_w = std.Io.Writer.fixed(&err_buf);

    const result = try cmdValidate(allocator, "dummy.toml", .{ .show_schema = true }, &out_w, &err_w, false);

    try std.testing.expectEqual(@as(u8, 0), result);

    const out_str = out_buf[0..out_w.end];
    try std.testing.expect(std.mem.indexOf(u8, out_str, "[tasks.<name>]") != null);
    try std.testing.expect(std.mem.indexOf(u8, out_str, "Schema Reference") != null);
}

test "cmdValidate: whitespace-only command fails" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "   "
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_w = std.Io.Writer.fixed(&err_buf);

    const result = try cmdValidate(allocator, config_path, .{}, &out_w, &err_w, false);

    try std.testing.expectEqual(@as(u8, 1), result);
    const err_str = err_buf[0..err_w.end];
    try std.testing.expect(std.mem.indexOf(u8, err_str, "whitespace-only") != null);
}

test "cmdValidate: duplicate task in workflow stage fails" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[workflows.ci]
        \\[[workflows.ci.stages]]
        \\name = "test"
        \\tasks = ["build", "build"]
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
    defer allocator.free(config_path);

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_w = std.Io.Writer.fixed(&err_buf);

    const result = try cmdValidate(allocator, config_path, .{}, &out_w, &err_w, false);

    try std.testing.expectEqual(@as(u8, 1), result);
    const err_str = err_buf[0..err_w.end];
    try std.testing.expect(std.mem.indexOf(u8, err_str, "appears multiple times") != null);
}

