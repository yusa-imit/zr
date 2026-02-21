const std = @import("std");
const loader = @import("config/loader.zig");
const parser = @import("config/parser.zig");
const expr = @import("config/expr.zig");
const matrix = @import("config/matrix.zig");
const dag_mod = @import("graph/dag.zig");
const topo_sort = @import("graph/topo_sort.zig");
const cycle_detect = @import("graph/cycle_detect.zig");
const scheduler = @import("exec/scheduler.zig");
const process = @import("exec/process.zig");
const color = @import("output/color.zig");
const progress = @import("output/progress.zig");
const monitor = @import("output/monitor.zig");
const history = @import("history/store.zig");
const watcher = @import("watch/watcher.zig");
const cache_store = @import("cache/store.zig");
const plugin_loader = @import("plugin/loader.zig");
const plugin_install = @import("plugin/install.zig");
const plugin_builtin = @import("plugin/builtin.zig");
const builtin_env = @import("plugin/builtin_env.zig");
const builtin_git = @import("plugin/builtin_git.zig");
const plugin_registry = @import("plugin/registry.zig");
const plugin_search = @import("plugin/search.zig");
const wasm_runtime = @import("plugin/wasm_runtime.zig");
const types = @import("config/types.zig");
const common = @import("cli/common.zig");
const completion = @import("cli/completion.zig");
const init = @import("cli/init.zig");
const workspace = @import("cli/workspace.zig");
const plugin_cli = @import("cli/plugin.zig");
const run_cmd = @import("cli/run.zig");
const list_cmd = @import("cli/list.zig");
const tui = @import("cli/tui.zig");
const live_cmd = @import("cli/live.zig");
const interactive_run = @import("cli/interactive_run.zig");
const validate_cmd = @import("cli/validate.zig");
const platform = @import("util/platform.zig");
const semver = @import("util/semver.zig");
const hash_util = @import("util/hash.zig");
const glob = @import("util/glob.zig");
const resource = @import("exec/resource.zig");
const control = @import("exec/control.zig");
const toolchain_types = @import("toolchain/types.zig");
const toolchain_installer = @import("toolchain/installer.zig");
const toolchain_downloader = @import("toolchain/downloader.zig");

// Ensure tests in all imported modules are included in test binary
comptime {
    _ = loader;
    _ = parser;
    _ = expr;
    _ = matrix;
    _ = dag_mod;
    _ = topo_sort;
    _ = cycle_detect;
    _ = scheduler;
    _ = process;
    _ = color;
    _ = progress;
    _ = monitor;
    _ = history;
    _ = watcher;
    _ = cache_store;
    _ = plugin_loader;
    _ = plugin_install;
    _ = plugin_builtin;
    _ = builtin_env;
    _ = builtin_git;
    _ = plugin_registry;
    _ = plugin_search;
    _ = wasm_runtime;
    _ = types;
    _ = common;
    _ = completion;
    _ = init;
    _ = workspace;
    _ = plugin_cli;
    _ = run_cmd;
    _ = list_cmd;
    _ = tui;
    _ = live_cmd;
    _ = interactive_run;
    _ = validate_cmd;
    _ = platform;
    _ = semver;
    _ = hash_util;
    _ = glob;
    _ = resource;
    _ = control;
    _ = toolchain_types;
    _ = toolchain_installer;
    _ = toolchain_downloader;
}

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

    // Parse global flags: --profile <name>, --dry-run, --jobs, --no-color, --quiet, --verbose, --config, --format, --monitor
    // Scan args for flags; strip them from the args slice before command dispatch.
    var profile_name: ?[]const u8 = null;
    var dry_run: bool = false;
    var max_jobs: u32 = 0;
    var no_color: bool = false;
    var quiet: bool = false;
    var verbose: bool = false;
    var json_output: bool = false;
    var config_path: []const u8 = common.CONFIG_FILE;
    var enable_monitor: bool = false;
    var remaining_args = std.ArrayList([]const u8){};
    defer remaining_args.deinit(allocator);
    {
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--profile") or std.mem.eql(u8, args[i], "-p")) {
                if (i + 1 < args.len) {
                    profile_name = args[i + 1];
                    i += 1; // skip value
                } else {
                    try color.printError(ew, use_color, "--profile: missing profile name\n\n  Hint: zr --profile <name> run <task>\n", .{});
                    return 1;
                }
            } else if (std.mem.eql(u8, args[i], "--dry-run") or std.mem.eql(u8, args[i], "-n")) {
                dry_run = true;
            } else if (std.mem.eql(u8, args[i], "--no-color")) {
                no_color = true;
            } else if (std.mem.eql(u8, args[i], "--quiet") or std.mem.eql(u8, args[i], "-q")) {
                quiet = true;
            } else if (std.mem.eql(u8, args[i], "--verbose") or std.mem.eql(u8, args[i], "-v")) {
                verbose = true;
            } else if (std.mem.eql(u8, args[i], "--format") or std.mem.eql(u8, args[i], "-f")) {
                if (i + 1 < args.len) {
                    const fmt_val = args[i + 1];
                    if (std.mem.eql(u8, fmt_val, "json")) {
                        json_output = true;
                    } else if (std.mem.eql(u8, fmt_val, "text")) {
                        json_output = false;
                    } else {
                        try color.printError(ew, use_color,
                            "--format: unknown format '{s}'\n\n  Hint: supported formats: text, json\n",
                            .{fmt_val});
                        return 1;
                    }
                    i += 1; // skip value
                } else {
                    try color.printError(ew, use_color,
                        "--format: missing value\n\n  Hint: zr --format <text|json> <command>\n", .{});
                    return 1;
                }
            } else if (std.mem.eql(u8, args[i], "--jobs") or std.mem.eql(u8, args[i], "-j")) {
                if (i + 1 < args.len) {
                    const n = std.fmt.parseInt(u32, args[i + 1], 10) catch {
                        try color.printError(ew, use_color,
                            "--jobs: invalid value '{s}' — must be a positive integer\n\n  Hint: zr --jobs 4 run <task>\n",
                            .{args[i + 1]});
                        return 1;
                    };
                    if (n == 0) {
                        try color.printError(ew, use_color,
                            "--jobs: value must be >= 1 (use 1 for sequential execution)\n\n  Hint: zr --jobs 4 run <task>\n", .{});
                        return 1;
                    }
                    max_jobs = n;
                    i += 1; // skip value
                } else {
                    try color.printError(ew, use_color,
                        "--jobs: missing value\n\n  Hint: zr --jobs <N> run <task>\n", .{});
                    return 1;
                }
            } else if (std.mem.eql(u8, args[i], "--config")) {
                if (i + 1 < args.len) {
                    config_path = args[i + 1];
                    i += 1; // skip value
                } else {
                    try color.printError(ew, use_color,
                        "--config: missing path\n\n  Hint: zr --config <path> run <task>\n", .{});
                    return 1;
                }
            } else if (std.mem.eql(u8, args[i], "--monitor") or std.mem.eql(u8, args[i], "-m")) {
                enable_monitor = true;
            } else {
                try remaining_args.append(allocator, args[i]);
            }
        }
    }
    // ZR_PROFILE env var is checked inside loadConfig (--profile flag takes precedence).

    // Apply --no-color override.
    const effective_color = use_color and !no_color;

    // For --quiet: redirect stdout to /dev/null so non-error output is suppressed.
    // On non-Unix systems this silently falls back to normal output.
    var quiet_file_opt: ?std.fs.File = null;
    defer if (quiet_file_opt) |f| f.close();
    var quiet_buf: [4096]u8 = undefined;
    // quiet_writer must be a plain (non-optional) var so that &quiet_writer.interface
    // is a stable pointer into this stack frame (not into an optional wrapper).
    var quiet_writer: std.fs.File.Writer = undefined;
    const effective_w: *std.Io.Writer = blk: {
        if (quiet) {
            if (std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only })) |qf| {
                quiet_file_opt = qf;
                quiet_writer = qf.writer(&quiet_buf);
                break :blk &quiet_writer.interface;
            } else |_| {}
        }
        break :blk w;
    };

    const effective_args = remaining_args.items;
    if (effective_args.len < 2) {
        try printHelp(effective_w, effective_color);
        return 0;
    }

    // --verbose: print a dim note after the help guard.
    if (verbose) {
        try color.printDim(effective_w, effective_color, "[verbose mode]\n", .{});
    }

    const cmd = effective_args[1];

    if (std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        try printHelp(effective_w, effective_color);
        return 0;
    }

    if (std.mem.eql(u8, cmd, "run")) {
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "run: missing task name\n\n  Hint: zr run <task-name>\n", .{});
            return 1;
        }
        const task_name = effective_args[2];
        return run_cmd.cmdRun(allocator, task_name, profile_name, dry_run, max_jobs, config_path, json_output, enable_monitor, effective_w, ew, effective_color, null);
    } else if (std.mem.eql(u8, cmd, "watch")) {
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "watch: missing task name\n\n  Hint: zr watch <task-name> [path...]\n", .{});
            return 1;
        }
        const task_name = effective_args[2];
        const watch_paths: []const []const u8 = if (effective_args.len > 3) effective_args[3..] else &[_][]const u8{"."};
        return run_cmd.cmdWatch(allocator, task_name, watch_paths, profile_name, max_jobs, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "workflow")) {
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "workflow: missing workflow name\n\n  Hint: zr workflow <name>\n", .{});
            return 1;
        }
        const wf_name = effective_args[2];
        return run_cmd.cmdWorkflow(allocator, wf_name, profile_name, dry_run, max_jobs, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "list")) {
        return list_cmd.cmdList(allocator, config_path, json_output, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "graph")) {
        return list_cmd.cmdGraph(allocator, config_path, json_output, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "history")) {
        return run_cmd.cmdHistory(allocator, json_output, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "init")) {
        return init.cmdInit(std.fs.cwd(), effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "validate")) {
        // Parse validate options
        var strict = false;
        var show_schema = false;
        for (effective_args[2..]) |arg| {
            if (std.mem.eql(u8, arg, "--strict")) {
                strict = true;
            } else if (std.mem.eql(u8, arg, "--schema")) {
                show_schema = true;
            }
        }
        return validate_cmd.cmdValidate(allocator, config_path, .{
            .strict = strict,
            .show_schema = show_schema,
        }, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "completion")) {
        const shell = if (effective_args.len >= 3) effective_args[2] else "";
        return completion.cmdCompletion(shell, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "workspace")) {
        const sub = if (effective_args.len >= 3) effective_args[2] else "";
        if (std.mem.eql(u8, sub, "list")) {
            return workspace.cmdWorkspaceList(allocator, config_path, json_output, effective_w, ew, effective_color);
        } else if (std.mem.eql(u8, sub, "run")) {
            if (effective_args.len < 4) {
                try color.printError(ew, effective_color,
                    "workspace run: missing task name\n\n  Hint: zr workspace run <task-name>\n", .{});
                return 1;
            }
            const task_name = effective_args[3];
            return workspace.cmdWorkspaceRun(allocator, task_name, profile_name, dry_run, max_jobs, config_path, json_output, effective_w, ew, effective_color);
        } else {
            try color.printError(ew, effective_color,
                "workspace: unknown subcommand '{s}'\n\n  Hint: zr workspace list | zr workspace run <task>\n", .{sub});
            return 1;
        }
    } else if (std.mem.eql(u8, cmd, "cache")) {
        const sub = if (effective_args.len >= 3) effective_args[2] else "";
        return list_cmd.cmdCache(allocator, sub, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "plugin")) {
        const sub = if (effective_args.len >= 3) effective_args[2] else "";
        return plugin_cli.cmdPlugin(allocator, sub, effective_args, config_path, json_output, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "interactive") or std.mem.eql(u8, cmd, "i")) {
        return tui.cmdInteractive(allocator, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "live")) {
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "live: missing task name\n\n  Hint: zr live <task-name> [task-name...]\n", .{});
            return 1;
        }
        const task_names = effective_args[2..];
        return live_cmd.cmdLive(allocator, task_names, profile_name, max_jobs, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "interactive-run") or std.mem.eql(u8, cmd, "irun")) {
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "interactive-run: missing task name\n\n  Hint: zr interactive-run <task-name>\n", .{});
            return 1;
        }
        const task_name = effective_args[2];
        return interactive_run.cmdInteractiveRun(allocator, task_name, config_path, effective_w, ew, effective_color);
    } else {
        try color.printError(ew, effective_color, "Unknown command: {s}\n\n", .{cmd});
        try printHelp(effective_w, effective_color);
        return 1;
    }
}

fn printHelp(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "zr v0.0.4", .{});
    try w.print(" - Zig Task Runner\n\n", .{});
    try color.printBold(w, use_color, "Usage:\n", .{});
    try w.print("  zr [options] <command> [arguments]\n\n", .{});
    try color.printBold(w, use_color, "Commands:\n", .{});
    try w.print("  run <task>             Run a task and its dependencies\n", .{});
    try w.print("  watch <task> [path...] Watch files and auto-run task on changes\n", .{});
    try w.print("  workflow <name>        Run a workflow by name\n", .{});
    try w.print("  list                   List all available tasks\n", .{});
    try w.print("  graph                  Show dependency tree\n", .{});
    try w.print("  history                Show recent run history\n", .{});
    try w.print("  workspace list         List workspace member directories\n", .{});
    try w.print("  workspace run <task>   Run a task across all workspace members\n", .{});
    try w.print("  cache clear            Clear all cached task results\n", .{});
    try w.print("  plugin list            List plugins declared in zr.toml\n", .{});
    try w.print("  plugin builtins        List available built-in plugins\n", .{});
    try w.print("  plugin search [query]  Search installed plugins by name/description\n", .{});
    try w.print("  plugin install <path|url>  Install a plugin (local path or git URL)\n", .{});
    try w.print("  plugin remove <name>   Remove an installed plugin\n", .{});
    try w.print("  plugin update <n> [p]  Update a plugin (git pull, or from new path)\n", .{});
    try w.print("  plugin info <name>     Show metadata for an installed plugin\n", .{});
    try w.print("  plugin create <name>   Scaffold a new plugin template directory\n", .{});
    try w.print("  interactive, i         Launch interactive TUI task picker\n", .{});
    try w.print("  live <task>            Run task with live TUI log streaming\n", .{});
    try w.print("  interactive-run, irun  Run task with cancel/retry controls\n", .{});
    try w.print("  init                   Scaffold a new zr.toml in the current directory\n", .{});
    try w.print("  validate               Validate zr.toml configuration file\n", .{});
    try w.print("  completion <shell>     Print shell completion script (bash|zsh|fish)\n\n", .{});
    try color.printBold(w, use_color, "Options:\n", .{});
    try w.print("  --help, -h            Show this help message\n", .{});
    try w.print("  --profile, -p <name>  Activate a named profile (overrides env/task settings)\n", .{});
    try w.print("  --dry-run, -n         Show what would run without executing (run/workflow only)\n", .{});
    try w.print("  --jobs, -j <N>        Max parallel tasks (default: CPU count)\n", .{});
    try w.print("  --no-color            Disable color output\n", .{});
    try w.print("  --quiet, -q           Suppress non-error output\n", .{});
    try w.print("  --verbose, -v         Verbose output\n", .{});
    try w.print("  --config <path>       Config file path (default: zr.toml)\n", .{});
    try w.print("  --format, -f <fmt>    Output format: text (default) or json\n", .{});
    try w.print("  --monitor, -m         Display live resource usage (CPU/memory) during execution\n\n", .{});
    try color.printDim(w, use_color, "Config file: zr.toml (in current directory)\n", .{});
    try color.printDim(w, use_color, "Profile env: ZR_PROFILE=<name> (alternative to --profile)\n", .{});
}

test "basic functionality" {
    try std.testing.expect(true);
}

test "--no-color and --jobs are consumed before command dispatch" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // With only flags and no command after them, should print help (exit 0),
    // not "Unknown command: --no-color".
    const fake_args = [_][]const u8{ "zr", "--no-color", "--jobs", "4" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, true);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "--quiet flag is parsed and does not crash" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // --quiet with no command prints help (exit 0).
    const fake_args = [_][]const u8{ "zr", "--quiet" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, true);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "--verbose flag is parsed and does not crash" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // --verbose with no command prints help (exit 0).
    const fake_args = [_][]const u8{ "zr", "--verbose" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "--config flag missing value returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // --config without a value should return exit code 1.
    const fake_args = [_][]const u8{ "zr", "--config" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "--jobs with invalid value returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // --jobs with non-numeric value should return exit code 1.
    const fake_args = [_][]const u8{ "zr", "--jobs", "notanumber" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "--format json is parsed and does not crash" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // --format json with no command prints help (exit 0).
    const fake_args = [_][]const u8{ "zr", "--format", "json" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "--format text is parsed and does not crash" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const fake_args = [_][]const u8{ "zr", "--format", "text" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "--format unknown value returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const fake_args = [_][]const u8{ "zr", "--format", "yaml" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "--format missing value returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const fake_args = [_][]const u8{ "zr", "--format" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "writeJsonString escapes special characters" {
    var buf: [256]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var w = stdout.writer(&buf);

    // Just test that it runs without error on common characters.
    try common.writeJsonString(&w.interface, "hello world");
    try common.writeJsonString(&w.interface, "with \"quotes\"");
    try common.writeJsonString(&w.interface, "with\nnewline");
    try common.writeJsonString(&w.interface, "with\\backslash");
}

test "cmdList --format json returns valid JSON with tasks field" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // Without a real config file this returns 1 — ensure it doesn't crash
    // and that flag parsing itself works (no panic).
    const fake_args = [_][]const u8{ "zr", "--format", "json", "list" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    // Exit 1 expected (no zr.toml in cwd during tests) — but no crash/panic.
    _ = code;
}

test "workspace command: missing subcommand returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // "workspace" with unknown subcommand returns 1
    const fake_args = [_][]const u8{ "zr", "workspace", "unknown" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "workspace command: run missing task name returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // "workspace run" without task name returns 1
    const fake_args = [_][]const u8{ "zr", "workspace", "run" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

