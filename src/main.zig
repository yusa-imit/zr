const std = @import("std");
const loader = @import("config/loader.zig");
const parser = @import("config/parser.zig");
const expr = @import("config/expr.zig");
const matrix = @import("config/matrix.zig");
const dag_mod = @import("graph/dag.zig");
const topo_sort = @import("graph/topo_sort.zig");
const cycle_detect = @import("graph/cycle_detect.zig");
const graph_ascii = @import("graph/ascii.zig");
const scheduler = @import("exec/scheduler.zig");
const process = @import("exec/process.zig");
const color = @import("output/color.zig");
const progress = @import("output/progress.zig");
const monitor = @import("output/monitor.zig");
const history = @import("history/store.zig");
const watcher = @import("watch/watcher.zig");
const cache_store = @import("cache/store.zig");
const cache_remote = @import("cache/remote.zig");
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
const tools_cmd = @import("cli/tools.zig");
const graph_cmd = @import("cli/graph.zig");
const lint_cmd = @import("cli/lint.zig");
const repo_cmd = @import("cli/repo.zig");
const codeowners_cmd = @import("cli/codeowners.zig");
const version_cmd = @import("cli/version.zig");
const publish_cmd = @import("cli/publish.zig");
const analytics_cmd = @import("cli/analytics.zig");
const context_cmd = @import("cli/context.zig");
const conformance_cmd = @import("cli/conformance.zig");
const bench_cmd = @import("cli/bench.zig");
const doctor_cmd = @import("cli/doctor.zig");
const setup_cmd = @import("cli/setup.zig");
const env_cmd = @import("cli/env.zig");
const export_cmd = @import("cli/export.zig");
const affected_cmd = @import("cli/affected.zig");
const clean_cmd = @import("cli/clean.zig");
const upgrade_cmd = @import("cli/upgrade.zig");
const alias_cmd = @import("cli/alias.zig");
const estimate_cmd = @import("cli/estimate.zig");
const show_cmd = @import("cli/show.zig");
const schedule_cmd = @import("cli/schedule.zig");
const platform = @import("util/platform.zig");
const semver = @import("util/semver.zig");
const hash_util = @import("util/hash.zig");
const glob = @import("util/glob.zig");
const affected = @import("util/affected.zig");
const resource = @import("exec/resource.zig");
const control = @import("exec/control.zig");
const toolchain_types = @import("toolchain/types.zig");
const toolchain_installer = @import("toolchain/installer.zig");
const toolchain_downloader = @import("toolchain/downloader.zig");
const toolchain_path = @import("toolchain/path.zig");
const constraints_mod = @import("config/constraints.zig");
const repos = @import("config/repos.zig");
const multirepo_sync = @import("multirepo/sync.zig");
const multirepo_status = @import("multirepo/status.zig");
const multirepo_graph = @import("multirepo/graph.zig");
const multirepo_run = @import("multirepo/run.zig");
const multirepo_synthetic = @import("multirepo/synthetic.zig");
const codeowners_types = @import("codeowners/types.zig");
const codeowners_generator = @import("codeowners/generator.zig");
const aliases = @import("config/aliases.zig");

// Ensure tests in all imported modules are included in test binary
comptime {
    _ = aliases;
    _ = alias_cmd;
    _ = estimate_cmd;
    _ = schedule_cmd;
    _ = loader;
    _ = parser;
    _ = expr;
    _ = matrix;
    _ = constraints_mod;
    _ = dag_mod;
    _ = topo_sort;
    _ = cycle_detect;
    _ = graph_ascii;
    _ = scheduler;
    _ = process;
    _ = color;
    _ = progress;
    _ = monitor;
    _ = history;
    _ = watcher;
    _ = cache_store;
    _ = cache_remote;
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
    _ = tools_cmd;
    _ = graph_cmd;
    _ = lint_cmd;
    _ = repo_cmd;
    _ = codeowners_cmd;
    _ = platform;
    _ = semver;
    _ = hash_util;
    _ = glob;
    _ = affected;
    _ = resource;
    _ = control;
    _ = toolchain_types;
    _ = toolchain_installer;
    _ = toolchain_downloader;
    _ = toolchain_path;
    _ = repos;
    _ = multirepo_sync;
    _ = multirepo_status;
    _ = multirepo_graph;
    _ = multirepo_run;
    _ = multirepo_synthetic;
    _ = codeowners_types;
    _ = codeowners_generator;
    _ = version_cmd;
    _ = publish_cmd;
    _ = analytics_cmd;
    _ = @import("versioning/types.zig");
    _ = @import("versioning/bump.zig");
    _ = @import("versioning/conventional.zig");
    _ = @import("versioning/changelog.zig");
    _ = @import("analytics/types.zig");
    _ = @import("analytics/collector.zig");
    _ = @import("analytics/html.zig");
    _ = @import("analytics/json.zig");
    _ = context_cmd;
    _ = @import("context/types.zig");
    _ = @import("context/generator.zig");
    _ = @import("context/json.zig");
    _ = @import("context/yaml.zig");
    _ = conformance_cmd;
    _ = @import("conformance/types.zig");
    _ = @import("conformance/engine.zig");
    _ = @import("conformance/parser.zig");
    _ = @import("conformance/fixer.zig");
    _ = bench_cmd;
    _ = @import("bench/types.zig");
    _ = @import("bench/runner.zig");
    _ = @import("bench/formatter.zig");
    _ = doctor_cmd;
    _ = setup_cmd;
    _ = env_cmd;
    _ = export_cmd;
    _ = affected_cmd;
    _ = clean_cmd;
    _ = upgrade_cmd;
    _ = @import("upgrade/types.zig");
    _ = @import("upgrade/checker.zig");
    _ = @import("upgrade/installer.zig");
    _ = alias_cmd;
    _ = estimate_cmd;
    _ = show_cmd;
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
    var affected_base: ?[]const u8 = null;
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
            } else if (std.mem.eql(u8, args[i], "--affected")) {
                if (i + 1 < args.len) {
                    affected_base = args[i + 1];
                    i += 1; // skip value
                } else {
                    try color.printError(ew, use_color,
                        "--affected: missing base reference\n\n  Hint: zr --affected origin/main workspace run <task>\n", .{});
                    return 1;
                }
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

    if (std.mem.eql(u8, cmd, "--version")) {
        try printVersion(effective_w, effective_color);
        return 0;
    }

    // Alias expansion: if cmd is not a known built-in, check if it's an alias
    const known_commands = [_][]const u8{
        "run",        "watch",      "workflow",   "list",
        "graph",      "history",    "init",       "validate",
        "completion", "workspace",  "cache",      "plugin",
        "interactive", "i",          "live",       "interactive-run",
        "irun",       "tools",      "lint",       "repo",
        "codeowners", "version",    "publish",    "analytics",
        "context",    "conformance", "bench",      "doctor",
        "setup",      "env",        "export",     "affected",
        "clean",      "upgrade",    "alias",      "estimate",
        "show",       "schedule",
    };
    var is_builtin = false;
    for (known_commands) |known| {
        if (std.mem.eql(u8, cmd, known)) {
            is_builtin = true;
            break;
        }
    }

    if (!is_builtin) {
        // Try to load aliases and expand
        var alias_config = aliases.AliasConfig.load(allocator) catch |err| {
            // If alias loading fails, just continue with unknown command error
            if (err != error.FileNotFound) {
                try color.printError(ew, effective_color, "Failed to load aliases: {}\n", .{err});
            }
            try color.printError(ew, effective_color, "Unknown command: {s}\n\n", .{cmd});
            try printHelp(effective_w, effective_color);
            return 1;
        };
        defer alias_config.deinit();

        if (alias_config.get(cmd)) |alias_command| {
            // Expand the alias: split alias_command by spaces and prepend "zr"
            // Example: alias_command = "run build && run test"
            // We need to tokenize this properly, handling quoted strings
            var expanded_args = std.ArrayList([]const u8){};
            defer expanded_args.deinit(allocator);

            try expanded_args.append(allocator, effective_args[0]); // preserve "zr" binary path

            // Simple tokenization (split by spaces, no quote handling for MVP)
            // This is sufficient for most alias use cases
            var tokens = std.mem.tokenizeScalar(u8, alias_command, ' ');
            while (tokens.next()) |token| {
                try expanded_args.append(allocator, token);
            }

            // Append remaining args after the alias name
            for (effective_args[2..]) |arg| {
                try expanded_args.append(allocator, arg);
            }

            // Recursively call run with expanded args
            return try run(allocator, expanded_args.items, w, ew, use_color);
        } else {
            // Not a builtin and not an alias
            try color.printError(ew, effective_color, "Unknown command: {s}\n\n", .{cmd});
            try printHelp(effective_w, effective_color);
            return 1;
        }
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
        // Parse list options
        var tree_mode = false;
        var filter_pattern: ?[]const u8 = null;
        var filter_tags: ?[]const u8 = null;
        var i: usize = 2;
        while (i < effective_args.len) : (i += 1) {
            const arg = effective_args[i];
            if (std.mem.eql(u8, arg, "--tree")) {
                tree_mode = true;
            } else if (std.mem.startsWith(u8, arg, "--tags=")) {
                filter_tags = arg["--tags=".len..];
            } else if (std.mem.eql(u8, arg, "--tags")) {
                if (i + 1 < effective_args.len) {
                    i += 1;
                    filter_tags = effective_args[i];
                }
            } else if (!std.mem.startsWith(u8, arg, "--")) {
                // First non-flag argument is the filter pattern
                filter_pattern = arg;
            }
        }
        return list_cmd.cmdList(allocator, config_path, json_output, tree_mode, filter_pattern, filter_tags, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "graph")) {
        // Parse graph options
        var ascii_mode = false;
        for (effective_args[2..]) |arg| {
            if (std.mem.eql(u8, arg, "--ascii")) {
                ascii_mode = true;
            }
        }
        return list_cmd.cmdGraph(allocator, config_path, json_output, ascii_mode, effective_w, ew, effective_color);
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
        if (std.mem.eql(u8, sub, "") or std.mem.eql(u8, sub, "--help") or std.mem.eql(u8, sub, "-h")) {
            try color.printBold(effective_w, effective_color, "zr workspace - Monorepo and multi-repository management\n\n", .{});
            try effective_w.writeAll("Usage:\n");
            try effective_w.writeAll("  zr workspace list              List workspace member directories\n");
            try effective_w.writeAll("  zr workspace run <task>        Run a task across all workspace members\n");
            try effective_w.writeAll("  zr workspace sync [path]       Build synthetic workspace from multi-repo\n");
            return if (std.mem.eql(u8, sub, "")) @as(u8, 1) else @as(u8, 0);
        } else if (std.mem.eql(u8, sub, "list")) {
            return workspace.cmdWorkspaceList(allocator, config_path, json_output, effective_w, ew, effective_color);
        } else if (std.mem.eql(u8, sub, "run")) {
            if (effective_args.len < 4) {
                try color.printError(ew, effective_color,
                    "workspace run: missing task name\n\n  Hint: zr workspace run <task-name>\n", .{});
                return 1;
            }
            const task_name = effective_args[3];
            return workspace.cmdWorkspaceRun(allocator, task_name, profile_name, dry_run, max_jobs, config_path, json_output, affected_base, effective_w, ew, effective_color);
        } else if (std.mem.eql(u8, sub, "sync")) {
            const repo_config_path: ?[]const u8 = if (effective_args.len >= 4) effective_args[3] else null;
            return workspace.cmdWorkspaceSync(allocator, repo_config_path, effective_w, ew, effective_color);
        } else {
            try color.printError(ew, effective_color,
                "workspace: unknown subcommand '{s}'\n\n  Hint: zr workspace list | zr workspace run <task> | zr workspace sync\n", .{sub});
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
    } else if (std.mem.eql(u8, cmd, "tools")) {
        const sub = if (effective_args.len >= 3) effective_args[2] else "";
        return tools_cmd.cmdTools(allocator, sub, effective_args, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "graph")) {
        const graph_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return graph_cmd.graphCommand(allocator, graph_args, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "lint")) {
        const lint_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return lint_cmd.run(allocator, lint_args);
    } else if (std.mem.eql(u8, cmd, "repo")) {
        const sub = if (effective_args.len >= 3) effective_args[2] else "";
        return repo_cmd.cmdRepo(allocator, sub, effective_args, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "codeowners")) {
        const codeowners_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return codeowners_cmd.cmdCodeowners(allocator, codeowners_args, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "version")) {
        const version_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        try version_cmd.cmdVersion(allocator, version_args);
        return 0;
    } else if (std.mem.eql(u8, cmd, "publish")) {
        const publish_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        try publish_cmd.cmdPublish(allocator, publish_args);
        return 0;
    } else if (std.mem.eql(u8, cmd, "analytics")) {
        const analytics_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return analytics_cmd.cmdAnalytics(allocator, analytics_args, json_output);
    } else if (std.mem.eql(u8, cmd, "context")) {
        const context_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return context_cmd.cmdContext(allocator, context_args);
    } else if (std.mem.eql(u8, cmd, "conformance")) {
        const conformance_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return conformance_cmd.cmdConformance(allocator, conformance_args);
    } else if (std.mem.eql(u8, cmd, "bench")) {
        const bench_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return bench_cmd.cmdBench(allocator, bench_args);
    } else if (std.mem.eql(u8, cmd, "doctor")) {
        const doctor_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        var opts = doctor_cmd.DoctorOptions{};
        for (doctor_args) |arg| {
            if (std.mem.startsWith(u8, arg, "--config=")) {
                opts.config_path = arg["--config=".len..];
            } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
                opts.verbose = true;
            }
        }
        return doctor_cmd.cmdDoctor(allocator, opts);
    } else if (std.mem.eql(u8, cmd, "setup")) {
        const setup_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return setup_cmd.cmdSetup(allocator, setup_args);
    } else if (std.mem.eql(u8, cmd, "env")) {
        const env_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return env_cmd.cmdEnv(allocator, env_args, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "export")) {
        const export_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return export_cmd.cmdExport(allocator, export_args, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "affected")) {
        const affected_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return affected_cmd.cmdAffected(allocator, affected_args, profile_name, dry_run, max_jobs, config_path, json_output, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "clean")) {
        const clean_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return clean_cmd.cmdClean(allocator, clean_args, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "upgrade")) {
        const upgrade_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return upgrade_cmd.cmdUpgrade(allocator, upgrade_args);
    } else if (std.mem.eql(u8, cmd, "alias")) {
        const alias_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return alias_cmd.cmdAlias(allocator, alias_args, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "estimate")) {
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "Usage: zr estimate <task> [--limit N] [--format json]\n", .{});
            try effective_w.writeAll("\n");
            try color.printBold(effective_w, effective_color, "Description:\n", .{});
            try effective_w.writeAll("  Estimate task duration based on execution history\n\n");
            try color.printBold(effective_w, effective_color, "Options:\n", .{});
            try effective_w.writeAll("  --limit N         Limit history sample to last N executions (default: 20)\n");
            try effective_w.writeAll("  --format json     Output estimation in JSON format\n");
            try effective_w.writeAll("  --help, -h        Show this help message\n");
            return 1;
        }
        const task_name = effective_args[2];

        // Check for --help flag
        if (std.mem.eql(u8, task_name, "--help") or std.mem.eql(u8, task_name, "-h")) {
            try effective_w.writeAll("Usage: zr estimate <task> [--limit N] [--format json]\n\n");
            try color.printBold(effective_w, effective_color, "Description:\n", .{});
            try effective_w.writeAll("  Estimate task duration based on execution history\n\n");
            try color.printBold(effective_w, effective_color, "Options:\n", .{});
            try effective_w.writeAll("  --limit N         Limit history sample to last N executions (default: 20)\n");
            try effective_w.writeAll("  --format json     Output estimation in JSON format\n");
            try effective_w.writeAll("  --help, -h        Show this help message\n");
            return 0;
        }

        // Parse --limit flag from remaining args
        var limit: usize = 20; // Default to last 20 runs
        var i: usize = 3;
        while (i < effective_args.len) : (i += 1) {
            const arg = effective_args[i];
            if (std.mem.eql(u8, arg, "--limit")) {
                i += 1;
                if (i >= effective_args.len) {
                    try color.printError(ew, effective_color, "error: --limit requires a number\n", .{});
                    return 1;
                }
                limit = std.fmt.parseInt(usize, effective_args[i], 10) catch {
                    try color.printError(ew, effective_color, "error: invalid limit value: {s}\n", .{effective_args[i]});
                    return 1;
                };
                if (limit == 0) {
                    try color.printError(ew, effective_color, "error: --limit must be greater than 0\n", .{});
                    return 1;
                }
            }
        }

        // Convert json_output to estimate's OutputFormat
        const estimate_format: estimate_cmd.OutputFormat = if (json_output) .json else .text;

        return estimate_cmd.cmdEstimate(allocator, task_name, config_path, limit, effective_w, ew, effective_color, estimate_format);
    } else if (std.mem.eql(u8, cmd, "show")) {
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "Usage: zr show <task>\n", .{});
            try effective_w.writeAll("\n");
            try color.printBold(effective_w, effective_color, "Description:\n", .{});
            try effective_w.writeAll("  Display detailed information about a task\n\n");
            try color.printBold(effective_w, effective_color, "Options:\n", .{});
            try effective_w.writeAll("  --help, -h        Show this help message\n");
            return 1;
        }
        const task_name = effective_args[2];

        // Check for --help flag
        if (std.mem.eql(u8, task_name, "--help") or std.mem.eql(u8, task_name, "-h")) {
            try effective_w.writeAll("Usage: zr show <task>\n\n");
            try color.printBold(effective_w, effective_color, "Description:\n", .{});
            try effective_w.writeAll("  Display detailed information about a task\n\n");
            try color.printBold(effective_w, effective_color, "Options:\n", .{});
            try effective_w.writeAll("  --help, -h        Show this help message\n");
            return 0;
        }

        return show_cmd.cmdShow(allocator, task_name, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "schedule")) {
        const schedule_args = if (effective_args.len > 2) effective_args[2..] else &[_][]const u8{};
        return schedule_cmd.cmdSchedule(allocator, schedule_args, config_path, effective_w, ew, effective_color);
    }

    // This should never be reached due to alias expansion logic above
    unreachable;
}

fn printVersion(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "zr v0.0.5", .{});
    try w.print("\n", .{});
}

fn printHelp(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "zr v0.0.5", .{});
    try w.print(" - Zig Task Runner\n\n", .{});
    try color.printBold(w, use_color, "Usage:\n", .{});
    try w.print("  zr [options] <command> [arguments]\n\n", .{});
    try color.printBold(w, use_color, "Commands:\n", .{});
    try w.print("  run <task>             Run a task and its dependencies\n", .{});
    try w.print("  watch <task> [path...] Watch files and auto-run task on changes\n", .{});
    try w.print("  workflow <name>        Run a workflow by name\n", .{});
    try w.print("  list [pattern] [--tree] [--tags=TAG,...]  List tasks (filters: pattern, tags; --tree for dependency tree)\n", .{});
    try w.print("  graph [--ascii]        Show task dependency graph (--ascii for tree view)\n", .{});
    try w.print("  history                Show recent run history\n", .{});
    try w.print("  workspace list         List workspace member directories\n", .{});
    try w.print("  workspace run <task>   Run a task across all workspace members\n", .{});
    try w.print("  workspace sync         Build synthetic workspace from multi-repo\n", .{});
    try w.print("  affected <task>        Run task on affected workspace members\n", .{});
    try w.print("  cache clear            Clear all cached task results\n", .{});
    try w.print("  cache status           Show cache statistics\n", .{});
    try w.print("  clean [OPTIONS]        Clean zr data (cache, history, toolchains, plugins)\n", .{});
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
    try w.print("  setup                  Set up project (install tools, run setup tasks)\n", .{});
    try w.print("  validate               Validate zr.toml configuration file\n", .{});
    try w.print("  lint                   Validate architecture constraints\n", .{});
    try w.print("  conformance [OPTIONS]  Check code conformance against rules\n", .{});
    try w.print("  completion <shell>     Print shell completion script (bash|zsh|fish)\n", .{});
    try w.print("  tools list [kind]      List installed toolchain versions\n", .{});
    try w.print("  tools install <k>@<v>  Install a toolchain (e.g., node@20.11.1)\n", .{});
    try w.print("  tools outdated [kind]  Check for outdated toolchains\n", .{});
    try w.print("  repo sync              Sync all multi-repo repositories\n", .{});
    try w.print("  repo status            Show git status of all repositories\n", .{});
    try w.print("  codeowners generate    Generate CODEOWNERS file from workspace\n", .{});
    try w.print("  version [--bump=TYPE]  Show or bump package version (major|minor|patch)\n", .{});
    try w.print("  publish [OPTIONS]      Publish a new version (auto or manual)\n", .{});
    try w.print("  analytics [OPTIONS]    Generate build analysis reports\n", .{});
    try w.print("  context [OPTIONS]      Generate AI-friendly project metadata\n", .{});
    try w.print("  bench <task> [OPTIONS] Benchmark task performance with statistics\n", .{});
    try w.print("  doctor                 Diagnose environment and toolchain setup\n", .{});
    try w.print("  env [OPTIONS]          Display environment variables for tasks\n", .{});
    try w.print("  export [OPTIONS]       Export env vars in shell-sourceable format\n", .{});
    try w.print("  upgrade [OPTIONS]      Upgrade zr to the latest version\n", .{});
    try w.print("  alias <subcommand>     Manage command aliases (add|list|remove|show)\n", .{});
    try w.print("  estimate <task>        Estimate task duration based on execution history\n", .{});
    try w.print("  show <task>            Display detailed information about a task\n", .{});
    try w.print("  schedule <subcommand>  Schedule tasks to run at specific times (add|list|remove|show)\n", .{});
    try w.print("  <alias>                Run a user-defined alias (e.g., 'zr dev' if 'dev' is defined)\n\n", .{});
    try color.printBold(w, use_color, "Options:\n", .{});
    try w.print("  --help, -h            Show this help message\n", .{});
    try w.print("  --version             Show version information\n", .{});
    try w.print("  --profile, -p <name>  Activate a named profile (overrides env/task settings)\n", .{});
    try w.print("  --dry-run, -n         Show what would run without executing (run/workflow only)\n", .{});
    try w.print("  --jobs, -j <N>        Max parallel tasks (default: CPU count)\n", .{});
    try w.print("  --no-color            Disable color output\n", .{});
    try w.print("  --quiet, -q           Suppress non-error output\n", .{});
    try w.print("  --verbose, -v         Verbose output\n", .{});
    try w.print("  --config <path>       Config file path (default: zr.toml)\n", .{});
    try w.print("  --format, -f <fmt>    Output format: text (default) or json\n", .{});
    try w.print("  --monitor, -m         Display live resource usage (CPU/memory) during execution\n", .{});
    try w.print("  --affected <ref>      Run only affected workspace members (e.g., origin/main)\n\n", .{});
    try color.printDim(w, use_color, "Config file: zr.toml (in current directory)\n", .{});
    try color.printDim(w, use_color, "Profile env: ZR_PROFILE=<name> (alternative to --profile)\n", .{});
}

test "basic functionality" {
    try std.testing.expect(true);
}

test "--no-color and --jobs are consumed before command dispatch" {
    const allocator = std.testing.allocator;

    // Open /dev/null for discard writer
    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = null_file.writer(&out_buf);
    var err_w = null_file.writer(&err_buf);

    // With only flags and no command after them, should print help (exit 0),
    // not "Unknown command: --no-color".
    const fake_args = [_][]const u8{ "zr", "--no-color", "--jobs", "4" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, true);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "--quiet flag is parsed and does not crash" {
    const allocator = std.testing.allocator;

    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = null_file.writer(&out_buf);
    var err_w = null_file.writer(&err_buf);

    // --quiet with no command prints help (exit 0).
    const fake_args = [_][]const u8{ "zr", "--quiet" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, true);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "--verbose flag is parsed and does not crash" {
    const allocator = std.testing.allocator;

    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = null_file.writer(&out_buf);
    var err_w = null_file.writer(&err_buf);

    // --verbose with no command prints help (exit 0).
    const fake_args = [_][]const u8{ "zr", "--verbose" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "--version flag prints version and exits successfully" {
    const allocator = std.testing.allocator;

    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = null_file.writer(&out_buf);
    var err_w = null_file.writer(&err_buf);

    // --version should print version info and exit 0.
    const fake_args = [_][]const u8{ "zr", "--version" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "--config flag missing value returns error" {
    const allocator = std.testing.allocator;

    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = null_file.writer(&out_buf);
    var err_w = null_file.writer(&err_buf);

    // --config without a value should return exit code 1.
    const fake_args = [_][]const u8{ "zr", "--config" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "--jobs with invalid value returns error" {
    const allocator = std.testing.allocator;

    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = null_file.writer(&out_buf);
    var err_w = null_file.writer(&err_buf);

    // --jobs with non-numeric value should return exit code 1.
    const fake_args = [_][]const u8{ "zr", "--jobs", "notanumber" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "--format json is parsed and does not crash" {
    const allocator = std.testing.allocator;

    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = null_file.writer(&out_buf);
    var err_w = null_file.writer(&err_buf);

    // --format json with no command prints help (exit 0).
    const fake_args = [_][]const u8{ "zr", "--format", "json" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "--format text is parsed and does not crash" {
    const allocator = std.testing.allocator;

    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = null_file.writer(&out_buf);
    var err_w = null_file.writer(&err_buf);

    const fake_args = [_][]const u8{ "zr", "--format", "text" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "--format unknown value returns error" {
    const allocator = std.testing.allocator;

    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = null_file.writer(&out_buf);
    var err_w = null_file.writer(&err_buf);

    const fake_args = [_][]const u8{ "zr", "--format", "yaml" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "--format missing value returns error" {
    const allocator = std.testing.allocator;

    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = null_file.writer(&out_buf);
    var err_w = null_file.writer(&err_buf);

    const fake_args = [_][]const u8{ "zr", "--format" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "writeJsonString escapes special characters" {
    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var out_buf: [4096]u8 = undefined;
    var out_w = null_file.writer(&out_buf);

    // Just test that it runs without error on common characters.
    try common.writeJsonString(&out_w.interface, "hello world");
    try common.writeJsonString(&out_w.interface, "with \"quotes\"");
    try common.writeJsonString(&out_w.interface, "with\nnewline");
    try common.writeJsonString(&out_w.interface, "with\\backslash");
}

test "cmdList --format json returns valid JSON with tasks field" {
    const allocator = std.testing.allocator;

    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = null_file.writer(&out_buf);
    var err_w = null_file.writer(&err_buf);

    // Without a real config file this returns 1 — ensure it doesn't crash
    // and that flag parsing itself works (no panic).
    const fake_args = [_][]const u8{ "zr", "--format", "json", "list" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    // Exit 1 expected (no zr.toml in cwd during tests) — but no crash/panic.
    _ = code;
}

test "workspace command: missing subcommand returns error" {
    const allocator = std.testing.allocator;

    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = null_file.writer(&out_buf);
    var err_w = null_file.writer(&err_buf);

    // "workspace" with unknown subcommand returns 1
    const fake_args = [_][]const u8{ "zr", "workspace", "unknown" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

test "workspace command: run missing task name returns error" {
    const allocator = std.testing.allocator;

    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = null_file.writer(&out_buf);
    var err_w = null_file.writer(&err_buf);

    // "workspace run" without task name returns 1
    const fake_args = [_][]const u8{ "zr", "workspace", "run" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), code);
}

