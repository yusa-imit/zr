const std = @import("std");
const config_mod = @import("../config/loader.zig");
const toolchain = @import("../toolchain/installer.zig");
const run = @import("run.zig");

pub fn cmdSetup(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    _ = args; // --help could be added later

    // Step 1: Load config
    std.debug.print("\n🔧 Starting project setup...\n\n", .{});

    const cwd_path = std.fs.cwd().realpathAlloc(allocator, ".") catch |err| {
        std.debug.print(" ✗ Failed to get current directory: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer allocator.free(cwd_path);

    std.debug.print(" → Loading configuration...\n", .{});

    const cfg = config_mod.loadFromFile(allocator, "zr.toml") catch |err| {
        std.debug.print(" ✗ Failed to load zr.toml: {s}\n", .{@errorName(err)});
        std.debug.print("\n   Hint: Run `zr init` to create a starter config.\n", .{});
        return 1;
    };
    defer {
        var mut_cfg = cfg;
        mut_cfg.deinit();
    }

    std.debug.print(" ✓ Configuration loaded\n\n", .{});

    // Step 2: Install toolchains if defined
    if (cfg.toolchains.tools.len > 0) {
        std.debug.print(" → Installing toolchains...\n", .{});

        for (cfg.toolchains.tools) |tool_spec| {
            const is_installed = try toolchain.isInstalled(allocator, tool_spec.kind, tool_spec.version);

            if (is_installed) {
                std.debug.print("   ✓ {s}@{} already installed\n", .{
                    @tagName(tool_spec.kind),
                    tool_spec.version,
                });
            } else {
                std.debug.print("   ⏳ Installing {s}@{}...\n", .{
                    @tagName(tool_spec.kind),
                    tool_spec.version,
                });

                toolchain.install(allocator, tool_spec.kind, tool_spec.version) catch |err| {
                    std.debug.print("   ✗ Failed to install {s}@{}: {s}\n", .{
                        @tagName(tool_spec.kind),
                        tool_spec.version,
                        @errorName(err),
                    });
                    std.debug.print("\n   Hint: Check internet connection or try installing manually.\n", .{});
                    return 1;
                };

                std.debug.print("   ✓ {s}@{} installed successfully\n", .{
                    @tagName(tool_spec.kind),
                    tool_spec.version,
                });
            }
        }

        std.debug.print(" ✓ All toolchains ready\n\n", .{});
    }

    // Step 3: Look for common setup tasks
    const setup_tasks = [_][]const u8{ "setup", "install", "bootstrap", "prepare", "deps" };
    var found_setup_task: ?[]const u8 = null;

    for (setup_tasks) |task_name| {
        if (cfg.tasks.get(task_name)) |_| {
            found_setup_task = task_name;
            break;
        }
    }

    if (found_setup_task) |task_name| {
        std.debug.print(" → Running setup task: {s}\n", .{task_name});
        std.debug.print("\n   Hint: Executing `zr run {s}`\n\n", .{task_name});

        // Execute the task directly via cmdRun
        const exit_code = try run.cmdRun(
            allocator,
            task_name,
            null, // profile_name
            false, // dry_run
            1, // max_jobs
            "zr.toml", // config_path
            false, // json_output
            false, // monitor
            w,
            ew,
            use_color,
            null, // task_control
            .{}, // filter_options
            false, // silent_override
        );

        if (exit_code != 0) {
            std.debug.print("\n ✗ Setup task failed with exit code {d}\n", .{exit_code});
            return exit_code;
        }

        std.debug.print("\n ✓ Setup task completed\n\n", .{});
    } else {
        std.debug.print(" ℹ  No setup task found (looked for: setup, install, bootstrap, prepare, deps)\n\n", .{});
    }

    // Step 4: Complete
    std.debug.print("✨ Setup complete!\n\n", .{});
    std.debug.print("Next steps:\n", .{});
    std.debug.print("  • zr list       - See available tasks\n", .{});
    std.debug.print("  • zr run <task> - Run a specific task\n", .{});
    std.debug.print("  • zr --help     - View all commands\n\n", .{});

    return 0;
}

// Tests
test "setup command basic validation" {
    const allocator = std.testing.allocator;

    // Create null file writers to discard output
    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var buf: [4096]u8 = undefined;
    var writer = null_file.writer(&buf);
    var err_buf: [1024]u8 = undefined;
    var err_writer = null_file.writer(&err_buf);

    // Call setup with no args - should work without crashing
    const result = cmdSetup(allocator, &[_][]const u8{}, &writer.interface, &err_writer.interface, false) catch |err| {
        // Expected to fail if no zr.toml exists in current directory
        try std.testing.expect(err == error.FileNotFound or err == error.AccessDenied);
        return;
    };

    // If it succeeded, verify it returned a valid exit code
    try std.testing.expect(result == 0 or result == 1);
}
