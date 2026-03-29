/// Validate zr.toml configuration file.
/// Checks for syntax errors, schema violations, and structural issues.
const std = @import("std");
const color = @import("../output/color.zig");
const common = @import("common.zig");
const loader = @import("../config/loader.zig");
const graph = @import("../graph/dag.zig");
const levenshtein = @import("../util/levenshtein.zig");
const expr = @import("../config/expr.zig");

pub const ValidateOptions = struct {
    /// Enable strict mode (treat warnings as errors)
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
                // Missing dependency - suggest similar task names
                var all_task_names_list = std.ArrayList([]const u8){};
                defer all_task_names_list.deinit(allocator);

                var dep_names_iter = config.tasks.iterator();
                while (dep_names_iter.next()) |dep_entry| {
                    try all_task_names_list.append(allocator, dep_entry.key_ptr.*);
                }

                const suggestions = try levenshtein.findClosestMatches(
                    allocator,
                    dep_name,
                    all_task_names_list.items,
                    3, // max edit distance
                    3, // max suggestions
                );
                defer allocator.free(suggestions);

                try color.printError(err_writer, use_color,
                    "✗ Task '{s}': dependency '{s}' not found\n",
                    .{ task_name, dep_name },
                );

                if (suggestions.len > 0) {
                    try err_writer.writeAll("  Did you mean: ");
                    for (suggestions, 0..) |sug, i| {
                        if (i > 0) try err_writer.writeAll(", ");
                        if (use_color) try err_writer.writeAll(color.Code.cyan);
                        try err_writer.writeAll(sug.name);
                        if (use_color) try err_writer.writeAll(color.Code.reset);
                    }
                    try err_writer.writeAll("?\n\n");
                } else {
                    try color.printDim(err_writer, use_color, "  Hint: Check task name spelling or add the missing task\n\n", .{});
                }

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
                    // Missing task in workflow - suggest similar task names
                    var all_task_names_list = std.ArrayList([]const u8){};
                    defer all_task_names_list.deinit(allocator);

                    var wf_task_iter = config.tasks.iterator();
                    while (wf_task_iter.next()) |wf_entry| {
                        try all_task_names_list.append(allocator, wf_entry.key_ptr.*);
                    }

                    const suggestions = try levenshtein.findClosestMatches(
                        allocator,
                        task_name,
                        all_task_names_list.items,
                        3, // max edit distance
                        3, // max suggestions
                    );
                    defer allocator.free(suggestions);

                    try color.printError(err_writer, use_color,
                        "✗ Workflow '{s}', stage {d}: task '{s}' not found\n",
                        .{ workflow_name, i, task_name },
                    );

                    if (suggestions.len > 0) {
                        try err_writer.writeAll("  Did you mean: ");
                        for (suggestions, 0..) |sug, idx| {
                            if (idx > 0) try err_writer.writeAll(", ");
                            if (use_color) try err_writer.writeAll(color.Code.cyan);
                            try err_writer.writeAll(sug.name);
                            if (use_color) try err_writer.writeAll(color.Code.reset);
                        }
                        try err_writer.writeAll("?\n\n");
                    } else {
                        try color.printDim(err_writer, use_color, "  Hint: Check task name spelling or add the missing task\n\n", .{});
                    }

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

        // Add conditional dependencies for cycle detection
        for (task.deps_if) |dep_if| {
            // For validation, always add the edge (cycle detection doesn't depend on condition value)
            dag.addEdge(task_name, dep_if.task) catch |err| {
                if (err == error.CycleDetected) {
                    try color.printError(err_writer, use_color,
                        "✗ Circular dependency detected involving task '{s}' (conditional)\n  Hint: Review your task dependencies to break the cycle\n\n",
                        .{task_name},
                    );
                    error_count += 1;
                } else {
                    return err;
                }
            };
        }

        // Add optional dependencies for cycle detection (only if they exist)
        for (task.deps_optional) |dep_name| {
            if (config.tasks.contains(dep_name)) {
                dag.addEdge(task_name, dep_name) catch |err| {
                    if (err == error.CycleDetected) {
                        try color.printError(err_writer, use_color,
                            "✗ Circular dependency detected involving task '{s}' (optional)\n  Hint: Review your task dependencies to break the cycle\n\n",
                            .{task_name},
                        );
                        error_count += 1;
                    } else {
                        return err;
                    }
                };
            }
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
            // Also mark conditional dependencies
            for (entry.value_ptr.deps_if) |dep_if| {
                try referenced_tasks.put(dep_if.task, {});
            }
            // Also mark optional dependencies
            for (entry.value_ptr.deps_optional) |dep_name| {
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

    // Validate expression syntax for conditions
    {
        var expr_iter = config.tasks.iterator();
        while (expr_iter.next()) |entry| {
            const task_name = entry.key_ptr.*;
            const task = entry.value_ptr;

            if (task.condition) |condition| {
                // Try to parse the expression to check syntax
                var diag_ctx = expr.DiagContext.init(allocator);
                defer diag_ctx.deinit();

                const result = expr.evalConditionWithDiag(allocator, condition, null, null, &diag_ctx) catch |err| {
                    try color.printError(err_writer, use_color,
                        "✗ Task '{s}': invalid expression syntax in 'condition'\n",
                        .{task_name},
                    );
                    try err_writer.print("  Expression: {s}\n", .{condition});
                    try err_writer.print("  Error: {s}\n", .{@errorName(err)});
                    try diag_ctx.formatStackTrace(err_writer);
                    try err_writer.writeAll("\n");
                    error_count += 1;
                    continue;
                };
                _ = result; // Parsed successfully
            }

            // Validate conditional dependencies
            for (task.deps_if) |dep_if| {
                var diag_ctx = expr.DiagContext.init(allocator);
                defer diag_ctx.deinit();

                const result = expr.evalConditionWithDiag(allocator, dep_if.condition, null, null, &diag_ctx) catch |err| {
                    try color.printError(err_writer, use_color,
                        "✗ Task '{s}': invalid expression syntax in 'deps_if' condition\n",
                        .{task_name},
                    );
                    try err_writer.print("  Expression: {s}\n", .{dep_if.condition});
                    try err_writer.print("  Error: {s}\n", .{@errorName(err)});
                    try diag_ctx.formatStackTrace(err_writer);
                    try err_writer.writeAll("\n");
                    error_count += 1;
                    continue;
                };
                _ = result;
            }
        }
    }

    // Performance warnings: check for excessive task count
    const task_count = config.tasks.count();
    if (task_count > 100) {
        if (use_color) try err_writer.writeAll(color.Code.bright_yellow);
        try err_writer.print("⚠ Performance: configuration has {d} tasks (>100)\n", .{task_count});
        if (use_color) try err_writer.writeAll(color.Code.reset);
        try color.printDim(err_writer, use_color, "  Hint: Consider splitting into multiple config files or using workspace for large projects\n\n", .{});
        warning_count += 1;
    }

    // Performance warnings: check for deep dependency chains
    {
        var max_depth: usize = 0;
        var deepest_task: []const u8 = "";

        var depth_iter = config.tasks.iterator();
        while (depth_iter.next()) |entry| {
            const task_name = entry.key_ptr.*;
            const depth = try calculateDepChainDepth(allocator, &config, task_name);
            if (depth > max_depth) {
                max_depth = depth;
                deepest_task = task_name;
            }
        }

        if (max_depth > 10) {
            if (use_color) try err_writer.writeAll(color.Code.bright_yellow);
            try err_writer.print("⚠ Performance: task '{s}' has deep dependency chain (depth: {d}, >10)\n", .{ deepest_task, max_depth });
            if (use_color) try err_writer.writeAll(color.Code.reset);
            try color.printDim(err_writer, use_color, "  Hint: Deep dependency chains can slow down execution planning\n\n", .{});
            warning_count += 1;
        }
    }

    // Check for duplicate task names across imports (namespace collisions)
    if (config.imports.len > 0) {
        var seen_tasks = std.StringHashMap([]const u8).init(allocator);
        defer seen_tasks.deinit();

        // First, track tasks from main config
        var main_iter = config.tasks.iterator();
        while (main_iter.next()) |entry| {
            try seen_tasks.put(entry.key_ptr.*, "main config");
        }

        // Then check imported configs (note: imports are already merged into config.tasks)
        // We detect duplicates by checking if task definitions came from different sources
        // This is a heuristic - we warn about potential collisions
        if (config.tasks.count() > 0 and config.imports.len > 1) {
            if (use_color) try err_writer.writeAll(color.Code.bright_yellow);
            try err_writer.print("⚠ Configuration uses {d} imports - watch for namespace collisions\n", .{config.imports.len});
            if (use_color) try err_writer.writeAll(color.Code.reset);
            try color.printDim(err_writer, use_color, "  Hint: Consider using unique task name prefixes for each imported file\n\n", .{});
            warning_count += 1;
        }
    }

    // Validate plugin configurations (if any)
    for (config.plugins) |plugin| {
        // Check required fields
        if (plugin.source.len == 0) {
            try color.printError(err_writer, use_color,
                "✗ Plugin '{s}': missing 'source' field\n  Hint: Add 'source = \"git:https://...\"' or 'source = \"./path/to/plugin\"'\n\n",
                .{plugin.name},
            );
            error_count += 1;
        }

        // Validate source format
        if (plugin.source.len > 0) {
            const has_protocol = std.mem.indexOf(u8, plugin.source, "://") != null or
                std.mem.startsWith(u8, plugin.source, "./") or
                std.mem.startsWith(u8, plugin.source, "/");

            if (!has_protocol) {
                if (use_color) try err_writer.writeAll(color.Code.bright_yellow);
                try err_writer.print("⚠ Plugin '{s}': source '{s}' should start with protocol or path\n", .{ plugin.name, plugin.source });
                if (use_color) try err_writer.writeAll(color.Code.reset);
                try color.printDim(err_writer, use_color, "  Hint: Use 'git:https://...', 'http://...', or './path'\n\n", .{});
                warning_count += 1;
            }
        }
    }

    // Print summary
    try w.writeAll("\n");

    if (error_count == 0 and warning_count == 0) {
        try color.printSuccess(w, use_color, "✓ Configuration valid\n\n", .{});

        const task_count_summary = config.tasks.count();
        const workflow_count = config.workflows.count();

        try color.printDim(w, use_color, "  Tasks:     {d}\n", .{task_count_summary});
        try color.printDim(w, use_color, "  Workflows: {d}\n", .{workflow_count});

        if (config.workspace) |workspace| {
            try color.printDim(w, use_color, "  Workspace: {d} members\n", .{workspace.members.len});
        }

        try w.writeAll("\n");
        return 0;
    } else if (error_count == 0) {
        // Only warnings - in strict mode, treat warnings as errors
        if (options.strict) {
            try color.printError(w, use_color, "✗ Configuration validation failed (--strict mode)\n\n", .{});
            if (use_color) try w.writeAll(color.Code.bright_yellow);
            try w.print("  Warnings: {d} (treated as errors)\n", .{warning_count});
            if (use_color) try w.writeAll(color.Code.reset);
            try w.writeAll("\n");
            try color.printDim(w, use_color, "  Hint: Fix warnings or remove --strict flag\n", .{});
            return 1;
        } else {
            if (use_color) try w.writeAll(color.Code.bright_yellow);
            try w.print("✓ Configuration valid with {d} warning(s)\n\n", .{warning_count});
            if (use_color) try w.writeAll(color.Code.reset);
            return 0;
        }
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

/// Calculate the maximum dependency chain depth for a task.
fn calculateDepChainDepth(
    allocator: std.mem.Allocator,
    config: *const loader.Config,
    task_name: []const u8,
) !usize {
    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();

    return calculateDepChainDepthRecursive(config, task_name, &visited);
}

fn calculateDepChainDepthRecursive(
    config: *const loader.Config,
    task_name: []const u8,
    visited: *std.StringHashMap(void),
) usize {
    // Check if already visited (cycle detection)
    if (visited.contains(task_name)) return 0;
    visited.put(task_name, {}) catch return 0;

    const task = config.tasks.get(task_name) orelse return 0;

    var max_depth: usize = 0;

    // Check regular dependencies
    for (task.deps) |dep_name| {
        const depth = calculateDepChainDepthRecursive(config, dep_name, visited);
        if (depth > max_depth) max_depth = depth;
    }

    // Check conditional dependencies
    for (task.deps_if) |dep_if| {
        const depth = calculateDepChainDepthRecursive(config, dep_if.task, visited);
        if (depth > max_depth) max_depth = depth;
    }

    // Check optional dependencies
    for (task.deps_optional) |dep_name| {
        const depth = calculateDepChainDepthRecursive(config, dep_name, visited);
        if (depth > max_depth) max_depth = depth;
    }

    return max_depth + 1;
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

test "cmdValidate: strict mode treats warnings as errors" {
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

    // Should fail with warnings in strict mode (warnings treated as errors)
    try std.testing.expectEqual(@as(u8, 1), result);

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

test "cmdValidate: deps_if with valid task passes" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.lint]
        \\cmd = "echo lint"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps_if = [{ task = "lint", condition = "platform.is_linux" }]
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

test "cmdValidate: deps_if with missing task passes (no validation)" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps_if = [{ task = "missing_task", condition = "platform.is_linux" }]
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

    // deps_if are not validated for existence (by design), so this should pass
    try std.testing.expectEqual(@as(u8, 0), result);
}

test "cmdValidate: deps_if with multiple conditions passes" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.lint]
        \\cmd = "echo lint"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps_if = [{ task = "lint", condition = "platform.is_linux" }, { task = "test", condition = "env.CI == '1'" }]
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

test "cmdValidate: deps_optional with existing task passes" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.format]
        \\cmd = "echo format"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps_optional = ["format"]
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

test "cmdValidate: deps_optional with missing task passes (ignored)" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps_optional = ["missing_task"]
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

test "cmdValidate: deps_optional with multiple tasks passes" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.format]
        \\cmd = "echo format"
        \\
        \\[tasks.lint]
        \\cmd = "echo lint"
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps_optional = ["format", "lint", "missing_task"]
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

    // Should pass - format and lint exist, missing_task is ignored
    try std.testing.expectEqual(@as(u8, 0), result);
}

