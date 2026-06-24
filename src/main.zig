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
const notification = @import("exec/notification.zig");
const timeline = @import("exec/timeline.zig");
const replay = @import("exec/replay.zig");
const checkpoint = @import("exec/checkpoint.zig");
const output_capture = @import("exec/output_capture.zig");
const retry_strategy = @import("exec/retry_strategy.zig");
const color = @import("output/color.zig");
const progress = @import("output/progress.zig");
const monitor = @import("output/monitor.zig");
const filter_mod = @import("output/filter.zig");
const history = @import("history/store.zig");
const watcher = @import("watch/watcher.zig");
const debounce = @import("watch/debounce.zig");
const livereload = @import("watch/livereload.zig");
const cache_key = @import("exec/cache_key.zig");
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
const help_cmd = @import("cli/help.zig");
const tui = @import("cli/tui.zig");
const task_picker = @import("cli/task_picker.zig");
const task_selector = @import("cli/task_selector.zig");
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
const secrets_cmd = @import("cli/secrets.zig");
const export_cmd = @import("cli/export.zig");
const explain_cmd = @import("cli/explain.zig");
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
const artifacts_cmd = @import("cli/artifacts.zig");
const deps_cmd = @import("cli/deps.zig");
const tags_cmd = @import("cli/tags.zig");
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
const toolchain_version = @import("toolchain/version.zig");
const constraints_mod = @import("config/constraints.zig");
const constraint_mod = @import("config/constraint.zig");
const lock_mod = @import("config/lock.zig");
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
    _ = constraint_mod;
    _ = lock_mod;
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
    _ = debounce;
    _ = livereload;
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
    _ = explain_cmd;
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
    .{ .name = "force", .type = .bool, .help = "Force task execution, ignoring up-to-date checks" },
    .{ .name = "no-color", .type = .bool, .help = "Disable color output" },
    .{ .name = "quiet", .short = 'q', .type = .bool, .help = "Suppress non-error output" },
    .{ .name = "verbose", .short = 'v', .type = .bool, .help = "Verbose output" },
    .{ .name = "silent", .short = 's', .type = .bool, .help = "Suppress task output unless task fails (overrides task-level silent)" },
    .{ .name = "format", .short = 'f', .type = .string, .default = "text", .help = "Output format: text or json" },
    .{ .name = "jobs", .short = 'j', .type = .int, .help = "Max parallel tasks (default: CPU count)" },
    .{ .name = "config", .type = .string, .help = "Config file path" },
    .{ .name = "monitor", .short = 'm', .type = .bool, .help = "Display live resource usage during execution" },
    .{ .name = "affected", .type = .string, .help = "Run only affected workspace members" },
    .{ .name = "show-env", .type = .bool, .help = "Display resolved environment variables for the task" },
    .{ .name = "show-outputs", .type = .bool, .help = "Display captured task outputs (share_output=true) after execution" },
    .{ .name = "grep", .type = .string, .help = "Filter output lines matching regex pattern" },
    .{ .name = "grep-v", .type = .string, .help = "Filter output lines NOT matching regex pattern (inverted match)" },
    .{ .name = "highlight", .type = .string, .help = "Highlight matches in output (shows all lines with pattern highlighted)" },
    .{ .name = "context", .short = 'C', .type = .int, .help = "Show N lines before/after grep matches (like grep -C)" },
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
    if (std.mem.eql(u8, long_name, "--grep")) return "--grep: missing regex pattern\n\n  Hint: zr --grep 'error|warning' run <task>";
    if (std.mem.eql(u8, long_name, "--grep-v")) return "--grep-v: missing regex pattern\n\n  Hint: zr --grep-v 'verbose' run <task>";
    if (std.mem.eql(u8, long_name, "--highlight")) return "--highlight: missing regex pattern\n\n  Hint: zr --highlight 'TODO|FIXME' run <task>";
    if (std.mem.eql(u8, long_name, "--context")) return "--context: missing line count\n\n  Hint: zr --grep 'ERROR' --context 3 run <task>";
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
            var empty_params = std.StringHashMap([]const u8).init(allocator);
            defer empty_params.deinit();
            var empty_cli_env = std.StringHashMap([]const u8).init(allocator);
            defer empty_cli_env.deinit();
            return run_cmd.cmdRun(allocator, "default", null, false, false, 0, config_path, false, false, w, ew, use_color, null, .{}, false, false, empty_params, &.{}, false, false, false, std.StringHashMap([]const u8).init(allocator), false, false, empty_cli_env, &.{});
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
            var empty_params2 = std.StringHashMap([]const u8).init(allocator);
            defer empty_params2.deinit();
            var empty_cli_env2 = std.StringHashMap([]const u8).init(allocator);
            defer empty_cli_env2.deinit();
            return run_cmd.cmdRun(allocator, single_task.key_ptr.*, null, false, false, 0, config_path, false, false, w, ew, use_color, null, .{}, false, false, empty_params2, &.{}, false, false, false, std.StringHashMap([]const u8).init(allocator), false, false, empty_cli_env2, &.{});
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
                var empty_params = std.StringHashMap([]const u8).init(allocator);
                defer empty_params.deinit();
                var empty_cli_env3 = std.StringHashMap([]const u8).init(allocator);
                defer empty_cli_env3.deinit();
                return run_cmd.cmdRun(allocator, picker_result.name, null, false, false, 0, config_path, false, false, w, ew, use_color, null, .{}, false, false, empty_params, &.{}, false, false, false, std.StringHashMap([]const u8).init(allocator), false, false, empty_cli_env3, &.{});
            } else {
                return run_cmd.cmdWorkflow(allocator, picker_result.name, null, false, 0, config_path, false, w, ew, use_color, .{}, false, &.{});
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
                    if (i + 1 < args.len) {
                        const value = args[i + 1];
                        // --format is a global flag but subcommands (bench, etc.) have their
                        // own extended format support (csv, xml, ...). Only consume it globally
                        // when the value is a known global format; otherwise let the subcommand handle it.
                        if (std.mem.eql(u8, flag_info.long_name, "--format") and
                            !std.mem.eql(u8, value, "text") and
                            !std.mem.eql(u8, value, "json"))
                        {
                            try remaining_args.append(allocator, arg);
                            try remaining_args.append(allocator, value);
                            i += 1;
                        } else {
                            // Emit long form for sailor (normalize short to long)
                            try global_flag_tokens.append(allocator, flag_info.long_name);
                            try global_flag_tokens.append(allocator, value);
                            i += 1;
                        }
                    } else {
                        // Missing value — use custom error messages
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
    const force_run = flag_parser.getBool("force", false);
    const no_color = flag_parser.getBool("no-color", false);
    const quiet = flag_parser.getBool("quiet", false);
    const verbose = flag_parser.getBool("verbose", false);
    const silent = flag_parser.getBool("silent", false);
    const enable_monitor = flag_parser.getBool("monitor", false);
    const show_env = flag_parser.getBool("show-env", false);
    const show_outputs = flag_parser.getBool("show-outputs", false);
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

    // Output filtering flags
    const filter_options = filter_mod.FilterOptions{
        .grep_pattern = if (flag_parser.get("grep")) |v| (v.asString() catch null) else null,
        .grep_v_pattern = if (flag_parser.get("grep-v")) |v| (v.asString() catch null) else null,
        .highlight_pattern = if (flag_parser.get("highlight")) |v| (v.asString() catch null) else null,
        .context_lines = if (flag_parser.get("context")) |v| blk: {
            const ctx_val = v.asInt() catch 0;
            if (ctx_val < 0 or ctx_val > 100) {
                try color.printError(ew, use_color,
                    "--context: value must be between 0 and 100\n\n  Hint: zr --grep 'ERROR' --context 3 run <task>\n", .{});
                return 1;
            }
            break :blk @intCast(ctx_val);
        } else 0,
    };

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
        "estimate",   "show",       "schedule",   "secrets",    "mcp",
        "explain",    "lsp",        "add",        "edit",       "failures",
        "template",   "which",      "ci",         "deps",       "artifacts",
        "tags",
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
        return run_cmd.cmdWorkflow(allocator, workflow_name, profile_name, dry_run, max_jobs, config_path, false, effective_w, ew, effective_color, filter_options, silent, &.{});
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
        var empty_params = std.StringHashMap([]const u8).init(allocator);
        defer empty_params.deinit();
        var empty_cli_env4 = std.StringHashMap([]const u8).init(allocator);
        defer empty_cli_env4.deinit();
        return run_cmd.cmdRun(allocator, task_name, profile_name, dry_run, force_run, max_jobs, config_path, json_output, enable_monitor, effective_w, ew, effective_color, null, filter_options, silent, show_env, empty_params, &.{}, false, false, false, std.StringHashMap([]const u8).init(allocator), false, false, empty_cli_env4, &.{});
    }

    if (std.mem.eql(u8, cmd, "run")) {
        if (effective_args.len >= 3 and (std.mem.eql(u8, effective_args[2], "--help") or std.mem.eql(u8, effective_args[2], "-h"))) {
            try color.printInfo(effective_w, effective_color,
                "Usage: zr run [TASK|PATTERN] [OPTIONS] [PARAMS...]\n\n" ++
                "Run a task and all its dependencies in topological order.\n\n" ++
                "ARGUMENTS:\n" ++
                "  <task>                Task name, glob pattern, or comma-separated list to run multiple\n" ++
                "  [key=value...]        Named task parameters\n" ++
                "  [value...]            Positional task parameters (in declaration order)\n\n" ++
                "TASK OPTIONS:\n" ++
                "  --tag=TAG             Filter tasks by tag (repeatable, AND logic)\n" ++
                "  --exclude-tag=TAG     Exclude tasks with tag (repeatable)\n" ++
                "  --dir=PATH            Filter tasks by working directory prefix\n" ++
                "  --skip=TASK           Skip specific tasks (repeatable, comma-separated)\n" ++
                "  --only                Run only this task without its dependencies\n" ++
                "  --explain             Show execution plan without running\n" ++
                "  --notify              Enable desktop notifications for all tasks\n" ++
                "  --fail-fast           Stop on first task failure (default: continue)\n" ++
                "  --param key=value     Set a named task parameter\n" ++
                "  --env KEY=VALUE       Inject environment variable (repeatable, overrides task env)\n" ++
                "  --input KEY=VALUE     Provide answer for input_prompt (repeatable)\n\n" ++
                "GLOBAL OPTIONS:\n" ++
                "  --dry-run, -n         Preview what would run without executing\n" ++
                "  --jobs, -j <N>        Max parallel tasks (default: CPU count)\n" ++
                "  --profile, -p NAME    Activate a named profile\n" ++
                "  --force               Force re-run even if task outputs are up-to-date\n" ++
                "  --show-env            Show effective environment variables\n" ++
                "  --show-outputs        Show captured task outputs (share_output=true) after execution\n" ++
                "  --monitor, -m         Display live resource usage during execution\n" ++
                "  --quiet, -q           Suppress non-error output\n" ++
                "  --verbose, -v         Verbose output\n" ++
                "  -h, --help            Show this help\n\n" ++
                "EXAMPLES:\n" ++
                "  zr run build                         # Run build task with all its dependencies\n" ++
                "  zr run test --only                   # Run test without running its dependencies\n" ++
                "  zr run build --dry-run               # Preview what would run without executing\n" ++
                "  zr run --tag=backend                 # Run all tasks tagged 'backend'\n" ++
                "  zr run deploy --skip=test,lint       # Deploy but skip test and lint tasks\n" ++
                "  zr run build --jobs=4                # Limit parallel execution to 4 jobs\n" ++
                "  zr run deploy env=production         # Pass 'env=production' as a task parameter\n" ++
                "  zr run test --env DATABASE=test      # Inject env var (override task config)\n" ++
                "  zr run deploy --env KEY=val --env SECRET=xyz  # Multiple env vars\n" ++
                "  zr run build,test,lint               # Run three tasks in sequence\n" ++
                "  zr run build,test --fail-fast        # Stop on first failure\n",
                .{},
            );
            return 0;
        }
        // Check for --explain flag early (before task name is required)
        var explain_mode = false;
        for (effective_args[2..]) |arg| {
            if (std.mem.eql(u8, arg, "--explain")) {
                explain_mode = true;
                break;
            }
        }

        if (effective_args.len < 3 or (effective_args.len == 3 and explain_mode)) {
            // No task name provided — launch interactive picker (unless --explain is only flag)
            if (explain_mode and effective_args.len == 3) {
                // `zr run --explain` with no task name
                try color.printError(ew, effective_color, "run: --explain requires a task name\n\n  Hint: zr run <task-name> --explain\n", .{});
                return 1;
            }
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
                // Picker mode doesn't support params (empty map)
                var empty_params = std.StringHashMap([]const u8).init(allocator);
                defer empty_params.deinit();
                var empty_cli_env5 = std.StringHashMap([]const u8).init(allocator);
                defer empty_cli_env5.deinit();
                return run_cmd.cmdRun(allocator, picker_result.name, profile_name, dry_run, force_run, max_jobs, config_path, json_output, enable_monitor, effective_w, ew, effective_color, null, filter_options, silent, show_env, empty_params, &.{}, false, false, false, std.StringHashMap([]const u8).init(allocator), false, false, empty_cli_env5, &.{});
            } else {
                // Workflow selected — delegate to workflow command
                config.deinit();
                return run_cmd.cmdWorkflow(allocator, picker_result.name, profile_name, dry_run, max_jobs, config_path, false, effective_w, ew, effective_color, filter_options, silent, &.{});
            }
        }
        // Support `zr run --only <task>` and `zr run --explain <task>` in addition to `zr run <task> --only`
        // Also support `zr run --tag=<tag>` (tag-filter mode without explicit task name → treat as "*")
        var only_mode_pre = false;
        var task_name_idx: usize = 2;
        var filter_only_mode = false; // true when first arg is a flag (tag/dir filter without explicit task)
        if (std.mem.eql(u8, effective_args[2], "--only")) {
            if (effective_args.len < 4) {
                try color.printError(ew, effective_color, "run: --only requires a task name\n\n  Hint: zr run <task-name> --only\n", .{});
                return 1;
            }
            only_mode_pre = true;
            task_name_idx = 3;
        } else if (std.mem.eql(u8, effective_args[2], "--explain")) {
            if (effective_args.len < 4) {
                try color.printError(ew, effective_color, "run: --explain requires a task name\n\n  Hint: zr run <task-name> --explain\n", .{});
                return 1;
            }
            task_name_idx = 3;
        } else if (std.mem.startsWith(u8, effective_args[2], "--tag") or
            std.mem.startsWith(u8, effective_args[2], "--exclude-tag") or
            std.mem.startsWith(u8, effective_args[2], "--dir="))
        {
            // Tag/dir filter-only mode: no explicit task name provided.
            // `zr run --tag=backend` is equivalent to `zr run "*" --tag=backend`
            filter_only_mode = true;
        }
        const task_name = if (filter_only_mode) "*" else effective_args[task_name_idx];

        // Parse filtering flags (v1.77.0 — Enhanced Task Filtering)
        var include_tags = std.ArrayList([]const u8){};
        defer {
            for (include_tags.items) |tag| allocator.free(tag);
            include_tags.deinit(allocator);
        }
        var exclude_tags_list = std.ArrayList([]const u8){};
        defer {
            for (exclude_tags_list.items) |tag| allocator.free(tag);
            exclude_tags_list.deinit(allocator);
        }
        var run_dir_filter: ?[]const u8 = null;
        var fail_fast = false;
        var notify_override = false;

        // Parse --skip flags (v1.83.0)
        var skip_tasks_list = std.ArrayList([]const u8){};
        defer {
            for (skip_tasks_list.items) |task| allocator.free(task);
            skip_tasks_list.deinit(allocator);
        }

        // Parse --only flag (v1.85.0); initialized from pre-scan if `zr run --only <task>` form
        var only_mode: bool = only_mode_pre;

        // Parse runtime task parameters (v1.75.0)
        // Supports 3 syntaxes:
        //   1. Positional: zr run task Alice London → maps to params in declaration order
        //   2. Named: zr run task name=Alice city=London
        //   3. --param flag: zr run task --param name=Alice --param city=London
        var runtime_params = std.StringHashMap([]const u8).init(allocator);
        defer {
            var _rp_it = runtime_params.iterator();
            while (_rp_it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            runtime_params.deinit();
        }

        // v1.88.0: input_prompt support
        var cli_inputs = std.StringHashMap([]const u8).init(allocator);
        defer {
            var _ci_it = cli_inputs.iterator();
            while (_ci_it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            cli_inputs.deinit();
        }
        // v1.102.0: CLI environment variables (--env KEY=VALUE)
        var cli_env = std.StringHashMap([]const u8).init(allocator);
        defer {
            var _ce_it = cli_env.iterator();
            while (_ce_it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            cli_env.deinit();
        }
        // v1.102.0: Runtime tags (--add-tag TAG)
        var runtime_tags = std.ArrayList([]const u8){};
        defer {
            for (runtime_tags.items) |t| allocator.free(t);
            runtime_tags.deinit(allocator);
        }
        var non_interactive: bool = false;
        var yes_confirm: bool = false;

        var positional_index: usize = 0;
        var i: usize = if (filter_only_mode) @as(usize, 2) else @as(usize, 3);
        while (i < effective_args.len) : (i += 1) {
            const arg = effective_args[i];

            if (std.mem.eql(u8, arg, "--tag")) {
                // --tag <tagname> syntax (repeatable)
                i += 1;
                if (i >= effective_args.len) {
                    try color.printError(ew, effective_color, "run: --tag requires tag name argument\n", .{});
                    return 1;
                }
                try include_tags.append(allocator, try allocator.dupe(u8, effective_args[i]));
            } else if (std.mem.startsWith(u8, arg, "--tag=")) {
                // --tag=tagname syntax (repeatable)
                const tag = arg["--tag=".len..];
                try include_tags.append(allocator, try allocator.dupe(u8, tag));
            } else if (std.mem.eql(u8, arg, "--exclude-tag")) {
                // --exclude-tag <tagname> syntax (repeatable)
                i += 1;
                if (i >= effective_args.len) {
                    try color.printError(ew, effective_color, "run: --exclude-tag requires tag name argument\n", .{});
                    return 1;
                }
                try exclude_tags_list.append(allocator, try allocator.dupe(u8, effective_args[i]));
            } else if (std.mem.startsWith(u8, arg, "--exclude-tag=")) {
                // --exclude-tag=tagname syntax (repeatable)
                const tag = arg["--exclude-tag=".len..];
                try exclude_tags_list.append(allocator, try allocator.dupe(u8, tag));
            } else if (std.mem.startsWith(u8, arg, "--dir=")) {
                // --dir=<path> syntax: filter tasks by cwd prefix
                run_dir_filter = arg["--dir=".len..];
            } else if (std.mem.eql(u8, arg, "--param")) {
                // --param key=value syntax
                i += 1;
                if (i >= effective_args.len) {
                    try color.printError(ew, effective_color, "run: --param requires key=value argument\n", .{});
                    return 1;
                }
                const kv = effective_args[i];
                if (std.mem.indexOf(u8, kv, "=")) |eq_pos| {
                    const key = kv[0..eq_pos];
                    const value = kv[eq_pos + 1 ..];
                    try runtime_params.put(try allocator.dupe(u8, key), try allocator.dupe(u8, value));
                } else {
                    try color.printError(ew, effective_color, "run: --param argument must be key=value format, got '{s}'\n", .{kv});
                    return 1;
                }
            } else if (std.mem.eql(u8, arg, "--input")) {
                // v1.88.0: --input key=value syntax (for input_prompt values)
                i += 1;
                if (i >= effective_args.len) {
                    try color.printError(ew, effective_color, "run: --input requires key=value argument\n", .{});
                    return 1;
                }
                const kv = effective_args[i];
                if (std.mem.indexOf(u8, kv, "=")) |eq_pos| {
                    const key = kv[0..eq_pos];
                    const value = kv[eq_pos + 1 ..];
                    try cli_inputs.put(try allocator.dupe(u8, key), try allocator.dupe(u8, value));
                } else {
                    try color.printError(ew, effective_color, "run: --input argument must be key=value format, got '{s}'\n", .{kv});
                    return 1;
                }
            } else if (std.mem.eql(u8, arg, "--env")) {
                // v1.102.0: --env key=value syntax (repeatable, for environment variable injection)
                i += 1;
                if (i >= effective_args.len) {
                    try color.printError(ew, effective_color, "run: --env requires key=value argument\n", .{});
                    return 1;
                }
                const kv = effective_args[i];
                if (std.mem.indexOf(u8, kv, "=")) |eq_pos| {
                    const key = kv[0..eq_pos];
                    const value = kv[eq_pos + 1 ..];
                    try cli_env.put(try allocator.dupe(u8, key), try allocator.dupe(u8, value));
                } else {
                    try color.printError(ew, effective_color, "run: --env argument must be key=value format, got '{s}'\n", .{kv});
                    return 1;
                }
            } else if (std.mem.eql(u8, arg, "--add-tag")) {
                // v1.102.0: --add-tag TAG syntax (repeatable, for runtime tag injection)
                i += 1;
                if (i >= effective_args.len) {
                    try color.printError(ew, effective_color, "run: --add-tag requires tag name argument\n", .{});
                    return 1;
                }
                try runtime_tags.append(allocator, try allocator.dupe(u8, effective_args[i]));
            } else if (std.mem.eql(u8, arg, "--non-interactive")) {
                // v1.88.0: --non-interactive mode (use defaults instead of prompting)
                non_interactive = true;
            } else if (std.mem.eql(u8, arg, "--yes") or std.mem.eql(u8, arg, "--no-confirm")) {
                // v1.90.0: skip all confirmation prompts, auto-answer yes
                yes_confirm = true;
            } else if (std.mem.eql(u8, arg, "--skip")) {
                // --skip <tasks> syntax (repeatable, comma-separated)
                i += 1;
                if (i >= effective_args.len) {
                    try color.printError(ew, effective_color, "run: --skip requires task name argument\n", .{});
                    return 1;
                }
                const skip_arg = effective_args[i];
                // Split by comma and add each task to skip_tasks_list
                var it = std.mem.splitSequence(u8, skip_arg, ",");
                while (it.next()) |task| {
                    const trimmed = std.mem.trim(u8, task, " \t");
                    if (trimmed.len > 0) {
                        try skip_tasks_list.append(allocator, try allocator.dupe(u8, trimmed));
                    }
                }
            } else if (std.mem.startsWith(u8, arg, "--skip=")) {
                // --skip=<tasks> syntax (repeatable, comma-separated)
                const skip_arg = arg["--skip=".len..];
                // Split by comma and add each task to skip_tasks_list
                var it = std.mem.splitSequence(u8, skip_arg, ",");
                while (it.next()) |task| {
                    const trimmed = std.mem.trim(u8, task, " \t");
                    if (trimmed.len > 0) {
                        try skip_tasks_list.append(allocator, try allocator.dupe(u8, trimmed));
                    }
                }
            } else if (std.mem.eql(u8, arg, "--fail-fast")) {
                fail_fast = true;
            } else if (std.mem.eql(u8, arg, "--notify")) {
                notify_override = true;
            } else if (std.mem.eql(u8, arg, "--only")) {
                only_mode = true;
            } else if (std.mem.eql(u8, arg, "--explain")) {
                // --explain flag is handled separately below
                continue;
            } else if (std.mem.indexOf(u8, arg, "=")) |eq_pos| {
                // Named key=value syntax
                const key = arg[0..eq_pos];
                const value = arg[eq_pos + 1 ..];
                try runtime_params.put(try allocator.dupe(u8, key), try allocator.dupe(u8, value));
            } else {
                // Positional argument — store with special marker for later resolution
                const pos_key = try std.fmt.allocPrint(allocator, "__positional_{d}", .{positional_index});
                try runtime_params.put(pos_key, try allocator.dupe(u8, arg));
                positional_index += 1;
            }
        }

        // If --explain mode, dispatch to cmdExplain instead of cmdRun
        if (explain_mode) {
            const explain_args = [_][]const u8{task_name};
            return explain_cmd.cmdExplain(allocator, &explain_args, config_path, effective_w, ew, effective_color);
        }

        // Check if task filtering is requested (glob pattern, tags, or dir)
        const has_glob_pattern = std.mem.indexOfAny(u8, task_name, "*?") != null;
        const has_filters = include_tags.items.len > 0 or exclude_tags_list.items.len > 0 or run_dir_filter != null;

        // Group wildcard ("build.*") — route to cmdRun for single-scheduler execution.
        // Without this, the generic glob path expands it into individual cmdRun calls,
        // causing shared dependencies (e.g. build.compile) to run once per selected task.
        if (std.mem.endsWith(u8, task_name, ".*") and !has_filters) {
            return run_cmd.cmdRun(allocator, task_name, profile_name, dry_run, force_run, max_jobs, config_path, json_output, enable_monitor, effective_w, ew, effective_color, null, filter_options, silent, show_env, runtime_params, skip_tasks_list.items, notify_override, only_mode, show_outputs, cli_inputs, non_interactive, yes_confirm, cli_env, runtime_tags.items);
        }

        // Comma-separated multi-task run: "zr run build,test,lint" (v1.101.0)
        // Runs each named task in left-to-right order; respects --fail-fast.
        const has_comma = std.mem.indexOf(u8, task_name, ",") != null;
        if (has_comma and !has_glob_pattern and !has_filters) {
            var task_list = std.ArrayList([]const u8){};
            defer task_list.deinit(allocator);

            var split_it = std.mem.splitSequence(u8, task_name, ",");
            while (split_it.next()) |part| {
                const trimmed = std.mem.trim(u8, part, " \t");
                if (trimmed.len > 0) {
                    try task_list.append(allocator, trimmed);
                }
            }

            if (task_list.items.len == 0) {
                try color.printError(ew, effective_color, "run: No valid task names in comma-separated list\n\n  Hint: zr run build,test,lint\n", .{});
                return 1;
            }

            if (task_list.items.len > 1) {
                try color.printBold(effective_w, effective_color, "Running {d} task(s):\n", .{task_list.items.len});
                for (task_list.items) |name| {
                    try effective_w.print("  - {s}\n", .{name});
                }
                try effective_w.print("\n", .{});
            }

            var all_success = true;
            for (task_list.items) |selected_task_name| {
                const exit_code = try run_cmd.cmdRun(
                    allocator,
                    selected_task_name,
                    profile_name,
                    dry_run,
                    force_run,
                    max_jobs,
                    config_path,
                    json_output,
                    enable_monitor,
                    effective_w,
                    ew,
                    effective_color,
                    null,
                    filter_options,
                    silent,
                    show_env,
                    runtime_params,
                    skip_tasks_list.items,
                    notify_override,
                    only_mode,
                    show_outputs,
                    cli_inputs,
                    non_interactive,
                    yes_confirm,
                    cli_env,
                    runtime_tags.items,
                );
                if (exit_code != 0) {
                    all_success = false;
                    if (fail_fast) {
                        try color.printError(ew, effective_color, "run: Task '{s}' failed — stopping (--fail-fast)\n", .{selected_task_name});
                        break;
                    }
                }
            }

            return if (all_success) @as(u8, 0) else @as(u8, 1);
        }

        if (has_glob_pattern or has_filters) {
            // Task filtering mode: load config and select matching tasks
            var config = (try common.loadConfig(allocator, config_path, profile_name, ew, effective_color)) orelse return 1;
            defer config.deinit();

            const filter = task_selector.TaskFilter{
                .pattern = if (has_glob_pattern) task_name else null,
                .include_tags = include_tags.items,
                .exclude_tags = exclude_tags_list.items,
                .dir_filter = run_dir_filter,
            };

            var selection = try task_selector.selectTasks(allocator, config.tasks, filter);
            defer selection.deinit();

            if (selection.task_names.len == 0) {
                // No tasks matched the filter
                try color.printError(ew, effective_color, "run: No tasks match the specified filters\n\n", .{});
                if (has_glob_pattern) {
                    try ew.print("  Pattern: {s}\n", .{task_name});
                }
                if (include_tags.items.len > 0) {
                    try ew.print("  Include tags: ", .{});
                    for (include_tags.items, 0..) |tag, idx| {
                        if (idx > 0) try ew.print(", ", .{});
                        try ew.print("{s}", .{tag});
                    }
                    try ew.print("\n", .{});
                }
                if (exclude_tags_list.items.len > 0) {
                    try ew.print("  Exclude tags: ", .{});
                    for (exclude_tags_list.items, 0..) |tag, idx| {
                        if (idx > 0) try ew.print(", ", .{});
                        try ew.print("{s}", .{tag});
                    }
                    try ew.print("\n", .{});
                }
                try ew.print("\n  Hint: Run 'zr list' to see available tasks and their tags\n", .{});
                return 1;
            }

            // Show selected tasks if multiple matches or dry-run
            if (selection.task_names.len > 1 or dry_run) {
                try color.printBold(effective_w, effective_color, "Selected {d} task(s):\n", .{selection.task_names.len});
                for (selection.task_names) |name| {
                    try effective_w.print("  - {s}\n", .{name});
                }
                try effective_w.print("\n", .{});
            }

            // Run each selected task
            var all_success = true;
            for (selection.task_names) |selected_task_name| {
                // Note: runtime_params apply to all selected tasks
                const exit_code = try run_cmd.cmdRun(
                    allocator,
                    selected_task_name,
                    profile_name,
                    dry_run,
                    force_run,
                    max_jobs,
                    config_path,
                    json_output,
                    enable_monitor,
                    effective_w,
                    ew,
                    effective_color,
                    null,
                    filter_options,
                    silent,
                    show_env,
                    runtime_params,
                    skip_tasks_list.items,
                    notify_override,
                    only_mode,
                    show_outputs,
                    cli_inputs,
                    non_interactive,
                    yes_confirm,
                    cli_env,
                    runtime_tags.items,
                );
                if (exit_code != 0) {
                    all_success = false;
                    if (fail_fast) {
                        try color.printError(ew, effective_color, "run: Task '{s}' failed — stopping (--fail-fast)\n", .{selected_task_name});
                        break;
                    }
                }
            }

            return if (all_success) @as(u8, 0) else @as(u8, 1);
        }

        // No filtering — run single task directly (existing behavior)
        return run_cmd.cmdRun(allocator, task_name, profile_name, dry_run, force_run, max_jobs, config_path, json_output, enable_monitor, effective_w, ew, effective_color, null, filter_options, silent, show_env, runtime_params, skip_tasks_list.items, notify_override, only_mode, show_outputs, cli_inputs, non_interactive, yes_confirm, cli_env, runtime_tags.items);
    } else if (std.mem.eql(u8, cmd, "watch")) {
        if (effective_args.len >= 3 and (std.mem.eql(u8, effective_args[2], "--help") or std.mem.eql(u8, effective_args[2], "-h"))) {
            try color.printInfo(effective_w, effective_color,
                "Usage: zr watch <TASK> [PATH...] [OPTIONS]\n\n" ++
                "Watch files for changes and automatically re-run a task.\n\n" ++
                "ARGUMENTS:\n" ++
                "  <task>                Task to run on file changes (required)\n" ++
                "  [path...]             Paths to watch for changes (default: \".\")\n\n" ++
                "GLOBAL OPTIONS:\n" ++
                "  --jobs, -j <N>        Max parallel tasks (default: CPU count)\n" ++
                "  --profile, -p NAME    Activate a named profile\n" ++
                "  --quiet, -q           Suppress non-error output\n" ++
                "  --verbose, -v         Verbose output\n" ++
                "  -h, --help            Show this help\n\n" ++
                "EXAMPLES:\n" ++
                "  zr watch build                  # Watch \".\" and re-run build on changes\n" ++
                "  zr watch test src/ tests/       # Watch specific directories\n" ++
                "  zr watch lint src/              # Watch src/ and re-run lint\n",
                .{},
            );
            return 0;
        }
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "watch: missing task name\n\n  Hint: zr watch <task-name> [path...]\n", .{});
            return 1;
        }
        const task_name = effective_args[2];
        const watch_paths: []const []const u8 = if (effective_args.len > 3) effective_args[3..] else &[_][]const u8{"."};
        return run_cmd.cmdWatch(allocator, task_name, watch_paths, profile_name, max_jobs, config_path, effective_w, ew, effective_color, filter_options, silent, &.{}, &.{});
    } else if (std.mem.eql(u8, cmd, "workflow")) {
        if (effective_args.len >= 3 and (std.mem.eql(u8, effective_args[2], "--help") or std.mem.eql(u8, effective_args[2], "-h"))) {
            try color.printInfo(effective_w, effective_color,
                "Usage: zr workflow <NAME> [OPTIONS]\n\n" ++
                "Run a named workflow defined in zr.toml.\n\n" ++
                "ARGUMENTS:\n" ++
                "  <name>                Workflow name to run (required)\n\n" ++
                "OPTIONS:\n" ++
                "  --matrix-show         Show matrix expansion steps before running\n\n" ++
                "GLOBAL OPTIONS:\n" ++
                "  --dry-run, -n         Preview what would run without executing\n" ++
                "  --jobs, -j <N>        Max parallel tasks (default: CPU count)\n" ++
                "  --profile, -p NAME    Activate a named profile\n" ++
                "  --quiet, -q           Suppress non-error output\n" ++
                "  --verbose, -v         Verbose output\n" ++
                "  -h, --help            Show this help\n\n" ++
                "EXAMPLES:\n" ++
                "  zr workflow deploy             # Run the deploy workflow\n" ++
                "  zr workflow build --dry-run    # Preview the build workflow\n" ++
                "  zr workflow release --matrix-show  # Show matrix expansion\n",
                .{},
            );
            return 0;
        }
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

        return run_cmd.cmdWorkflow(allocator, wf_name, profile_name, dry_run, max_jobs, config_path, matrix_show, effective_w, ew, effective_color, filter_options, silent, &.{});
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
        var show_status = false;
        var show_cache = false;
        var list_verbose = false;
        var sort_by: ?[]const u8 = null;
        var show_all = false;
        var group_filter: ?[]const u8 = null;
        var show_source = false;
        var show_last_run_tags = false;
        // Quick --help check before full arg parsing
        for (effective_args[2..]) |a| {
            if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
                try color.printInfo(effective_w, effective_color,
                    "Usage: zr list [OPTIONS] [PATTERN]\n\n" ++
                    "List all available tasks and workflows.\n\n" ++
                    "OPTIONS:\n" ++
                    "  --tree               Show dependency tree\n" ++
                    "  --sort=<key>         Sort by: name (default), freq, time, recent\n" ++
                    "  --group=<name>       Show only tasks in namespace group\n" ++
                    "  --group-by-tags      Group tasks by their tags\n" ++
                    "  --tags=<tags>        Filter tasks by tags (comma-separated)\n" ++
                    "  --exclude-tags=<t>   Exclude tasks with these tags\n" ++
                    "  --search=<text>      Full-text search in name, description, command\n" ++
                    "  --fuzzy              Fuzzy-match PATTERN against task names\n" ++
                    "  --recent[=N]         Show N most recently run tasks (default: 10)\n" ++
                    "  --frequent[=N]       Show N most frequently run tasks (default: 10)\n" ++
                    "  --slow[=MS]          Show tasks slower than threshold (default: 30s)\n" ++
                    "  --status             Show up-to-date status for each task\n" ++
                    "  --show-cache         Show cache status for each task\n" ++
                    "  --show-env           Show effective environment variables\n" ++
                    "  --source             Show source file for tasks from includes (v1.99.0)\n" ++
                    "  --last-run-tags      Show runtime tags (+tag) from most recent run per task\n" ++
                    "  --verbose            Show detailed task metadata\n" ++
                    "  --format json        Output as JSON\n" ++
                    "  --members            List workspace members only\n" ++
                    "  --all, -a            Show all tasks including internal ones\n" ++
                    "  -h, --help           Show this help\n",
                    .{},
                );
                return 0;
            }
        }
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
            } else if (std.mem.eql(u8, arg, "--status")) {
                show_status = true;
            } else if (std.mem.eql(u8, arg, "--show-cache")) {
                show_cache = true;
            } else if (std.mem.eql(u8, arg, "--verbose")) {
                list_verbose = true;
            } else if (std.mem.eql(u8, arg, "--all") or std.mem.eql(u8, arg, "-a")) {
                show_all = true;
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
            } else if (std.mem.startsWith(u8, arg, "--sort=")) {
                sort_by = arg["--sort=".len..];
            } else if (std.mem.eql(u8, arg, "--sort")) {
                if (i + 1 < effective_args.len) {
                    i += 1;
                    sort_by = effective_args[i];
                }
            } else if (std.mem.startsWith(u8, arg, "--group=")) {
                group_filter = arg["--group=".len..];
            } else if (std.mem.eql(u8, arg, "--group")) {
                if (i + 1 < effective_args.len) {
                    i += 1;
                    group_filter = effective_args[i];
                }
            } else if (std.mem.eql(u8, arg, "--source")) {
                show_source = true;
            } else if (std.mem.eql(u8, arg, "--last-run-tags")) {
                show_last_run_tags = true;
            } else if (!std.mem.startsWith(u8, arg, "--")) {
                // First non-flag argument is the filter pattern
                filter_pattern = arg;
            }
        }
        return list_cmd.cmdList(allocator, config_path, json_output, tree_mode, filter_pattern, filter_tags, exclude_tags, profiles_only, members_only, fuzzy_search, group_by_tags, recent_count, frequent_count, slow_threshold_ms, search_description, show_status, show_cache, show_env, list_verbose, sort_by, show_all, group_filter, show_source, show_last_run_tags, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "help")) {
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "help: missing task name\n\n  Usage: zr help <task-name>\n", .{});
            return 1;
        }
        const task_name = effective_args[2];
        var config = (try common.loadConfig(allocator, config_path, profile_name, ew, effective_color)) orelse return 1;
        defer config.deinit();
        try help_cmd.cmdHelp(&config, task_name, effective_color, effective_w, ew);
        return 0;
    } else if (std.mem.eql(u8, cmd, "man")) {
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "man: missing task name\n\n  Usage: zr man <task-name>\n", .{});
            return 1;
        }
        const task_name = effective_args[2];
        var config = (try common.loadConfig(allocator, config_path, profile_name, ew, effective_color)) orelse return 1;
        defer config.deinit();
        try help_cmd.cmdMan(allocator, &config, task_name, effective_w, ew);
        return 0;
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
                std.mem.startsWith(u8, arg, "--group=") or
                std.mem.startsWith(u8, arg, "--from=") or
                std.mem.startsWith(u8, arg, "--to=") or
                std.mem.startsWith(u8, arg, "--depth=") or
                std.mem.eql(u8, arg, "--cycles-only") or
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
        const history_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return run_cmd.cmdHistory(allocator, history_args, json_output, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "init")) {
        // Quick --help check before running init
        for (effective_args[2..]) |arg| {
            if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                try color.printInfo(effective_w, effective_color,
                    "Usage: zr init [OPTIONS]\n\n" ++
                    "Initialize a new zr.toml configuration file in the current directory.\n\n" ++
                    "OPTIONS:\n" ++
                    "  --detect              Auto-detect project type and generate tasks\n" ++
                    "  --from-npm            Migrate scripts from package.json\n" ++
                    "  --from-make           Migrate targets from Makefile\n" ++
                    "  --from-just           Migrate recipes from Justfile\n" ++
                    "  --from-task           Migrate tasks from Taskfile.yml\n" ++
                    "  --dry-run             Preview what would be generated without creating files\n" ++
                    "  -h, --help            Show this help\n\n" ++
                    "EXAMPLES:\n" ++
                    "  zr init                    # Create a minimal zr.toml\n" ++
                    "  zr init --detect           # Auto-detect project and generate tasks\n" ++
                    "  zr init --from-make        # Convert Makefile to zr.toml\n" ++
                    "  zr init --from-npm         # Convert package.json scripts to tasks\n" ++
                    "  zr init --dry-run          # Preview without creating files\n",
                    .{},
                );
                return 0;
            }
        }
        // Parse init options
        var detect_mode = false;
        var migrate_mode = init.MigrateMode.none;
        for (effective_args[2..]) |arg| {
            if (std.mem.eql(u8, arg, "--detect")) {
                detect_mode = true;
            } else if (std.mem.eql(u8, arg, "--from-npm")) {
                migrate_mode = .npm;
            } else if (std.mem.eql(u8, arg, "--from-make")) {
                migrate_mode = .makefile;
            } else if (std.mem.eql(u8, arg, "--from-just")) {
                migrate_mode = .justfile;
            } else if (std.mem.eql(u8, arg, "--from-task")) {
                migrate_mode = .taskfile;
            }
        }
        return init.cmdInit(allocator, std.fs.cwd(), detect_mode, migrate_mode, dry_run, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "validate")) {
        // Parse validate options
        var strict = false;
        var show_schema = false;
        var show_includes = false;
        for (effective_args[2..]) |arg| {
            if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                try color.printInfo(effective_w, effective_color,
                    "Usage: zr validate [OPTIONS]\n\n" ++
                    "Validate the zr.toml configuration file for syntax and schema errors.\n\n" ++
                    "OPTIONS:\n" ++
                    "  --strict              Treat warnings as errors\n" ++
                    "  --schema              Show the configuration schema\n" ++
                    "  --show-includes       Show include tree with file paths and task counts (v1.99.0)\n" ++
                    "  --config <path>       Config file path (default: zr.toml)\n" ++
                    "  -h, --help            Show this help\n\n" ++
                    "EXAMPLES:\n" ++
                    "  zr validate                     # Validate zr.toml in current directory\n" ++
                    "  zr validate --strict            # Fail on warnings too\n" ++
                    "  zr validate --config other.toml # Validate a specific file\n" ++
                    "  zr validate --show-includes     # Show include tree\n",
                    .{},
                );
                return 0;
            } else if (std.mem.eql(u8, arg, "--strict")) {
                strict = true;
            } else if (std.mem.eql(u8, arg, "--schema")) {
                show_schema = true;
            } else if (std.mem.eql(u8, arg, "--show-includes")) {
                show_includes = true;
            }
        }
        return validate_cmd.cmdValidate(allocator, config_path, .{
            .strict = strict,
            .show_schema = show_schema,
            .show_includes = show_includes,
        }, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "completion")) {
        // Check if --install flag is present
        var install_mode = false;
        var shell = if (effective_args.len >= 3) effective_args[2] else "";

        if (effective_args.len >= 3 and std.mem.eql(u8, effective_args[2], "--install")) {
            install_mode = true;
            shell = if (effective_args.len >= 4) effective_args[3] else "";
        }

        if (std.mem.eql(u8, shell, "--help") or std.mem.eql(u8, shell, "-h")) {
            try effective_w.writeAll("Usage: zr completion [--install] <shell>\n\n");
            try effective_w.writeAll("Generate or install shell completion scripts.\n\n");
            try effective_w.writeAll("Shells:\n");
            try effective_w.writeAll("  bash        Generate/install bash completion script\n");
            try effective_w.writeAll("  zsh         Generate/install zsh completion script\n");
            try effective_w.writeAll("  fish        Generate/install fish completion script\n");
            try effective_w.writeAll("  powershell  Generate PowerShell completion script\n\n");
            try effective_w.writeAll("Flags:\n");
            try effective_w.writeAll("  --install   Automatically install completion to shell config file\n\n");
            try effective_w.writeAll("Examples:\n");
            try effective_w.writeAll("  zr completion bash >> ~/.bashrc\n");
            try effective_w.writeAll("  zr completion --install bash\n");
            try effective_w.writeAll("  zr completion --install zsh\n");
            return 0;
        }

        if (install_mode) {
            return try completion.installCompletion(allocator, shell, effective_w, ew, effective_color);
        } else {
            return completion.cmdCompletion(shell, effective_w, ew, effective_color);
        }
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
    } else if (std.mem.eql(u8, cmd, "deps")) {
        deps_cmd.handle(allocator, effective_args, effective_w, ew) catch |err| switch (err) {
            error.UnsatisfiedConstraints, error.TaskNotFound, error.UnknownSubcommand, error.ConfigNotFound => return 1,
            else => return err,
        };
        return 0;
    } else if (std.mem.eql(u8, cmd, "plugin")) {
        const sub = if (effective_args.len >= 3) effective_args[2] else "";
        return plugin_cli.cmdPlugin(allocator, sub, effective_args, config_path, json_output, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "registry")) {
        try registry_cmd.cmdRegistry(allocator, effective_args, effective_color, effective_w, ew);
        return 0;
    } else if (std.mem.eql(u8, cmd, "interactive") or std.mem.eql(u8, cmd, "i")) {
        return tui.cmdInteractive(allocator, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "live")) {
        if (effective_args.len >= 3 and (std.mem.eql(u8, effective_args[2], "--help") or std.mem.eql(u8, effective_args[2], "-h"))) {
            try color.printInfo(effective_w, effective_color,
                "Usage: zr live <TASK...> [OPTIONS]\n\n" ++
                "Run tasks with live TUI log streaming.\n\n" ++
                "ARGUMENTS:\n" ++
                "  <task...>             One or more task names to run (required)\n\n" ++
                "GLOBAL OPTIONS:\n" ++
                "  --jobs, -j <N>        Max parallel tasks (default: CPU count)\n" ++
                "  --profile, -p NAME    Activate a named profile\n" ++
                "  -h, --help            Show this help\n\n" ++
                "EXAMPLES:\n" ++
                "  zr live build                   # Run build with live log streaming\n" ++
                "  zr live test lint               # Stream logs for test and lint in parallel\n",
                .{},
            );
            return 0;
        }
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "live: missing task name\n\n  Hint: zr live <task-name> [task-name...]\n", .{});
            return 1;
        }
        const task_names = effective_args[2..];
        return live_cmd.cmdLive(allocator, task_names, profile_name, max_jobs, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "monitor")) {
        if (effective_args.len >= 3 and (std.mem.eql(u8, effective_args[2], "--help") or std.mem.eql(u8, effective_args[2], "-h"))) {
            try color.printInfo(effective_w, effective_color,
                "Usage: zr monitor <WORKFLOW> [OPTIONS]\n\n" ++
                "Run a workflow with a real-time resource monitoring dashboard.\n\n" ++
                "ARGUMENTS:\n" ++
                "  <workflow>            Workflow name to monitor (required)\n\n" ++
                "GLOBAL OPTIONS:\n" ++
                "  --jobs, -j <N>        Max parallel tasks (default: CPU count)\n" ++
                "  --profile, -p NAME    Activate a named profile\n" ++
                "  -h, --help            Show this help\n\n" ++
                "EXAMPLES:\n" ++
                "  zr monitor deploy               # Monitor deploy workflow resource usage\n" ++
                "  zr monitor build                # Show CPU/memory during build workflow\n",
                .{},
            );
            return 0;
        }
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "monitor: missing workflow name\n\n  Hint: zr monitor <workflow-name>\n", .{});
            return 1;
        }
        const workflow_name = effective_args[2];
        return monitor_dashboard.cmdMonitor(allocator, workflow_name, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "interactive-run") or std.mem.eql(u8, cmd, "irun")) {
        if (effective_args.len >= 3 and (std.mem.eql(u8, effective_args[2], "--help") or std.mem.eql(u8, effective_args[2], "-h"))) {
            try color.printInfo(effective_w, effective_color,
                "Usage: zr irun <TASK> [OPTIONS]\n\n" ++
                "Run a task with interactive cancel/retry controls.\n\n" ++
                "ARGUMENTS:\n" ++
                "  <task>                Task name to run (required)\n\n" ++
                "GLOBAL OPTIONS:\n" ++
                "  --dry-run, -n         Preview what would run without executing\n" ++
                "  --jobs, -j <N>        Max parallel tasks (default: CPU count)\n" ++
                "  --profile, -p NAME    Activate a named profile\n" ++
                "  -h, --help            Show this help\n\n" ++
                "EXAMPLES:\n" ++
                "  zr irun build                   # Run build with interactive controls\n" ++
                "  zr irun deploy                  # Deploy with cancel/retry on failure\n",
                .{},
            );
            return 0;
        }
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
        return lint_cmd.run(allocator, lint_args, effective_w, ew);
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
        return publish_cmd.cmdPublish(allocator, publish_args, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "analytics")) {
        const analytics_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return analytics_cmd.cmdAnalytics(allocator, analytics_args, json_output, effective_w, ew);
    } else if (std.mem.eql(u8, cmd, "context")) {
        const context_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return context_cmd.cmdContext(allocator, context_args, effective_w, ew);
    } else if (std.mem.eql(u8, cmd, "secrets")) {
        // Secret management: zr secrets list|check (v1.98.0)
        const secrets_args = if (effective_args.len >= 2) effective_args[1..] else &[_][]const u8{};
        return try secrets_cmd.secretsCommand(allocator, secrets_args, effective_w, ew, config_path, effective_color);
    } else if (std.mem.eql(u8, cmd, "mcp")) {
        // MCP server: zr mcp serve
        if (effective_args.len < 3) {
            try color.printError(ew, effective_color, "mcp: missing subcommand\n\n  Hint: zr mcp serve\n", .{});
            return 1;
        }
        const subcmd = effective_args[2];
        if (std.mem.eql(u8, subcmd, "--help") or std.mem.eql(u8, subcmd, "-h")) {
            try color.printInfo(effective_w, effective_color,
                "Usage: zr mcp <SUBCOMMAND>\n\n" ++
                "MCP (Model Context Protocol) server for AI agent integration.\n\n" ++
                "SUBCOMMANDS:\n" ++
                "  serve                 Start MCP server (stdio transport for Claude/Cursor)\n\n" ++
                "GLOBAL OPTIONS:\n" ++
                "  -h, --help            Show this help\n\n" ++
                "EXAMPLES:\n" ++
                "  zr mcp serve                    # Start MCP server on stdio\n",
                .{},
            );
            return 0;
        }
        if (std.mem.eql(u8, subcmd, "serve")) {
            // Check for --help flag
            const mcp_args = if (effective_args.len >= 4) effective_args[3..] else &[_][]const u8{};
            for (mcp_args) |arg| {
                if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                    try color.printBold(effective_w, effective_color, "Usage: zr mcp serve [OPTIONS]\n\n", .{});
                    try effective_w.print("Start MCP (Model Context Protocol) server for AI integration.\n\n", .{});
                    try color.printBold(effective_w, effective_color, "DESCRIPTION:\n", .{});
                    try effective_w.print("  The MCP server enables AI assistants like Claude Code and Cursor to\n", .{});
                    try effective_w.print("  interact with your project by exposing zr commands as MCP tools.\n\n", .{});
                    try color.printBold(effective_w, effective_color, "OPTIONS:\n", .{});
                    try effective_w.print("  --help, -h          Show this help message\n\n", .{});
                    try color.printBold(effective_w, effective_color, "EXAMPLES:\n", .{});
                    try effective_w.print("  # Start MCP server (typically called by AI editor)\n", .{});
                    try effective_w.print("  zr mcp serve\n\n", .{});
                    try color.printBold(effective_w, effective_color, "INTEGRATION:\n", .{});
                    try effective_w.print("  Add to Claude Code config:\n", .{});
                    try effective_w.print("  {{\"mcpServers\": {{\"zr\": {{\"command\": \"zr\", \"args\": [\"mcp\", \"serve\"]}}}}}}\n\n", .{});
                    try effective_w.print("  See docs/guides/mcp-integration.md for detailed setup instructions.\n", .{});
                    return 0;
                }
            }
            return mcp_server.serve(allocator);
        } else {
            try color.printError(ew, effective_color, "mcp: unknown subcommand '{s}'\n\n  Hint: zr mcp serve\n", .{subcmd});
            return 1;
        }
    } else if (std.mem.eql(u8, cmd, "lsp")) {
        // LSP server: zr lsp
        // Check for --help flag
        const lsp_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        for (lsp_args) |arg| {
            if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                try color.printBold(effective_w, effective_color, "Usage: zr lsp [OPTIONS]\n\n", .{});
                try effective_w.print("Start LSP (Language Server Protocol) server for editor integration.\n\n", .{});
                try color.printBold(effective_w, effective_color, "DESCRIPTION:\n", .{});
                try effective_w.print("  The LSP server provides rich editing features for zr.toml files:\n", .{});
                try effective_w.print("  - Syntax highlighting and validation\n", .{});
                try effective_w.print("  - Auto-completion for task names, fields, and dependencies\n", .{});
                try effective_w.print("  - Hover documentation for configuration options\n", .{});
                try effective_w.print("  - Go-to-definition for task dependencies\n", .{});
                try effective_w.print("  - Real-time diagnostics for configuration errors\n\n", .{});
                try color.printBold(effective_w, effective_color, "OPTIONS:\n", .{});
                try effective_w.print("  --help, -h          Show this help message\n\n", .{});
                try color.printBold(effective_w, effective_color, "EXAMPLES:\n", .{});
                try effective_w.print("  # Start LSP server (typically called by editor)\n", .{});
                try effective_w.print("  zr lsp\n\n", .{});
                try color.printBold(effective_w, effective_color, "EDITOR INTEGRATION:\n", .{});
                try effective_w.print("  VS Code: Install the zr extension from marketplace\n", .{});
                try effective_w.print("  Neovim:  Configure nvim-lspconfig with cmd = {{\"zr\", \"lsp\"}}\n\n", .{});
                try effective_w.print("  See docs/guides/lsp-setup.md for detailed setup instructions.\n", .{});
                return 0;
            }
        }
        return lsp_server.serve(allocator);
    } else if (std.mem.eql(u8, cmd, "conformance")) {
        const conformance_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return conformance_cmd.cmdConformance(allocator, conformance_args, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "bench")) {
        const bench_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return bench_cmd.cmdBench(allocator, bench_args, effective_w, ew, json_output);
    } else if (std.mem.eql(u8, cmd, "doctor")) {
        const doctor_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        var opts = doctor_cmd.DoctorOptions{};
        for (doctor_args) |arg| {
            if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                try color.printInfo(effective_w, effective_color,
                    "Usage: zr doctor [OPTIONS]\n\n" ++
                    "Diagnose environment and toolchain setup issues.\n\n" ++
                    "OPTIONS:\n" ++
                    "  --verbose, -v         Show detailed diagnostic output\n" ++
                    "  --config=<path>       Config file path (default: zr.toml)\n" ++
                    "  -h, --help            Show this help\n\n" ++
                    "EXAMPLES:\n" ++
                    "  zr doctor                       # Check environment setup\n" ++
                    "  zr doctor --verbose             # Detailed diagnostics\n",
                    .{},
                );
                return 0;
            } else if (std.mem.startsWith(u8, arg, "--config=")) {
                opts.config_path = arg["--config=".len..];
            } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
                opts.verbose = true;
            }
        }
        return doctor_cmd.cmdDoctor(allocator, opts, effective_w, ew);
    } else if (std.mem.eql(u8, cmd, "cd")) {
        if (effective_args.len < 3 or std.mem.eql(u8, effective_args[2], "--help") or std.mem.eql(u8, effective_args[2], "-h")) {
            if (effective_args.len >= 3 and (std.mem.eql(u8, effective_args[2], "--help") or std.mem.eql(u8, effective_args[2], "-h"))) {
                try effective_w.writeAll("Usage: zr cd <member-name>\n\n");
                try effective_w.writeAll("Change directory to a workspace member project.\n\n");
                try effective_w.writeAll("Arguments:\n");
                try effective_w.writeAll("  <member-name>   Name of the workspace member to navigate to\n\n");
                try effective_w.writeAll("Examples:\n");
                try effective_w.writeAll("  zr cd frontend\n");
                try effective_w.writeAll("  zr cd backend/api\n\n");
                try effective_w.writeAll("Note: Use with eval: eval $(zr cd frontend)\n");
                return 0;
            }
            try color.printError(ew, effective_color, "[CD]: missing workspace member name\n\n  Hint: zr cd <member-name>\n", .{});
            return 1;
        }
        const member_name = effective_args[2];
        return cd_cmd.cmdCd(allocator, std.fs.cwd(), member_name, effective_w, ew, effective_color);
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
        return upgrade_cmd.cmdUpgrade(allocator, upgrade_args, effective_w, ew);
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

        // Parse --limit and --format flags from remaining args
        var limit: usize = 20; // Default to last 20 runs
        var estimate_json = json_output; // inherit global --format json
        var i: usize = 3;
        while (i < effective_args.len) : (i += 1) {
            const arg = effective_args[i];
            if (std.mem.eql(u8, arg, "--limit")) {
                i += 1;
                if (i >= effective_args.len) {
                    try color.printError(ew, effective_color, "[Estimate]: --limit requires a number\n", .{});
                    return 1;
                }
                limit = std.fmt.parseInt(usize, effective_args[i], 10) catch {
                    try color.printError(ew, effective_color, "[Estimate]: invalid limit value: {s}\n", .{effective_args[i]});
                    return 1;
                };
                if (limit == 0) {
                    try color.printError(ew, effective_color, "[Estimate]: --limit must be greater than 0\n", .{});
                    return 1;
                }
            } else if (std.mem.startsWith(u8, arg, "--limit=")) {
                const val = arg["--limit=".len..];
                limit = std.fmt.parseInt(usize, val, 10) catch {
                    try color.printError(ew, effective_color, "[Estimate]: invalid limit value: {s}\n", .{val});
                    return 1;
                };
                if (limit == 0) {
                    try color.printError(ew, effective_color, "[Estimate]: --limit must be greater than 0\n", .{});
                    return 1;
                }
            } else if (std.mem.eql(u8, arg, "--format")) {
                i += 1;
                if (i >= effective_args.len) {
                    try color.printError(ew, effective_color, "[Estimate]: --format requires a value (text|json)\n", .{});
                    return 1;
                }
                if (std.mem.eql(u8, effective_args[i], "json")) {
                    estimate_json = true;
                } else if (std.mem.eql(u8, effective_args[i], "text")) {
                    estimate_json = false;
                }
            } else if (std.mem.eql(u8, arg, "--format=json")) {
                estimate_json = true;
            } else if (std.mem.eql(u8, arg, "--format=text")) {
                estimate_json = false;
            }
        }

        // Convert json_output to estimate's OutputFormat
        const estimate_format: estimate_cmd.OutputFormat = if (estimate_json) .json else .text;

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
        if (std.mem.eql(u8, edit_args[0], "--help") or std.mem.eql(u8, edit_args[0], "-h")) {
            try color.printInfo(effective_w, effective_color,
                "Usage: zr edit <task|workflow|profile> [OPTIONS]\n\n" ++
                "Open a TUI editor to create or modify a task, workflow, or profile.\n\n" ++
                "ARGUMENTS:\n" ++
                "  task                  Edit a task definition\n" ++
                "  workflow              Edit a workflow definition\n" ++
                "  profile               Edit a profile definition\n\n" ++
                "GLOBAL OPTIONS:\n" ++
                "  --config <path>       Config file path (default: zr.toml)\n" ++
                "  -h, --help            Show this help\n\n" ++
                "EXAMPLES:\n" ++
                "  zr edit task                    # Open TUI to edit a task\n" ++
                "  zr edit workflow                # Open TUI to edit a workflow\n",
                .{},
            );
            return 0;
        }
        const entity_type = edit_args[0];
        return config_editor.cmdEdit(allocator, entity_type, edit_args[1..], effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "explain")) {
        const explain_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return explain_cmd.cmdExplain(allocator, explain_args, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "tags")) {
        const tags_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        return tags_cmd.cmdTags(allocator, tags_args, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "failures")) {
        const failures_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        var opts = failures_cmd.FailuresOptions{
            .use_color = effective_color,
        };

        // Handle --help before subcommand dispatch
        if (failures_args.len > 0 and
            (std.mem.eql(u8, failures_args[0], "--help") or std.mem.eql(u8, failures_args[0], "-h")))
        {
            try failures_cmd.printHelp(effective_w);
            return 0;
        }

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
            return failures_cmd.cmdFailuresClear(allocator, opts, effective_w, ew);
        } else {
            return failures_cmd.cmdFailures(allocator, opts, effective_w, ew);
        }
    } else if (std.mem.eql(u8, cmd, "template")) {
        const template_args = if (effective_args.len >= 3) effective_args[2..] else &[_][]const u8{};
        if (template_args.len == 0) {
            try color.printError(ew, effective_color, "Usage: zr template <list|show|add> [--builtin] [args...]\n", .{});
            return 1;
        }
        if (std.mem.eql(u8, template_args[0], "--help") or std.mem.eql(u8, template_args[0], "-h")) {
            try color.printInfo(effective_w, effective_color,
                "Usage: zr template <SUBCOMMAND> [OPTIONS]\n\n" ++
                "Manage and apply task/workflow templates.\n\n" ++
                "SUBCOMMANDS:\n" ++
                "  list                  List available templates\n" ++
                "  show <name>           Show template details\n" ++
                "  add <name>            Apply a template to the current project\n\n" ++
                "OPTIONS:\n" ++
                "  --builtin             Show/use built-in templates only\n\n" ++
                "GLOBAL OPTIONS:\n" ++
                "  --config <path>       Config file path (default: zr.toml)\n" ++
                "  -h, --help            Show this help\n\n" ++
                "EXAMPLES:\n" ++
                "  zr template list                # List all available templates\n" ++
                "  zr template list --builtin      # List built-in templates only\n" ++
                "  zr template add ci-github       # Apply the GitHub CI template\n",
                .{},
            );
            return 0;
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

        if (std.mem.eql(u8, subcommand, "--help") or std.mem.eql(u8, subcommand, "-h")) {
            try ci_cmd.printHelp(effective_w);
            return 0;
        } else if (std.mem.eql(u8, subcommand, "generate")) {
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
                } else if (!std.mem.startsWith(u8, arg, "-")) {
                    // Positional arg: first non-flag is the platform name
                    if (ci_platform == null) ci_platform = arg;
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
        if (effective_args.len < 3 or std.mem.eql(u8, effective_args[2], "--help") or std.mem.eql(u8, effective_args[2], "-h")) {
            if (effective_args.len >= 3 and (std.mem.eql(u8, effective_args[2], "--help") or std.mem.eql(u8, effective_args[2], "-h"))) {
                try color.printInfo(effective_w, effective_color,
                    "Usage: zr which <TASK>\n\n" ++
                    "Show where a task is defined in the configuration.\n\n" ++
                    "ARGUMENTS:\n" ++
                    "  <task>                Task name to locate (required)\n\n" ++
                    "GLOBAL OPTIONS:\n" ++
                    "  --config <path>       Config file path (default: zr.toml)\n" ++
                    "  -h, --help            Show this help\n\n" ++
                    "EXAMPLES:\n" ++
                    "  zr which build                  # Show where 'build' task is defined\n" ++
                    "  zr which test                   # Show config file and line for 'test'\n",
                    .{},
                );
                return 0;
            }
            try color.printError(ew, effective_color, "which: missing task name\n\n  Hint: zr which <task>\n", .{});
            return 1;
        }
        const task_name = effective_args[2];
        return which_cmd.cmdWhich(allocator, task_name, config_path, effective_w, ew, effective_color);
    } else if (std.mem.eql(u8, cmd, "artifacts")) {
        // Handle artifact management: zr artifacts get/clean
        // Pass effective_args[1..] so artifacts.handle sees args[0]="artifacts", args[1]=subcommand
        const artifacts_argv = if (effective_args.len >= 2) effective_args[1..] else effective_args;
        artifacts_cmd.handle(allocator, artifacts_argv, effective_w, ew) catch |err| {
            try color.printError(ew, effective_color, "artifacts error: {}\n", .{err});
            return 1;
        };
        return 0;
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
    try w.print("  run <task|pattern>     Run a task and its dependencies\n", .{});
    try w.print("    --tag=TAG            Filter tasks by tag (repeatable, AND logic)\n", .{});
    try w.print("    --exclude-tag=TAG    Exclude tasks with tag (repeatable)\n", .{});
    try w.print("    --dir=PATH           Filter tasks by working directory prefix\n", .{});
    try w.print("    --skip=TASK          Skip specific tasks (repeatable, comma-separated)\n", .{});
    try w.print("    --only               Run only the specified task(s) without their dependencies\n", .{});
    try w.print("    --notify             Enable desktop notifications for all tasks\n", .{});
    try w.print("    --fail-fast          Stop on first task failure (default: continue)\n", .{});
    try w.print("  watch <task> [path...] Watch files and auto-run task on changes\n", .{});
    try w.print("  workflow <name>        Run a workflow by name\n", .{});
    try w.print("  list [pattern] [--tree] [--tags=TAG,...]  List tasks (filters: pattern, tags; --tree for dependency tree)\n", .{});
    try w.print("  which <task>           Show where a task is defined\n", .{});
    try w.print("  graph [--ascii]        Show task dependency graph (--ascii for tree view)\n", .{});
    try w.print("  history [stats|clear]  Show recent run history; stats for aggregates, clear to delete\n", .{});
    try w.print("  workspace list         List workspace member directories\n", .{});
    try w.print("  workspace run <task>   Run a task across all workspace members\n", .{});
    try w.print("  workspace sync         Build synthetic workspace from multi-repo\n", .{});
    try w.print("  affected <task>        Run task on affected workspace members\n", .{});
    try w.print("  cache clear            Clear all cached task results\n", .{});
    try w.print("  cache status           Show cache statistics\n", .{});
    try w.print("  artifacts get <task>   List/retrieve stored task output artifacts\n", .{});
    try w.print("  artifacts clean        Remove old artifacts based on retention policy\n", .{});
    try w.print("  deps check             Verify all dependencies satisfy constraints\n", .{});
    try w.print("  deps install           List or install missing dependencies\n", .{});
    try w.print("  deps outdated          Show available updates for dependencies\n", .{});
    try w.print("  deps lock              Generate lock file with resolved versions\n", .{});
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
    try w.print("    --from-npm           Migrate from package.json scripts\n", .{});
    try w.print("    --from-make          Migrate from Makefile\n", .{});
    try w.print("    --from-just          Migrate from justfile\n", .{});
    try w.print("    --from-task          Migrate from Taskfile.yml\n", .{});
    try w.print("    --dry-run            Preview migration without creating files\n", .{});
    try w.print("  template list          List available task/workflow templates\n", .{});
    try w.print("  template add <name>    Apply a template to current project\n", .{});
    try w.print("  ci list                List available CI/CD integration templates\n", .{});
    try w.print("  ci generate <provider> Generate CI pipeline config (github|gitlab|circleci)\n", .{});
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
    try w.print("  explain <task>         Show execution plan and dependency chain for a task\n", .{});
    try w.print("    --tree               Display dependency tree visually\n", .{});
    try w.print("    --json               Output execution plan as JSON\n", .{});
    try w.print("  tags [<tag>]           List all tags (or tasks for a specific tag)\n", .{});
    try w.print("    --sort=count         Sort by task count (default: alphabetical)\n", .{});
    try w.print("    --json               Output as JSON\n", .{});
    try w.print("  help <task>            Show rich formatted help for a task\n", .{});
    try w.print("  man <task>             Show man-page style documentation for a task\n", .{});
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

test "live --help shows help instead of treating flag as task name" {
    const allocator = std.testing.allocator;

    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = null_file.writer(&out_buf);
    var err_w = null_file.writer(&err_buf);

    const fake_args = [_][]const u8{ "zr", "live", "--help" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "monitor --help shows help instead of treating flag as workflow name" {
    const allocator = std.testing.allocator;

    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = null_file.writer(&out_buf);
    var err_w = null_file.writer(&err_buf);

    const fake_args = [_][]const u8{ "zr", "monitor", "--help" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "irun --help shows help instead of treating flag as task name" {
    const allocator = std.testing.allocator;

    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();

    var out_buf: [4096]u8 = undefined;
    var err_buf: [4096]u8 = undefined;
    var out_w = null_file.writer(&out_buf);
    var err_w = null_file.writer(&err_buf);

    const fake_args = [_][]const u8{ "zr", "irun", "--help" };
    const code = try run(allocator, &fake_args, &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 0), code);
}

// Force remote module test discovery by referencing it
comptime {
    _ = remote.RemoteExecutor;
    _ = tui_profiler.TuiProfiler;
    _ = cache_key.CacheKeyGenerator;
    _ = notification.NotifyOn;
}

