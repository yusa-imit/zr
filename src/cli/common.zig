const std = @import("std");
const loader = @import("../config/loader.zig");
const types = @import("../config/types.zig");
const dag_mod = @import("../graph/dag.zig");
const color = @import("../output/color.zig");

pub const CONFIG_FILE = "zr.toml";

/// Find zr.toml by searching current directory and parent directories.
/// Returns absolute path to zr.toml or null if not found.
/// Caller owns returned memory.
pub fn findConfigPath(allocator: std.mem.Allocator) !?[]const u8 {
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.fs.cwd().realpath(".", &cwd_buf);

    var current_dir = try allocator.dupe(u8, cwd);
    defer allocator.free(current_dir);

    while (true) {
        // Try to find zr.toml in current directory
        const candidate = try std.fs.path.join(allocator, &[_][]const u8{ current_dir, CONFIG_FILE });
        errdefer allocator.free(candidate);

        // Check if file exists
        std.fs.accessAbsolute(candidate, .{}) catch |err| {
            if (err == error.FileNotFound) {
                allocator.free(candidate);

                // Move to parent directory
                const parent = std.fs.path.dirname(current_dir) orelse {
                    // Reached root without finding config
                    return null;
                };

                // Stop if we've reached the root (no more parents)
                if (std.mem.eql(u8, parent, current_dir)) {
                    return null;
                }

                const new_current = try allocator.dupe(u8, parent);
                allocator.free(current_dir);
                current_dir = new_current;
                continue;
            } else {
                return err;
            }
        };

        // Found it!
        return candidate;
    }
}

/// Load config from file, applying profile overrides if requested.
/// Returns null and prints an error message if loading fails.
pub fn loadConfig(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    profile_name_opt: ?[]const u8,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !?loader.Config {
    var config = loader.loadFromFile(allocator, config_path) catch |err| {
        switch (err) {
            error.FileNotFound => {
                try color.printError(err_writer, use_color,
                    "Config: {s} not found\n\n  Hint: Create a zr.toml file in the current directory\n",
                    .{config_path},
                );
            },
            else => {
                try color.printError(err_writer, use_color,
                    "Config: Failed to load {s}: {s}\n",
                    .{ config_path, @errorName(err) },
                );
            },
        }
        return null;
    };

    // Resolve effective profile: --profile flag, then ZR_PROFILE env var.
    var effective_profile: ?[]const u8 = profile_name_opt;
    var env_profile_buf: [256]u8 = undefined;
    if (effective_profile == null) {
        if (std.process.getEnvVarOwned(allocator, "ZR_PROFILE")) |pname| {
            defer allocator.free(pname);
            if (pname.len > 0 and pname.len <= env_profile_buf.len) {
                @memcpy(env_profile_buf[0..pname.len], pname);
                effective_profile = env_profile_buf[0..pname.len];
            }
        } else |_| {}
    }

    if (effective_profile) |pname| {
        config.applyProfile(pname) catch |err| switch (err) {
            error.ProfileNotFound => {
                try color.printError(err_writer, use_color,
                    "profile: '{s}' not found in {s}\n\n  Hint: Add [profiles.{s}] to your zr.toml\n",
                    .{ pname, config_path, pname },
                );
                config.deinit();
                return null;
            },
            else => {
                try color.printError(err_writer, use_color,
                    "profile: Failed to apply '{s}': {s}\n", .{ pname, @errorName(err) });
                config.deinit();
                return null;
            },
        };
    }

    return config;
}

/// Construct a DAG from all tasks in the config.
pub fn buildDag(allocator: std.mem.Allocator, config: *const loader.Config) !dag_mod.DAG {
    var dag = dag_mod.DAG.init(allocator);
    errdefer dag.deinit();

    var it = config.tasks.iterator();
    while (it.next()) |entry| {
        const task = entry.value_ptr;
        try dag.addNode(task.name);

        // Add regular dependencies
        for (task.deps) |dep| {
            try dag.addEdge(task.name, dep);
        }

        // Add conditional dependencies (only if condition evaluates to true)
        const expr = @import("../config/expr.zig");
        for (task.deps_if) |dep_if| {
            const condition_met = expr.evalCondition(allocator, dep_if.condition, task.env) catch false;
            if (condition_met) {
                try dag.addEdge(task.name, dep_if.task);
            }
        }

        // Add optional dependencies (only if task exists)
        for (task.deps_optional) |dep| {
            if (config.tasks.contains(dep)) {
                try dag.addEdge(task.name, dep);
            }
        }
    }

    return dag;
}

/// Write a JSON-encoded string (with surrounding quotes and escape sequences).
pub fn writeJsonString(w: anytype, s: []const u8) !void {
    try w.writeAll("\"");
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            0x00...0x08, 0x0b, 0x0c, 0x0e...0x1f => try w.print("\\u{x:0>4}", .{c}),
            else => try w.writeByte(c),
        }
    }
    try w.writeAll("\"");
}

test "writeJsonString escapes special characters" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    // Test basic string
    try writeJsonString(writer, "hello world");
    try std.testing.expectEqualStrings("\"hello world\"", stream.getWritten());

    // Test quotes
    stream.reset();
    try writeJsonString(writer, "with \"quotes\"");
    try std.testing.expectEqualStrings("\"with \\\"quotes\\\"\"", stream.getWritten());

    // Test newline
    stream.reset();
    try writeJsonString(writer, "with\nnewline");
    try std.testing.expectEqualStrings("\"with\\nnewline\"", stream.getWritten());

    // Test backslash
    stream.reset();
    try writeJsonString(writer, "with\\backslash");
    try std.testing.expectEqualStrings("\"with\\\\backslash\"", stream.getWritten());
}

test "buildDag with conditional dependencies - condition true" {
    const allocator = std.testing.allocator;
    var config = types.Config.init(allocator);
    defer config.deinit();

    // Add tasks
    try config.addTask("lint", "echo lint", null, null, &[_][]const u8{});
    try config.addTask("test", "echo test", null, null, &[_][]const u8{});

    // Add task with conditional dep where condition is true
    try config.addTaskWithDepsIf("build", "echo build", &[_]types.ConditionalDep{
        .{ .task = "lint", .condition = "true" },
    });

    var dag = try buildDag(allocator, &config);
    defer dag.deinit();

    // build should depend on lint because condition is true
    const lint_node = dag.getNode("lint").?;
    try std.testing.expectEqual(@as(usize, 0), lint_node.dependencies.items.len);

    const build_node = dag.getNode("build").?;
    try std.testing.expectEqual(@as(usize, 1), build_node.dependencies.items.len);
    try std.testing.expectEqualStrings("lint", build_node.dependencies.items[0]);
}

test "buildDag with conditional dependencies - condition false" {
    const allocator = std.testing.allocator;
    var config = types.Config.init(allocator);
    defer config.deinit();

    // Add tasks
    try config.addTask("lint", "echo lint", null, null, &[_][]const u8{});
    try config.addTask("test", "echo test", null, null, &[_][]const u8{});

    // Add task with conditional dep where condition is false
    try config.addTaskWithDepsIf("build", "echo build", &[_]types.ConditionalDep{
        .{ .task = "lint", .condition = "false" },
    });

    var dag = try buildDag(allocator, &config);
    defer dag.deinit();

    // build should NOT depend on lint because condition is false
    const build_node = dag.getNode("build").?;
    try std.testing.expectEqual(@as(usize, 0), build_node.dependencies.items.len);
}

test "buildDag with optional dependencies - task exists" {
    const allocator = std.testing.allocator;
    var config = types.Config.init(allocator);
    defer config.deinit();

    // Add tasks
    try config.addTask("format", "echo format", null, null, &[_][]const u8{});
    try config.addTask("lint", "echo lint", null, null, &[_][]const u8{});

    // Add task with optional deps where tasks exist
    try config.addTaskWithDepsOptional("build", "echo build", &[_][]const u8{ "format", "lint" });

    var dag = try buildDag(allocator, &config);
    defer dag.deinit();

    // build should depend on format and lint because they exist
    const build_node = dag.getNode("build").?;
    try std.testing.expectEqual(@as(usize, 2), build_node.dependencies.items.len);
}

test "buildDag with optional dependencies - task missing" {
    const allocator = std.testing.allocator;
    var config = types.Config.init(allocator);
    defer config.deinit();

    // Add only some tasks
    try config.addTask("format", "echo format", null, null, &[_][]const u8{});
    // Note: "lint" does not exist

    // Add task with optional dep where one task doesn't exist
    try config.addTaskWithDepsOptional("build", "echo build", &[_][]const u8{ "format", "missing_task" });

    var dag = try buildDag(allocator, &config);
    defer dag.deinit();

    // build should only depend on format (missing_task is ignored)
    const build_node = dag.getNode("build").?;
    try std.testing.expectEqual(@as(usize, 1), build_node.dependencies.items.len);
    try std.testing.expectEqualStrings("format", build_node.dependencies.items[0]);
}

test "buildDag with mixed dependency types" {
    const allocator = std.testing.allocator;
    var config = types.Config.init(allocator);
    defer config.deinit();

    // Add all tasks
    try config.addTask("install", "echo install", null, null, &[_][]const u8{});
    try config.addTask("generate", "echo generate", null, null, &[_][]const u8{});

    // Add task with parallel deps only (deps_serial are handled by scheduler, not DAG)
    try config.addTask("build", "echo build", null, null, &[_][]const u8{"install", "generate"});

    var dag = try buildDag(allocator, &config);
    defer dag.deinit();

    // Verify the regular deps
    const build_node = dag.getNode("build").?;
    try std.testing.expectEqual(@as(usize, 2), build_node.dependencies.items.len); // install + generate
}
