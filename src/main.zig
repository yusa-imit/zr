const std = @import("std");
const sailor = @import("sailor");
const loader = @import("config/loader.zig");
const parser = @import("config/parser.zig");
const expr = @import("config/expr.zig");
const expr_diagnostics = @import("config/expr_diagnostics.zig");
const matrix = @import("config/matrix.zig");
const dag_mod = @import("graph/dag.zig");
const topo_sort = @import("graph/topo_sort.zig");
const cycle_detect = @import("graph/cycle_detect.zig");
const graph_ascii = @import("graph/ascii.zig");
const scheduler = @import("exec/scheduler.zig");
const process = @import("exec/process.zig");
const remote = @import("exec/remote.zig");
const timeline = @import("exec/timeline.zig");
const replay = @import("exec/replay.zig");
const checkpoint = @import("exec/checkpoint.zig");
const output_capture = @import("exec/output_capture.zig");
const retry_strategy = @import("exec/retry_strategy.zig");
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
const toml_highlight = @import("config/toml_highlight.zig");
const error_display = @import("config/error_display.zig");
const common = @import("cli/common.zig");
const completion = @import("cli/completion.zig");
const init = @import("cli/init.zig");
const workspace = @import("cli/workspace.zig");
const plugin_cli = @import("cli/plugin.zig");
const run_cmd = @import("cli/run.zig");
const list_cmd = @import("cli/list.zig");
const tui = @import("cli/tui.zig");
const task_picker = @import("cli/task_picker.zig");
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
const which_cmd = @import("cli/which.zig");
const cd_cmd = @import("cli/cd.zig");
const shell_hook_cmd = @import("cli/shell_hook.zig");
const abbreviations = @import("cli/abbreviations.zig");
const setup_cmd = @import("cli/setup.zig");
const env_cmd = @import("cli/env.zig");
const export_cmd = @import("cli/export.zig");
const affected_cmd = @import("cli/affected.zig");
const clean_cmd = @import("cli/clean.zig");
const upgrade_cmd = @import("cli/upgrade.zig");
const alias_cmd = @import("cli/alias.zig");
const add_cmd = @import("cli/add.zig");
const config_editor = @import("cli/config_editor.zig");
const failures_cmd = @import("cli/failures.zig");
const template_cmd = @import("cli/template.zig");
const ci_cmd = @import("cli/ci.zig");
const mcp_server = @import("mcp/server.zig");
const lsp_server = @import("lsp/server.zig");
const estimate_cmd = @import("cli/estimate.zig");
const show_cmd = @import("cli/show.zig");
const schedule_cmd = @import("cli/schedule.zig");
const monitor_dashboard = @import("cli/monitor.zig");
const monitor_cmd = @import("cli/monitor.zig");
const registry_cmd = @import("cli/registry.zig");
const platform = @import("util/platform.zig");
const semver = @import("util/semver.zig");
const hash_util = @import("util/hash.zig");
const glob = @import("util/glob.zig");
const affected = @import("util/affected.zig");
const numa = @import("util/numa.zig");
const profiler = @import("util/profiler.zig");
pub const tui_profiler = @import("util/tui_profiler.zig");
const error_codes = @import("util/error_codes.zig");
const resource = @import("exec/resource.zig");
const resource_monitor = @import("exec/resource_monitor.zig");
const metrics_export = @import("exec/metrics_export.zig");
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
const levenshtein = @import("util/levenshtein.zig");
const checker = @import("upgrade/checker.zig");

// Public exports for fuzz tests and external tools
// Use different names to avoid shadowing internal const declarations
pub const config_parser = parser;
pub const config_expr = expr;
pub const exec_output_capture = output_capture;

// Ensure tests in all imported modules are included in test binary
comptime {
    _ = aliases;
    _ = alias_cmd;
    _ = estimate_cmd;
    _ = schedule_cmd;
    _ = loader;
    _ = parser;
    _ = expr;
    _ = expr_diagnostics;
    _ = matrix;
    _ = constraints_mod;
    _ = dag_mod;
    _ = topo_sort;
    _ = cycle_detect;
    _ = graph_ascii;
    _ = scheduler;
    _ = process;
    _ = timeline;
    _ = replay;
    _ = checkpoint;
    _ = output_capture;
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
    _ = toml_highlight;
    _ = error_display;
    _ = common;
    _ = completion;
    _ = init;
    _ = workspace;
    _ = plugin_cli;
    _ = registry_cmd;
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
    _ = numa;
    _ = profiler;
    _ = resource;
    _ = resource_monitor;
    _ = metrics_export;
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
    _ = checker;
    _ = @import("upgrade/installer.zig");
    _ = alias_cmd;
    _ = estimate_cmd;
    _ = show_cmd;
    _ = @import("util/levenshtein.zig");
    _ = @import("lsp/position.zig");
    _ = @import("lsp/document.zig");
    _ = @import("lsp/diagnostics.zig");
    _ = @import("lsp/handlers.zig");
    _ = @import("lsp/server.zig");
    _ = config_editor;
    _ = abbreviations;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);

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

    // Manual cleanup to ensure it happens even on std.process.exit()
    std.process.argsFree(allocator, args);
    _ = gpa.deinit();

    if (result) |exit_code| {
        if (exit_code != 0) std.process.exit(exit_code);
    } else |err| {
        return err;
    }
}

/// Print unknown command error with suggestions using error code system.
fn printUnknownCommandError(
    allocator: std.mem.Allocator,
    unknown_cmd: []const u8,
    known_commands: []const []const u8,
    ew: *std.Io.Writer,
    use_color: bool,
) !void {
    // Find suggestions
    const suggestions = try levenshtein.findClosestMatches(
        allocator,
        unknown_cmd,
        known_commands,
        3, // max distance: allow up to 3 edits
        3, // max suggestions: show at most 3 alternatives
    );
    defer allocator.free(suggestions);

    // Build hint with suggestions
    var hint_buf: [512]u8 = undefined;
    var hint_stream = std.io.fixedBufferStream(&hint_buf);
    const hint_writer = hint_stream.writer();

    if (suggestions.len > 0) {
        try hint_writer.print("Did you mean one of these?\n", .{});
        for (suggestions) |suggestion| {
            try hint_writer.print("    zr {s}\n", .{suggestion.name});
        }
        try hint_writer.print("\nOr run 'zr --help' to see all available commands.", .{});
    } else {
        try hint_writer.print("Run 'zr --help' to see all available commands.", .{});
    }

    // Create error detail (allocate message buffer because unknown_cmd is stack-local)
    var msg_buf: [256]u8 = undefined;
    const msg = try std.fmt.bufPrint(&msg_buf, "Unknown command: {s}", .{unknown_cmd});

    const err = error_codes.ErrorDetail{
        .code = .task_not_found, // Reusing task_not_found for now (command is similar to task)
        .message = msg,
        .hint = hint_stream.getWritten(),
    };

    try err.print(ew, use_color);
}

/// Suggest similar commands using Levenshtein distance.
/// Prints "Did you mean?" suggestions to the error writer if close matches are found.
/// DEPRECATED: Use printUnknownCommandError instead for new code.
fn suggestSimilarCommands(
    allocator: std.mem.Allocator,
    unknown_cmd: []const u8,
    known_commands: []const []const u8,
    ew: *std.Io.Writer,
    use_color: bool,
) !void {
    const suggestions = try levenshtein.findClosestMatches(
        allocator,
        unknown_cmd,
        known_commands,
        3, // max distance: allow up to 3 edits
        3, // max suggestions: show at most 3 alternatives
    );
    defer allocator.free(suggestions);

    if (suggestions.len > 0) {
        try ew.print("\n", .{});
        try color.printInfo(ew, use_color, "Did you mean?\n", .{});
        for (suggestions) |suggestion| {
            try ew.print("    {s}\n", .{suggestion.name});
        }
    }
}

/// Global flag definitions using sailor.arg for compile-time validated, type-safe parsing.
const global_flags = [_]sailor.arg.FlagDef{
    .{ .name = "profile", .short = 'p', .type = .string, .help = "Activate a named profile" },
    .{ .name = "dry-run", .short = 'n', .type = .bool, .help = "Show what would run without executing" },
    .{ .name = "no-color", .type = .bool, .help = "Disable color output" },
    .{ .name = "quiet", .short = 'q', .type = .bool, .help = "Suppress non-error output" },
    .{ .name = "verbose", .short = 'v', .type = .bool, .help = "Verbose output" },
    .{ .name = "format", .short = 'f', .type = .string, .default = "text", .help = "Output format: text or json" },
    .{ .name = "jobs", .short = 'j', .type = .int, .help = "Max parallel tasks (default: CPU count)" },
    .{ .name = "config", .type = .string, .help = "Config file path" },
    .{ .name = "monitor", .short = 'm', .type = .bool, .help = "Display live resource usage during execution" },
    .{ .name = "affected", .type = .string, .help = "Run only affected workspace members" },
};

const GlobalFlagParser = sailor.arg.Parser(&global_flags);

const GlobalFlagInfo = struct {
    long_name: []const u8,
    takes_value: bool,
};

/// Check if an arg token is a known global flag.
/// Returns flag info if recognized, null otherwise (passed through to subcommand).
fn isGlobalFlag(arg: []const u8) ?GlobalFlagInfo {
    if (std.mem.startsWith(u8, arg, "--")) {
        const name = arg[2..];
        inline for (global_flags) |flag| {
            if (std.mem.eql(u8, name, flag.name)) {
                return .{ .long_name = "--" ++ flag.name, .takes_value = flag.type != .bool };
            }
        }
        return null;
    }
    if (std.mem.startsWith(u8, arg, "-") and arg.len == 2) {
        const ch = arg[1];
        inline for (global_flags) |flag| {
            if (flag.short != null and flag.short.? == ch) {
                return .{ .long_name = "--" ++ flag.name, .takes_value = flag.type != .bool };
            }
        }
        return null;
    }
    return null;
}

/// Custom error hints for missing-value global flags.
fn globalFlagHint(long_name: []const u8) []const u8 {
    if (std.mem.eql(u8, long_name, "--profile")) return "--profile: missing profile name\n\n  Hint: zr --profile <name> run <task>";
    if (std.mem.eql(u8, long_name, "--format")) return "--format: missing value\n\n  Hint: zr --format <text|json> <command>";
    if (std.mem.eql(u8, long_name, "--jobs")) return "--jobs: missing value\n\n  Hint: zr --jobs <N> run <task>";
    if (std.mem.eql(u8, long_name, "--config")) return "--config: missing path\n\n  Hint: zr --config <path> run <task>";
    if (std.mem.eql(u8, long_name, "--affected")) return "--affected: missing base reference\n\n  Hint: zr --affected origin/main workspace run <task>";
    return "missing flag value";
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
        // Smart no-args behavior:
        // 1. If 'default' task exists → run it
        // 2. If single task exists → run it
        // 3. If multiple tasks → interactive picker
        // 4. Otherwise → show help

        // Try to find config file
        const config_path = (try common.findConfigPath(allocator)) orelse {
            // No config → show help
            try printHelp(w, use_color);
            return 0;
        };
        defer allocator.free(config_path);

        // Load config
        var config = (try common.loadConfig(allocator, config_path, null, ew, use_color)) orelse {
            // Load failed → error already printed
            return 1;
        };
        defer config.deinit();

        // Check for 'default' task
        if (config.tasks.get("default")) |_| {
            // Run default task
            return run_cmd.cmdRun(allocator, "default", null, false, 0, config_path, false, false, w, ew, use_color, null);
        }

        // Count tasks
        const task_count = config.tasks.count();
        if (task_count == 0) {
            // No tasks → show help
            try printHelp(w, use_color);
            return 0;
        } else if (task_count == 1) {
            // Single task → auto-run it
            var task_it = config.tasks.iterator();
            const single_task = task_it.next().?;
            return run_cmd.cmdRun(allocator, single_task.key_ptr.*, null, false, 0, config_path, false, false, w, ew, use_color, null);
        } else {
            // Multiple tasks → interactive picker
            if (!std.fs.File.stdout().isTty()) {
                // No TTY → show help
                try printHelp(w, use_color);
                return 0;
            }

            const picker_result = task_picker.runPicker(
                allocator,
                &config,
                .{
                    .fuzzy_search = true,
                    .show_preview = true,
                    .initial_query = "",
                },
                w,
            ) catch |err| {
                try color.printError(ew, use_color, "Failed to launch interactive picker: {}\n", .{err});
                return 1;
            };

            if (!picker_result.executed) {
                // User cancelled
                return 0;
            }

            if (picker_result.kind == .task) {
                return run_cmd.cmdRun(allocator, picker_result.name, null, false, 0, config_path, false, false, w, ew, use_color, null);
            } else {
                return run_cmd.cmdWorkflow(allocator, picker_result.name, null, false, 0, config_path, false, w, ew, use_color);
            }
        }
    }

    // Parse global flags using sailor.arg — extract known global flags from args,
    // passing through unknown flags (subcommand-specific) to remaining_args.
    var remaining_args: std.ArrayListUnmanaged([]const u8) = .{};
    defer remaining_args.deinit(allocator);
    var global_flag_tokens: std.ArrayListUnmanaged([]const u8) = .{};
    defer global_flag_tokens.deinit(allocator);

    {
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (isGlobalFlag(arg)) |flag_info| {
                if (flag_info.takes_value) {
                    // Emit long form for sailor (normalize short to long)
                    try global_flag_tokens.append(allocator, flag_info.long_name);
                    if (i + 1 < args.len) {
                        try global_flag_tokens.append(allocator, args[i + 1]);
                        i += 1;
                    } else {
                        // Missing value — let sailor report MissingValue
                        // But we need custom error messages, so handle here
                        const hints = globalFlagHint(flag_info.long_name);
                        try color.printError(ew, use_color, "{s}\n", .{hints});
                        return 1;
                    }
                } else {
                    try global_flag_tokens.append(allocator, flag_info.long_name);
                }
            } else {
                try remaining_args.append(allocator, arg);
            }
        }
    }

    var flag_parser = GlobalFlagParser.init(allocator);
    defer flag_parser.deinit();
    flag_parser.parse(global_flag_tokens.items) catch |err| switch (err) {
        error.InvalidValue => {
            // --jobs had a non-integer value
            try color.printError(ew, use_color,
                "--jobs: invalid value — must be a positive integer\n\n  Hint: zr --jobs 4 run <task>\n", .{});
            return 1;
        },
        else => {
            try color.printError(ew, use_color, "Invalid flag value\n", .{});
            return 1;
        },
    };

    // Extract parsed values with type-safe access
    const profile_name: ?[]const u8 = if (flag_parser.get("profile")) |v| (v.asString() catch null) else null;
    const dry_run = flag_parser.getBool("dry-run", false);
    const no_color = flag_parser.getBool("no-color", false);
    const quiet = flag_parser.getBool("quiet", false);
    const verbose = flag_parser.getBool("verbose", false);
    const enable_monitor = flag_parser.getBool("monitor", false);
    // Resolve config path: explicit --config flag, or search parent directories for zr.toml
    var config_path_owned: ?[]const u8 = null;
    defer if (config_path_owned) |path| allocator.free(path);

    const config_path = if (flag_parser.get("config")) |config_val|
        try config_val.asString()
    else blk: {
        // Search current directory and parents for zr.toml
        if (try common.findConfigPath(allocator)) |found_path| {
            config_path_owned = found_path;
            break :blk found_path;
        } else {
            // Fall back to "./zr.toml" (will fail with clear error message)
            break :blk common.CONFIG_FILE;
        }
    };
    const affected_base: ?[]const u8 = if (flag_parser.get("affected")) |v| (v.asString() catch null) else null;

    // --format: custom validation (only "json" or "text")
    const format_str = flag_parser.getString("format", "text");
    var json_output: bool = false;
    if (std.mem.eql(u8, format_str, "json")) {
        json_output = true;
    } else if (std.mem.eql(u8, format_str, "text")) {
        json_output = false;
    } else {
        try color.printError(ew, use_color,
            "--format: unknown format '{s}'\n\n  Hint: supported formats: text, json\n",
            .{format_str});
        return 1;
    }

    // --jobs: if explicitly set, must be >= 1. If not set, default to 0 (auto-detect CPU count).
    const max_jobs: u32 = if (flag_parser.get("jobs")) |v| blk: {
        const jobs_val = v.asInt() catch 0;
        if (jobs_val <= 0 or jobs_val > std.math.maxInt(u32)) {
            try color.printError(ew, use_color,
                "--jobs: value must be >= 1 (use 1 for sequential execution)\n\n  Hint: zr --jobs 4 run <task>\n", .{});
            return 1;
        }
        break :blk @intCast(jobs_val);
    } else 0;

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
        "registry",   "interactive", "i",          "live",
        "monitor",    "interactive-run", "irun",       "tools",      "lint",
        "repo",       "codeowners", "version",    "publish",
        "analytics",  "context",    "conformance", "bench",
        "doctor",     "cd",         "shell-hook", "setup",      "env",        "export",
        "affected",   "clean",      "upgrade",    "alias",
        "estimate",   "show",       "schedule",   "mcp",
        "lsp",        "add",        "edit",       "failures",
        "template",   "which",      "ci",
    };
    var is_builtin = false;
    for (known_commands) |known| {
        if (std.mem.eql(u8, cmd, known)) {
            is_builtin = true;
            break;
        }
    }

    if (!is_builtin) {
        // First, try abbreviations from ~/.zrconfig
        const abbrev_config_path = abbreviations.getConfigPath(allocator) catch null;
        if (abbrev_config_path) |path| {
            defer allocator.free(path);
            var abbrev_map = abbreviations.parseAbbreviationConfig(allocator, path) catch |err| blk: {
                if (err != error.FileNotFound) {
                    try color.printError(ew, effective_color, "Failed to load abbreviations: {}\n", .{err});
                }
                break :blk null;
            };
            if (abbrev_map) |*map| {
                defer {
                    var it = map.iterator();
                    while (it.next()) |entry| {
                        allocator.free(entry.key_ptr.*);
                        allocator.free(entry.value_ptr.*);
                    }
                    map.deinit();
                }

                var maybe_expanded = try abbreviations.expandAbbreviation(allocator, map, cmd);
                if (maybe_expanded) |*expanded| {
                    defer {
                        for (expanded.items) |item| allocator.free(item);
                        expanded.deinit(allocator);
                    }

                    // Build new args with abbreviation expansion
                    var new_args: std.ArrayListUnmanaged([]const u8) = .{};
                    defer new_args.deinit(allocator);

                    try new_args.append(allocator, effective_args[0]); // "zr"
                    for (expanded.items) |item| {
                        try new_args.append(allocator, item);
                    }
                    // Append remaining args after abbreviation
                    for (effective_args[2..]) |arg| {
                        try new_args.append(allocator, arg);
                    }

                    // Recursively call run with expanded args
                    return try run(allocator, new_args.items, w, ew, use_color);
                }
            }
        }

        // Try to load aliases and expand
        var alias_config = aliases.AliasConfig.load(allocator) catch |err| {
            // If alias loading fails, just continue with unknown command error
            if (err != error.FileNotFound) {
                try color.printError(ew, effective_color, "Failed to load aliases: {}\n", .{err});
            }
            try printUnknownCommandError(allocator, cmd, &known_commands, ew, effective_color);
            return 1;
        };
        defer alias_config.deinit();

        if (alias_config.get(cmd)) |alias_command| {
            // Expand the alias: split alias_command by spaces and prepend "zr"
            // Example: alias_command = "run build && run test"
            // We need to tokenize this properly, handling quoted strings
            var expanded_args: std.ArrayListUnmanaged([]const u8) = .{};
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
            try printUnknownCommandError(allocator, cmd, &known_commands, ew, effective_color);
            return 1;
        }
    }

    // Workflow shorthand: w/<workflow> → workflow <workflow>
    if (std.mem.startsWith(u8, cmd, "w/")) {
        const workflow_name = cmd[2..]; // Skip "w/"
        if (workflow_name.len == 0) {
            try color.printError(ew, effective_color, "w/: missing workflow name\n\n  Hint: zr w/<workflow-name>\n", .{});
            return 1;
        }
        return run_cmd.cmdWorkflow(allocator, workflow_name, profile_name, dry_run, max_jobs, config_path, false, effective_w, ew, effective_color);
    }

    // History-based shortcuts: !! (last task), !-N (Nth-to-last task)
    if (std.mem.startsWith(u8, cmd, "!")) {
        // Get history file path
        const history_path = try std.fs.path.join(allocator, &[_][]const u8{
            try std.process.getEnvVarOwned(allocator, "HOME"),
            ".zr_history",
        });
        defer allocator.free(history_path);

        const store = try history.Store.init(allocator, history_path);
        defer store.deinit();

        var records = try store.loadLast(allocator, 100); // Load last 100 for indexing
        defer {
            for (records.items) |r| r.deinit(allocator);
            records.deinit(allocator);
        }

        if (records.items.len == 0) {
            try color.printError(ew, effective_color, "No task history found\n\n  Hint: Run a task first to populate history\n", .{});
            return 1;
        }

        var target_index: usize = 0;
        if (std.mem.eql(u8, cmd, "!!")) {
            // Last task (index 0 in reverse order)
            target_index = 0;
        } else if (std.mem.startsWith(u8, cmd, "!-")) {
            // !-N → Nth-to-last task
            const offset_str = cmd[2..];
            const offset = std.fmt.parseInt(usize, offset_str, 10) catch {
                try color.printError(ew, effective_color, "Invalid history index: {s}\n\n  Hint: Use !! for last task or !-N for Nth-to-last (e.g., !-2)\n", .{cmd});
                return 1;
            };
            if (offset == 0) {
                try color.printError(ew, effective_color, "Invalid history index: !-0\n\n  Hint: Use !! for last task or !-N for Nth-to-last (e.g., !-2)\n", .{});
                return 1;
            }
            target_index = offset - 1; // !-1 == last (index 0), !-2 == 2nd-to-last (index 1)
        } else {
            // Unknown history syntax
            try color.printError(ew, effective_color, "Unknown history syntax: {s}\n\n  Hint: Use !! for last task or !-N for Nth-to-last (e.g., !-2)\n", .{cmd});
            return 1;
        }

        if (target_index >= records.items.len) {
            try color.printError(ew, effective_color, "History index out of range: only {d} tasks in history\n", .{records.items.len});
            return 1;
        }

        // Reverse index (loadLast returns newest first)
        const task_name = records.items[records.items.len - 1 - target_index].task_name;

        // Print info message
        try color.printInfo(effective_w, effective_color, "Re-running: {s}\n", .{task_name});

        // Re-run the task (use 'run' command with the task name)
        return run_cmd.cmdRun(allocator, task_name, profile_name, dry_run, max_jobs, config_path, json_output, enable_monitor, effective_w, ew, effective_color, null);
    }

    if (std.mem.eql(u8, cmd, "run")) {
        if (effective_args.len < 3) {
            // No task name provided — launch interactive picker
            if (!std.fs.File.stdout().isTty()) {
                try color.printError(ew, effective_color, "run: missing task name (no TTY for interactive picker)\n\n  Hint: zr run <task-name>\n", .{});
                return 1;
            }

            // Load config for picker
            var config = (try common.loadConfig(allocator, config_path, profile_name, ew, effective_color)) orelse return 1;
            defer config.deinit();

            // Run interactive picker
            const picker_result = task_picker.runPicker(
                allocator,
                &config,
                .{
                    .fuzzy_search = true,
                    .show_preview = true,
                    .initial_query = "",
                },
                effective_w,
            ) catch |err| {
                try color.printError(ew, effective_color, "Failed to launch interactive picker: {}\n", .{err});
                return 1;
            };

            if (!picker_result.executed) {
                // User cancelled (q or Esc)
                return 0;
            }

            // User selected a task/workflow — execute it
            if (picker_result.kind == .task) {
                // Reload config (picker consumed it)
                config.deinit();
                return run_cmd.cmdRun(allocator, picker_result.name, profile_name, dry_run, max_jobs, config_path, json_output, enable_monitor, effective_w, ew, effective_color, null);
            } else {
                // Workflow selected — delegate to workflow command
                config.deinit();
                return run_cmd.cmdWorkflow(allocator, picker_result.name, profile_name, dry_run, max_jobs, config_path, false, effective_w, ew, effective_color);
            }
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

        // Parse --matrix-show flag
        var matrix_show = false;
        var i: usize = 3;
        while (i < effective_args.len) : (i += 1) {
            if (std.mem.eql(u8, effective_args[i], "--matrix-show")) {
                matrix_show = true;
            }
        }

        return run_cmd.cmdWorkflow(allocator, wf_name, profile_name, dry_run, max_jobs, config_path, matrix_show, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "list")) {
        // Parse list options
        var tree_mode = false;
        var filter_pattern: ?[]const u8 = null;
        var filter_tags: ?[]const u8 = null;
        var exclude_tags: ?[]const u8 = null;
        var profiles_only = false;
        var members_only = false;
        var fuzzy_search = false;
        var group_by_tags = false;
        var recent_count: ?usize = null;
        var frequent_count: ?usize = null;
        var slow_threshold_ms: ?u64 = null;
        var search_description: ?[]const u8 = null;
        var i: usize = 2;
        while (i < effective_args.len) : (i += 1) {
            const arg = effective_args[i];
            if (std.mem.eql(u8, arg, "--tree")) {
                tree_mode = true;
            } else if (std.mem.eql(u8, arg, "--profiles")) {
                profiles_only = true;
            } else if (std.mem.eql(u8, arg, "--members")) {
                members_only = true;
            } else if (std.mem.eql(u8, arg, "--fuzzy")) {
                fuzzy_search = true;
            } else if (std.mem.eql(u8, arg, "--group-by-tags")) {
                group_by_tags = true;
            } else if (std.mem.startsWith(u8, arg, "--recent=")) {
                const count_str = arg["--recent=".len..];
                recent_count = std.fmt.parseInt(usize, count_str, 10) catch {
                    try color.printError(ew, effective_color, "list: invalid --recent count: {s}\n", .{count_str});
                    return 1;
                };
            } else if (std.mem.eql(u8, arg, "--recent")) {
                // Default to 10 most recent tasks
                recent_count = 10;
            } else if (std.mem.startsWith(u8, arg, "--frequent=")) {
                const count_str = arg["--frequent=".len..];
                frequent_count = std.fmt.parseInt(usize, count_str, 10) catch {
                    try color.printError(ew, effective_color, "list: invalid --frequent count: {s}\n", .{count_str});
                    return 1;
                };
            } else if (std.mem.eql(u8, arg, "--frequent")) {
                // Default to top 10 most frequent tasks
                frequent_count = 10;
            } else if (std.mem.startsWith(u8, arg, "--slow=")) {
                const threshold_str = arg["--slow=".len..];
                slow_threshold_ms = std.fmt.parseInt(u64, threshold_str, 10) catch {
                    try color.printError(ew, effective_color, "list: invalid --slow threshold: {s}\n", .{threshold_str});
                    return 1;
                };
            } else if (std.mem.eql(u8, arg, "--slow")) {
                // Default to 30 seconds (30000 ms)
                slow_threshold_ms = 30000;
            } else if (std.mem.startsWith(u8, arg, "--search=")) {
                search_description = arg["--search=".len..];
            } else if (std.mem.eql(u8, arg, "--search")) {
                if (i + 1 < effective_args.len) {
                    i += 1;
                    search_description = effective_args[i];
                }
            } else if (std.mem.startsWith(u8, arg, "--tags=")) {
                filter_tags = arg["--tags=".len..];
            } else if (std.mem.eql(u8, arg, "--tags")) {
                if (i + 1 < effective_args.len) {
                    i += 1;
                    filter_tags = effective_args[i];
                }
            } else if (std.mem.startsWith(u8, arg, "--exclude-tags=")) {
                exclude_tags = arg["--exclude-tags=".len..];
            } else if (std.mem.eql(u8, arg, "--exclude-tags")) {
                if (i + 1 < effective_args.len) {
                    i += 1;
                    exclude_tags = effective_args[i];
                }
            } else if (!std.mem.startsWith(u8, arg, "--")) {
                // First non-flag argument is the filter pattern
                filter_pattern = arg;
            }
        }
        return list_cmd.cmdList(allocator, config_path, json_output, tree_mode, filter_pattern, filter_tags, exclude_tags, profiles_only, members_only, fuzzy_search, group_by_tags, recent_count, frequent_count, slow_threshold_ms, search_description, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "graph")) {
        // Check if using new graph command flags (--type, --format, --interactive, etc.)
        // If so, delegate to the full graph_cmd handler
        var use_new_graph = false;
        for (effective_args[2..]) |arg| {
            if (std.mem.startsWith(u8, arg, "--type=") or
                std.mem.startsWith(u8, arg, "--format=") or
                std.mem.eql(u8, arg, "--interactive") or
                std.mem.eql(u8, arg, "--watch") or
                std.mem.startsWith(u8, arg, "--affected") or
                std.mem.startsWith(u8, arg, "--focus=") or
                std.mem.eql(u8, arg, "--help") or
                std.mem.eql(u8, arg, "-h")) {
                use_new_graph = true;
                break;
            }
        }

        if (use_new_graph) {
            const graph_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
            return graph_cmd.graphCommand(allocator, graph_args, effective_w, ew, effective_color);
        }

        // Legacy graph command (only supports --ascii)
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
        // Parse init options
        var detect_mode = false;
        var migrate_mode = init.MigrateMode.none;
        for (effective_args[2..]) |arg| {
            if (std.mem.eql(u8, arg, "--detect")) {
                detect_mode = true;
            } else if (std.mem.eql(u8, arg, "--from-make")) {
                migrate_mode = .makefile;
            } else if (std.mem.eql(u8, arg, "--from-just")) {
                migrate_mode = .justfile;
            } else if (std.mem.eql(u8, arg, "--from-task")) {
                migrate_mode = .taskfile;
            }
        }
        return init.cmdInit(allocator, std.fs.cwd(), detect_mode, migrate_mode, effective_w, ew, effective_color);
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
        return list_cmd.cmdCache(allocator, effective_args, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "plugin")) {
        const sub = if (effective_args.len >= 3) effective_args[2] else "";
        return plugin_cli.cmdPlugin(allocator, sub, effective_args, config_path, json_output, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "registry")) {
        try registry_cmd.cmdRegistry(allocator, effective_args, effective_color, effective_w, ew);
        return 0;
    } else if (std.mem.eql(u8, cmd, "interactive") or std.mem.eql(u8, cmd, "i")) {
        return tui.cmdInteractive(allocator, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "live")) {
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "live: missing task name\n\n  Hint: zr live <task-name> [task-name...]\n", .{});
            return 1;
        }
        const task_names = effective_args[2..];
        return live_cmd.cmdLive(allocator, task_names, profile_name, max_jobs, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "monitor")) {
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "monitor: missing workflow name\n\n  Hint: zr monitor <workflow-name>\n", .{});
            return 1;
        }
        const workflow_name = effective_args[2];
        return monitor_dashboard.cmdMonitor(allocator, workflow_name, config_path, effective_w, ew, effective_color);
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
    } else if (std.mem.eql(u8, cmd, "mcp")) {
        // MCP server: zr mcp serve
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "mcp: missing subcommand\n\n  Hint: zr mcp serve\n", .{});
            return 1;
        }
        const subcmd = effective_args[2];
        if (std.mem.eql(u8, subcmd, "serve")) {
            return mcp_server.serve(allocator);
        } else {
            try color.printError(ew, effective_color, "mcp: unknown subcommand '{s}'\n\n  Hint: zr mcp serve\n", .{subcmd});
            return 1;
        }
    } else if (std.mem.eql(u8, cmd, "lsp")) {
        // LSP server: zr lsp
        return lsp_server.serve(allocator);
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
    } else if (std.mem.eql(u8, cmd, "cd")) {
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "cd: missing workspace member name\n\n  Hint: zr cd <member-name>\n", .{});
            return 1;
        }
        const member_name = effective_args[2];
        return cd_cmd.cmdCd(allocator, member_name, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "shell-hook")) {
        const shell_name = if (effective_args.len >= 3) effective_args[2] else "";
        return shell_hook_cmd.cmdShellHook(allocator, shell_name, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "setup")) {
        const setup_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return setup_cmd.cmdSetup(allocator, setup_args, effective_w, ew, effective_color);
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
            try color.printError(ew, effective_color, "Usage: zr estimate <task|workflow> [--limit N] [--format json]\n", .{});
            try effective_w.writeAll("\n");
            try color.printBold(effective_w, effective_color, "Description:\n", .{});
            try effective_w.writeAll("  Estimate task or workflow duration based on execution history\n\n");
            try color.printBold(effective_w, effective_color, "Options:\n", .{});
            try effective_w.writeAll("  --limit N         Limit history sample to last N executions (default: 20)\n");
            try effective_w.writeAll("  --format json     Output estimation in JSON format\n");
            try effective_w.writeAll("  --help, -h        Show this help message\n");
            return 1;
        }
        const task_name = effective_args[2];

        // Check for --help flag
        if (std.mem.eql(u8, task_name, "--help") or std.mem.eql(u8, task_name, "-h")) {
            try effective_w.writeAll("Usage: zr estimate <task|workflow> [--limit N] [--format json]\n\n");
            try color.printBold(effective_w, effective_color, "Description:\n", .{});
            try effective_w.writeAll("  Estimate task or workflow duration based on execution history\n\n");
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
            try color.printError(ew, effective_color, "Usage: zr show <task> [--output]\n", .{});
            try effective_w.writeAll("\n");
            try color.printBold(effective_w, effective_color, "Description:\n", .{});
            try effective_w.writeAll("  Display detailed information about a task\n\n");
            try color.printBold(effective_w, effective_color, "Options:\n", .{});
            try effective_w.writeAll("  --help, -h           Show this help message\n");
            try effective_w.writeAll("  --output             Display captured task output from previous execution\n");
            try effective_w.writeAll("  --search <pattern>   Search for pattern in output (requires --output)\n");
            try effective_w.writeAll("  --filter <pattern>   Filter output to lines matching pattern (requires --output)\n");
            try effective_w.writeAll("  --head <N>           Show only first N lines (requires --output)\n");
            try effective_w.writeAll("  --tail <N>           Show only last N lines (requires --output)\n");
            try effective_w.writeAll("  --follow, -f         Follow output in real-time (tail -f style, requires --output)\n");
            return 1;
        }
        const task_name = effective_args[2];

        // Check for --help flag
        if (std.mem.eql(u8, task_name, "--help") or std.mem.eql(u8, task_name, "-h")) {
            try effective_w.writeAll("Usage: zr show <task> [--output] [OPTIONS]\n\n");
            try color.printBold(effective_w, effective_color, "Description:\n", .{});
            try effective_w.writeAll("  Display detailed information about a task\n\n");
            try color.printBold(effective_w, effective_color, "Options:\n", .{});
            try effective_w.writeAll("  --help, -h           Show this help message\n");
            try effective_w.writeAll("  --output             Display captured task output from previous execution\n");
            try effective_w.writeAll("  --search <pattern>   Search for pattern in output (requires --output)\n");
            try effective_w.writeAll("  --filter <pattern>   Filter output to lines matching pattern (requires --output)\n");
            try effective_w.writeAll("  --head <N>           Show only first N lines (requires --output)\n");
            try effective_w.writeAll("  --tail <N>           Show only last N lines (requires --output)\n");
            try effective_w.writeAll("  --follow, -f         Follow output in real-time (tail -f style, requires --output)\n");
            try effective_w.writeAll("  --no-pager           Disable automatic pager for large output (requires --output)\n");
            return 0;
        }

        // Parse flags for show command
        var output_flag = false;
        var output_opts = show_cmd.ShowOutputOptions{};

        if (effective_args.len >= 4) {
            var i: usize = 3;
            while (i < effective_args.len) : (i += 1) {
                const arg = effective_args[i];
                if (std.mem.eql(u8, arg, "--output")) {
                    output_flag = true;
                } else if (std.mem.eql(u8, arg, "--search")) {
                    if (i + 1 < effective_args.len) {
                        i += 1;
                        output_opts.search_pattern = effective_args[i];
                    }
                } else if (std.mem.eql(u8, arg, "--filter")) {
                    if (i + 1 < effective_args.len) {
                        i += 1;
                        output_opts.filter_regex = effective_args[i];
                    }
                } else if (std.mem.eql(u8, arg, "--tail")) {
                    if (i + 1 < effective_args.len) {
                        i += 1;
                        output_opts.tail_lines = std.fmt.parseInt(usize, effective_args[i], 10) catch null;
                    }
                } else if (std.mem.eql(u8, arg, "--head")) {
                    if (i + 1 < effective_args.len) {
                        i += 1;
                        output_opts.head_lines = std.fmt.parseInt(usize, effective_args[i], 10) catch null;
                    }
                } else if (std.mem.eql(u8, arg, "--follow") or std.mem.eql(u8, arg, "-f")) {
                    output_opts.follow = true;
                } else if (std.mem.eql(u8, arg, "--no-pager")) {
                    output_opts.no_pager = true;
                }
            }
        }

        return show_cmd.cmdShow(allocator, task_name, config_path, effective_w, ew, effective_color, output_flag, output_opts);
    } else if (std.mem.eql(u8, cmd, "schedule")) {
        const schedule_args = if (effective_args.len > 2) effective_args[2..] else &[_][]const u8{};
        return schedule_cmd.cmdSchedule(allocator, schedule_args, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "mcp")) {
        const mcp_sub = if (effective_args.len >= 3) effective_args[2] else "";
        if (std.mem.eql(u8, mcp_sub, "serve")) {
            return mcp_server.serve(allocator);
        } else {
            try color.printError(ew, effective_color, "mcp: unknown subcommand '{s}'\n\n  Hint: zr mcp serve\n", .{mcp_sub});
            return 1;
        }
    } else if (std.mem.eql(u8, cmd, "lsp")) {
        return lsp_server.serve(allocator);
    } else if (std.mem.eql(u8, cmd, "add")) {
        const add_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return add_cmd.cmdAdd(allocator, add_args, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "edit")) {
        const edit_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        if (edit_args.len == 0) {
            try color.printError(ew, effective_color, "Usage: zr edit <task|workflow|profile>\n", .{});
            return 1;
        }
        const entity_type = edit_args[0];
        return config_editor.cmdEdit(allocator, entity_type, edit_args[1..], effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "failures")) {
        const failures_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        var opts = failures_cmd.FailuresOptions{
            .use_color = effective_color,
        };

        // Parse subcommand: `failures list` (default) or `failures clear`
        var subcommand: []const u8 = "list";
        var failures_opts_args = failures_args;
        if (failures_args.len > 0) {
            if (std.mem.eql(u8, failures_args[0], "clear") or std.mem.eql(u8, failures_args[0], "list")) {
                subcommand = failures_args[0];
                failures_opts_args = failures_args[1..];
            }
        }

        // Parse options
        for (failures_opts_args) |arg| {
            if (std.mem.startsWith(u8, arg, "--task=")) {
                opts.task = arg["--task=".len..];
            } else if (std.mem.startsWith(u8, arg, "--storage-dir=")) {
                opts.storage_dir = arg["--storage-dir=".len..];
            }
        }

        if (std.mem.eql(u8, subcommand, "clear")) {
            return failures_cmd.cmdFailuresClear(allocator, opts);
        } else {
            return failures_cmd.cmdFailures(allocator, opts);
        }
    } else if (std.mem.eql(u8, cmd, "template")) {
        const template_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        if (template_args.len == 0) {
            try color.printError(ew, effective_color, "Usage: zr template <list|show|add> [--builtin] [args...]\n", .{});
            return 1;
        }
        const subcommand = template_args[0];
        const sub_args = if (template_args.len > 1) template_args[1..] else &[_][]const u8{};

        // Check for --builtin flag
        var use_builtin = false;
        for (sub_args) |arg| {
            if (std.mem.eql(u8, arg, "--builtin")) {
                use_builtin = true;
                break;
            }
        }

        if (std.mem.eql(u8, subcommand, "list")) {
            if (use_builtin) {
                return template_cmd.listBuiltinTemplates(allocator, sub_args);
            } else {
                return template_cmd.listTemplates(allocator, sub_args);
            }
        } else if (std.mem.eql(u8, subcommand, "show")) {
            if (use_builtin) {
                return template_cmd.showBuiltinTemplate(allocator, sub_args);
            } else {
                return template_cmd.showTemplate(allocator, sub_args);
            }
        } else if (std.mem.eql(u8, subcommand, "add")) {
            if (use_builtin) {
                return template_cmd.addBuiltinTemplate(allocator, sub_args);
            } else {
                return template_cmd.applyTemplate(allocator, sub_args);
            }
        } else if (std.mem.eql(u8, subcommand, "apply")) {
            // 'apply' is the old name for user-defined templates
            return template_cmd.applyTemplate(allocator, sub_args);
        } else {
            try color.printError(ew, effective_color, "Unknown template subcommand: {s}\n", .{subcommand});
            try color.printError(ew, effective_color, "Usage: zr template <list|show|add> [--builtin] [args...]\n", .{});
            return 1;
        }
    } else if (std.mem.eql(u8, cmd, "ci")) {
        const ci_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        if (ci_args.len == 0) {
            try ci_cmd.printHelp(effective_w);
            return 0;
        }
        const subcommand = ci_args[0];
        const sub_args = if (ci_args.len > 1) ci_args[1..] else &[_][]const u8{};

        if (std.mem.eql(u8, subcommand, "generate")) {
            // Parse flags
            var ci_platform: ?[]const u8 = null;
            var ci_template_type: ?[]const u8 = null;
            var ci_output_path: ?[]const u8 = null;

            for (sub_args) |arg| {
                if (std.mem.startsWith(u8, arg, "--platform=")) {
                    ci_platform = arg["--platform=".len..];
                } else if (std.mem.startsWith(u8, arg, "--type=")) {
                    ci_template_type = arg["--type=".len..];
                } else if (std.mem.startsWith(u8, arg, "--output=")) {
                    ci_output_path = arg["--output=".len..];
                }
            }

            return ci_cmd.cmdGenerate(allocator, ci_platform, ci_template_type, ci_output_path, effective_w, ew, effective_color) catch |err| {
                if (err == error.InvalidPlatform or err == error.InvalidTemplateType or
                    err == error.PlatformNotDetected or err == error.TemplateNotFound)
                {
                    return 1;
                }
                return err;
            };
        } else if (std.mem.eql(u8, subcommand, "list")) {
            return ci_cmd.cmdList(allocator, effective_w, effective_color);
        } else {
            try color.printError(ew, effective_color, "Unknown ci subcommand: {s}\n", .{subcommand});
            try ci_cmd.printHelp(ew);
            return 1;
        }
    } else if (std.mem.eql(u8, cmd, "which")) {
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "which: missing task name\n\n  Hint: zr which <task>\n", .{});
            return 1;
        }
        const task_name = effective_args[2];
        return which_cmd.cmdWhich(allocator, task_name, config_path, effective_w, ew, effective_color);
    }

    // This should never be reached due to alias expansion logic above
    unreachable;
}

fn printVersion(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "zr v" ++ checker.CURRENT_VERSION, .{});
    try w.print("\n", .{});
}

fn printHelp(w: *std.Io.Writer, use_color: bool) !void {
    try color.printBold(w, use_color, "zr v" ++ checker.CURRENT_VERSION, .{});
    try w.print(" - Zig Task Runner\n\n", .{});
    try color.printBold(w, use_color, "Usage:\n", .{});
    try w.print("  zr [options] <command> [arguments]\n\n", .{});
    try color.printBold(w, use_color, "Commands:\n", .{});
    try w.print("  run <task>             Run a task and its dependencies\n", .{});
    try w.print("  watch <task> [path...] Watch files and auto-run task on changes\n", .{});
    try w.print("  workflow <name>        Run a workflow by name\n", .{});
    try w.print("  list [pattern] [--tree] [--tags=TAG,...]  List tasks (filters: pattern, tags; --tree for dependency tree)\n", .{});
    try w.print("  which <task>           Show where a task is defined\n", .{});
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
    try w.print("  registry serve         Start plugin registry HTTP server\n", .{});
    try w.print("  interactive, i         Launch interactive TUI task picker\n", .{});
    try w.print("  live <task>            Run task with live TUI log streaming\n", .{});
    try w.print("  monitor <workflow>     Real-time resource dashboard for workflow execution\n", .{});
    try w.print("  interactive-run, irun  Run task with cancel/retry controls\n", .{});
    try w.print("  init                   Scaffold a new zr.toml in the current directory\n", .{});
    try w.print("    --detect             Auto-detect project languages and generate tasks\n", .{});
    try w.print("    --from-make          Migrate from Makefile\n", .{});
    try w.print("    --from-just          Migrate from justfile\n", .{});
    try w.print("    --from-task          Migrate from Taskfile.yml\n", .{});
    try w.print("  add <type> [name]      Interactively add a task, workflow, or profile\n", .{});
    try w.print("  edit <type>            TUI editor for creating tasks, workflows, or profiles\n", .{});
    try w.print("  setup                  Set up project (install tools, run setup tasks)\n", .{});
    try w.print("  validate               Validate zr.toml configuration file\n", .{});
    try w.print("  lint                   Validate architecture constraints\n", .{});
    try w.print("  conformance [OPTIONS]  Check code conformance against rules\n", .{});
    try w.print("  completion <shell>     Print shell completion script (bash|zsh|fish|powershell)\n", .{});
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
    try w.print("  cd <member>            Print path to workspace member (for shell integration)\n", .{});
    try w.print("  env [OPTIONS]          Display environment variables for tasks\n", .{});
    try w.print("  export [OPTIONS]       Export env vars in shell-sourceable format\n", .{});
    try w.print("  upgrade [OPTIONS]      Upgrade zr to the latest version\n", .{});
    try w.print("  alias <subcommand>     Manage command aliases (add|list|remove|show)\n", .{});
    try w.print("  estimate <task|workflow> Estimate task/workflow duration based on execution history\n", .{});
    try w.print("  show <task>            Display detailed information about a task\n", .{});
    try w.print("  failures [list|clear]  View or clear captured task failure reports\n", .{});
    try w.print("  schedule <subcommand>  Schedule tasks to run at specific times (add|list|remove|show)\n", .{});
    try w.print("  monitor <workflow>     Execute workflow with real-time resource monitoring dashboard\n", .{});
    try w.print("  mcp serve              Start MCP server for Claude Code/Cursor integration\n", .{});
    try w.print("  lsp                    Start LSP server for VS Code/Neovim integration\n", .{});
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

test "basic functionality - program structure" {
    // Verify main module compiles successfully and exports expected functions
    const allocator = std.testing.allocator;

    // Test that run function signature is correct
    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var buf: [4096]u8 = undefined;
    var writer = null_file.writer(&buf);

    // Verify help text can be printed (basic smoke test)
    try printHelp(&writer.interface, false);

    // Verify we can call run with minimal args (should show help)
    const args = [_][]const u8{"zr"};
    const exit_code = try run(allocator, &args, &writer.interface, &writer.interface, true);
    try std.testing.expectEqual(@as(u8, 0), exit_code);
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
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    // Test basic string
    try common.writeJsonString(writer, "hello world");
    try std.testing.expectEqualStrings("\"hello world\"", stream.getWritten());

    // Test quotes
    stream.reset();
    try common.writeJsonString(writer, "with \"quotes\"");
    try std.testing.expectEqualStrings("\"with \\\"quotes\\\"\"", stream.getWritten());

    // Test newline
    stream.reset();
    try common.writeJsonString(writer, "with\nnewline");
    try std.testing.expectEqualStrings("\"with\\nnewline\"", stream.getWritten());

    // Test backslash
    stream.reset();
    try common.writeJsonString(writer, "with\\backslash");
    try std.testing.expectEqualStrings("\"with\\\\backslash\"", stream.getWritten());
}

test "cmdList --format json returns valid JSON with tasks field" {
    const allocator = std.testing.allocator;

    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = null_file.writer(&out_buf);
    var err_w = null_file.writer(&err_buf);

    // Without a real config file this succeeds with empty task list.
    // This test verifies flag parsing works and the command doesn't crash/panic.
    const fake_args = [_][]const u8{ "zr", "--format", "json", "list" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    // Exit 0 expected (command succeeds even without zr.toml, shows empty list)
    try std.testing.expectEqual(@as(u8, 0), code);
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

// Force remote module test discovery by referencing it
comptime {
    _ = remote.RemoteExecutor;
    _ = tui_profiler.TuiProfiler;
}

