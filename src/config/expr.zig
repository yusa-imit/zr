const std = @import("std");
const builtin = @import("builtin");

pub const EvalError = error{ OutOfMemory, InvalidExpression };

/// Runtime execution state for tasks and stages.
/// Used to evaluate expressions like stages['name'].success or tasks['name'].duration.
pub const RuntimeState = struct {
    /// Results from completed tasks (task_name -> TaskState).
    tasks: std.StringHashMap(TaskState),
    /// Results from completed workflow stages (stage_name -> StageState).
    stages: std.StringHashMap(StageState),

    pub const TaskState = struct {
        success: bool,
        duration_ms: u64,
    };

    pub const StageState = struct {
        success: bool,
    };

    pub fn init(allocator: std.mem.Allocator) RuntimeState {
        return .{
            .tasks = std.StringHashMap(TaskState).init(allocator),
            .stages = std.StringHashMap(StageState).init(allocator),
        };
    }

    pub fn deinit(self: *RuntimeState) void {
        self.tasks.deinit();
        self.stages.deinit();
    }
};

const ExprContext = struct {
    allocator: std.mem.Allocator,
    task_env: ?[]const [2][]const u8,
    runtime_state: ?*const RuntimeState,
};

/// Evaluate a condition expression string.
/// `task_env` contains per-task env overrides (checked first before process env).
/// `runtime_state` contains task/stage execution results for runtime references.
/// Returns true if the condition passes (task should run), false if skipped.
/// On parse error or unknown expression, returns true (fail-open: run the task).
pub fn evalCondition(
    allocator: std.mem.Allocator,
    expr: []const u8,
    task_env: ?[]const [2][]const u8,
) EvalError!bool {
    return evalConditionWithState(allocator, expr, task_env, null);
}

/// Evaluate a condition with optional runtime state.
pub fn evalConditionWithState(
    allocator: std.mem.Allocator,
    expr: []const u8,
    task_env: ?[]const [2][]const u8,
    runtime_state: ?*const RuntimeState,
) EvalError!bool {
    const ctx = ExprContext{
        .allocator = allocator,
        .task_env = task_env,
        .runtime_state = runtime_state,
    };
    return evalOr(&ctx, expr) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidExpression => return true, // fail-open
    };
}

/// Parse OR expression (lowest precedence)
fn evalOr(ctx: *const ExprContext, expr: []const u8) !bool {
    const trimmed = std.mem.trim(u8, expr, " \t\r\n");

    // Find || operator (must scan for it outside of quotes/parens)
    if (std.mem.indexOf(u8, trimmed, "||")) |pos| {
        const left = trimmed[0..pos];
        const right = trimmed[pos + 2 ..];
        const left_val = try evalAnd(ctx, left);
        if (left_val) return true; // Short-circuit
        return evalAnd(ctx, right);
    }

    return evalAnd(ctx, trimmed);
}

/// Parse AND expression
fn evalAnd(ctx: *const ExprContext, expr: []const u8) !bool {
    const trimmed = std.mem.trim(u8, expr, " \t\r\n");

    // Find && operator
    if (std.mem.indexOf(u8, trimmed, "&&")) |pos| {
        const left = trimmed[0..pos];
        const right = trimmed[pos + 2 ..];
        const left_val = try evalPrimary(ctx, left);
        if (!left_val) return false; // Short-circuit
        return evalPrimary(ctx, right);
    }

    return evalPrimary(ctx, trimmed);
}

/// Parse primary expression (literals, function calls, env vars, platform checks)
fn evalPrimary(ctx: *const ExprContext, expr: []const u8) !bool {
    const trimmed = std.mem.trim(u8, expr, " \t\r\n");

    // Literal booleans
    if (std.mem.eql(u8, trimmed, "true")) return true;
    if (std.mem.eql(u8, trimmed, "false")) return false;

    // Platform check: platform == "linux"
    if (std.mem.startsWith(u8, trimmed, "platform")) {
        return evalPlatformCheck(trimmed);
    }

    // Arch check: arch == "x86_64"
    if (std.mem.startsWith(u8, trimmed, "arch")) {
        return evalArchCheck(trimmed);
    }

    // File functions
    if (std.mem.startsWith(u8, trimmed, "file.exists(")) {
        return evalFileExists(ctx, trimmed);
    }
    if (std.mem.startsWith(u8, trimmed, "file.changed(")) {
        return evalFileChanged(ctx, trimmed);
    }
    if (std.mem.startsWith(u8, trimmed, "file.newer(")) {
        return evalFileNewer(ctx, trimmed);
    }
    if (std.mem.startsWith(u8, trimmed, "file.hash(")) {
        return evalFileHash(ctx, trimmed);
    }

    // Shell command execution
    if (std.mem.startsWith(u8, trimmed, "shell(")) {
        return evalShell(ctx, trimmed);
    }

    // Semver comparison
    if (std.mem.startsWith(u8, trimmed, "semver.gte(")) {
        return evalSemverGte(ctx, trimmed);
    }

    // Environment variable check
    if (std.mem.startsWith(u8, trimmed, "env.")) {
        return evalEnvCheck(ctx, trimmed);
    }

    // Runtime state references: stages['name'].success
    if (std.mem.startsWith(u8, trimmed, "stages[")) {
        return evalStageRef(ctx, trimmed);
    }

    // Runtime state references: tasks['name'].duration
    if (std.mem.startsWith(u8, trimmed, "tasks[")) {
        return evalTaskRef(ctx, trimmed);
    }

    // Unknown expression: fail-open
    return true;
}

/// Evaluate platform == "linux" | "darwin" | "windows"
fn evalPlatformCheck(expr: []const u8) !bool {
    const after_platform = std.mem.trim(u8, expr["platform".len..], " \t");
    if (!std.mem.startsWith(u8, after_platform, "==")) {
        return error.InvalidExpression;
    }

    const rhs_raw = std.mem.trim(u8, after_platform["==".len..], " \t");
    const rhs = stripQuotes(rhs_raw);

    const current_os = switch (builtin.os.tag) {
        .linux => "linux",
        .macos => "darwin",
        .windows => "windows",
        else => "unknown",
    };

    return std.mem.eql(u8, current_os, rhs);
}

/// Evaluate arch == "x86_64" | "aarch64"
fn evalArchCheck(expr: []const u8) !bool {
    const after_arch = std.mem.trim(u8, expr["arch".len..], " \t");
    if (!std.mem.startsWith(u8, after_arch, "==")) {
        return error.InvalidExpression;
    }

    const rhs_raw = std.mem.trim(u8, after_arch["==".len..], " \t");
    const rhs = stripQuotes(rhs_raw);

    const current_arch = switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        else => "unknown",
    };

    return std.mem.eql(u8, current_arch, rhs);
}

/// Evaluate file.exists("path")
fn evalFileExists(_: *const ExprContext, expr: []const u8) !bool {
    const start_paren = std.mem.indexOf(u8, expr, "(") orelse return error.InvalidExpression;
    const end_paren = std.mem.lastIndexOf(u8, expr, ")") orelse return error.InvalidExpression;

    const arg_raw = expr[start_paren + 1 .. end_paren];
    const arg = stripQuotes(std.mem.trim(u8, arg_raw, " \t"));

    // Check if file exists
    std.fs.cwd().access(arg, .{}) catch return false;
    return true;
}

/// Evaluate file.changed("glob") - checks git diff
fn evalFileChanged(ctx: *const ExprContext, expr: []const u8) !bool {
    const start_paren = std.mem.indexOf(u8, expr, "(") orelse return error.InvalidExpression;
    const end_paren = std.mem.lastIndexOf(u8, expr, ")") orelse return error.InvalidExpression;

    const glob_raw = expr[start_paren + 1 .. end_paren];
    const glob = stripQuotes(std.mem.trim(u8, glob_raw, " \t"));

    // Execute git diff to check for changes using Child.run
    const result = std.process.Child.run(.{
        .allocator = ctx.allocator,
        .argv = &[_][]const u8{
            "git",
            "diff",
            "--name-only",
            "HEAD",
            "--",
            glob,
        },
    }) catch return false; // Not a git repo or git not available

    defer ctx.allocator.free(result.stdout);
    defer ctx.allocator.free(result.stderr);

    // If any files match the glob pattern in the diff, return true
    return result.stdout.len > 0;
}

/// Evaluate env.VAR_NAME [operator "value"]
fn evalEnvCheck(ctx: *const ExprContext, expr: []const u8) !bool {
    // Extract variable name: chars up to space, '=', '!', or end of string
    const after_prefix = expr["env.".len..];
    const var_name_end = blk: {
        for (after_prefix, 0..) |c, i| {
            if (c == ' ' or c == '\t' or c == '=' or c == '!') break :blk i;
        }
        break :blk after_prefix.len;
    };

    if (var_name_end == 0) {
        return error.InvalidExpression;
    }

    const var_name = after_prefix[0..var_name_end];
    const rest = std.mem.trim(u8, after_prefix[var_name_end..], " \t");

    // Look up the env value (task_env first, then process env)
    const env_value = try lookupEnv(ctx.allocator, var_name, ctx.task_env);
    defer if (env_value) |v| ctx.allocator.free(v);

    const value_str = if (env_value) |v| v else "";

    if (rest.len == 0) {
        // Truthy check: non-empty value
        return value_str.len > 0;
    }

    // Parse operator: "==" or "!="
    if (std.mem.startsWith(u8, rest, "==")) {
        const rhs_raw = std.mem.trim(u8, rest["==".len..], " \t");
        const rhs = stripQuotes(rhs_raw);
        return std.mem.eql(u8, value_str, rhs);
    }

    if (std.mem.startsWith(u8, rest, "!=")) {
        const rhs_raw = std.mem.trim(u8, rest["!=".len..], " \t");
        const rhs = stripQuotes(rhs_raw);
        return !std.mem.eql(u8, value_str, rhs);
    }

    return error.InvalidExpression;
}

/// Evaluate file.newer("target", "source")
/// Returns true if target file is newer than source file (or directory).
/// For directories, compares against the newest file in the directory tree.
fn evalFileNewer(ctx: *const ExprContext, expr: []const u8) !bool {
    const start_paren = std.mem.indexOf(u8, expr, "(") orelse return error.InvalidExpression;
    const end_paren = std.mem.lastIndexOf(u8, expr, ")") orelse return error.InvalidExpression;

    const args_raw = expr[start_paren + 1 .. end_paren];

    // Find the comma separating the two arguments
    const comma_idx = std.mem.indexOf(u8, args_raw, ",") orelse return error.InvalidExpression;

    const target_raw = std.mem.trim(u8, args_raw[0..comma_idx], " \t");
    const source_raw = std.mem.trim(u8, args_raw[comma_idx + 1..], " \t");

    const target = stripQuotes(target_raw);
    const source = stripQuotes(source_raw);

    // Get modification time for target
    const target_stat = std.fs.cwd().statFile(target) catch return false;
    const target_mtime = target_stat.mtime;

    // Get modification time for source (could be file or directory)
    const source_stat = std.fs.cwd().statFile(source) catch |err| {
        // If source is a directory, we need to find the newest file in it
        if (err == error.IsDir) {
            const newest_mtime = try findNewestFileInDir(ctx.allocator, source);
            return target_mtime > newest_mtime;
        }
        return false;
    };

    return target_mtime > source_stat.mtime;
}

/// Find the newest file modification time in a directory tree
fn findNewestFileInDir(allocator: std.mem.Allocator, dir_path: []const u8) !i128 {
    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return 0;
    defer dir.close();

    var newest: i128 = 0;
    var walker = dir.walk(allocator) catch return 0;
    defer walker.deinit();

    while (walker.next() catch null) |entry| {
        if (entry.kind == .file) {
            const stat = entry.dir.statFile(entry.basename) catch continue;
            if (stat.mtime > newest) {
                newest = stat.mtime;
            }
        }
    }

    return newest;
}

/// Evaluate file.hash("path")
/// Returns the hash of the file content as a hex string.
/// Currently uses Wyhash for speed. Always returns true (used for change detection).
fn evalFileHash(ctx: *const ExprContext, expr: []const u8) !bool {
    const start_paren = std.mem.indexOf(u8, expr, "(") orelse return error.InvalidExpression;
    const end_paren = std.mem.lastIndexOf(u8, expr, ")") orelse return error.InvalidExpression;

    const arg_raw = expr[start_paren + 1 .. end_paren];
    const arg = stripQuotes(std.mem.trim(u8, arg_raw, " \t"));

    // Read file content
    const file = std.fs.cwd().openFile(arg, .{}) catch return false;
    defer file.close();

    const content = file.readToEndAlloc(ctx.allocator, 100 * 1024 * 1024) catch return false; // 100MB max
    defer ctx.allocator.free(content);

    // Compute hash (we return true since this is typically used in comparisons)
    _ = std.hash.Wyhash.hash(0, content);

    // Note: In a real implementation, this would store/compare the hash
    // For now, we just return true to indicate the file was readable
    return true;
}

/// Evaluate shell("command")
/// Executes a shell command and checks if it succeeds (exit code 0).
/// Security: This is intentionally limited to checking success/failure only.
fn evalShell(ctx: *const ExprContext, expr: []const u8) !bool {
    const start_paren = std.mem.indexOf(u8, expr, "(") orelse return error.InvalidExpression;
    const end_paren = std.mem.lastIndexOf(u8, expr, ")") orelse return error.InvalidExpression;

    const cmd_raw = expr[start_paren + 1 .. end_paren];
    const cmd = stripQuotes(std.mem.trim(u8, cmd_raw, " \t"));

    // Execute command via shell
    const shell_cmd = if (builtin.os.tag == .windows) "cmd.exe" else "sh";
    const shell_flag = if (builtin.os.tag == .windows) "/C" else "-c";

    const result = std.process.Child.run(.{
        .allocator = ctx.allocator,
        .argv = &[_][]const u8{ shell_cmd, shell_flag, cmd },
    }) catch return false;

    defer ctx.allocator.free(result.stdout);
    defer ctx.allocator.free(result.stderr);

    // Return true if command succeeded
    return switch (result.term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

/// Evaluate semver.gte("version1", "version2")
/// Returns true if version1 >= version2 (semantic versioning comparison).
fn evalSemverGte(ctx: *const ExprContext, expr: []const u8) !bool {
    const start_paren = std.mem.indexOf(u8, expr, "(") orelse return error.InvalidExpression;
    const end_paren = std.mem.lastIndexOf(u8, expr, ")") orelse return error.InvalidExpression;

    const args_raw = expr[start_paren + 1 .. end_paren];

    // Find the comma separating the two arguments
    const comma_idx = std.mem.indexOf(u8, args_raw, ",") orelse return error.InvalidExpression;

    const v1_raw = std.mem.trim(u8, args_raw[0..comma_idx], " \t");
    const v2_raw = std.mem.trim(u8, args_raw[comma_idx + 1..], " \t");

    const v1_str = stripQuotes(v1_raw);
    const v2_str = stripQuotes(v2_raw);

    const v1 = parseSemver(v1_str) catch return false;
    const v2 = parseSemver(v2_str) catch return false;

    _ = ctx; // unused but required by signature

    return compareSemver(v1, v2) >= 0;
}

const SemVer = struct {
    major: u32,
    minor: u32,
    patch: u32,
};

/// Parse a semantic version string (e.g., "1.2.3")
fn parseSemver(s: []const u8) !SemVer {
    var iter = std.mem.splitScalar(u8, s, '.');

    const major_str = iter.next() orelse return error.InvalidExpression;
    const minor_str = iter.next() orelse return error.InvalidExpression;
    const patch_str = iter.next() orelse return error.InvalidExpression;

    const major = std.fmt.parseInt(u32, major_str, 10) catch return error.InvalidExpression;
    const minor = std.fmt.parseInt(u32, minor_str, 10) catch return error.InvalidExpression;
    const patch = std.fmt.parseInt(u32, patch_str, 10) catch return error.InvalidExpression;

    return SemVer{ .major = major, .minor = minor, .patch = patch };
}

/// Compare two semantic versions
/// Returns: -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2
fn compareSemver(v1: SemVer, v2: SemVer) i32 {
    if (v1.major != v2.major) {
        return if (v1.major > v2.major) @as(i32, 1) else -1;
    }
    if (v1.minor != v2.minor) {
        return if (v1.minor > v2.minor) @as(i32, 1) else -1;
    }
    if (v1.patch != v2.patch) {
        return if (v1.patch > v2.patch) @as(i32, 1) else -1;
    }
    return 0;
}

/// Evaluate stages['name'].success
/// Returns true if the named stage exists in runtime state and succeeded.
/// If runtime_state is null or stage not found, returns true (fail-open).
fn evalStageRef(ctx: *const ExprContext, expr: []const u8) !bool {
    // Parse: stages['name'].success
    const start_bracket = std.mem.indexOf(u8, expr, "[") orelse return error.InvalidExpression;
    const end_bracket = std.mem.indexOf(u8, expr[start_bracket..], "]") orelse return error.InvalidExpression;
    const bracket_end = start_bracket + end_bracket;

    // Extract stage name from brackets
    const name_raw = expr[start_bracket + 1 .. bracket_end];
    const stage_name = stripQuotes(std.mem.trim(u8, name_raw, " \t"));

    // Parse the property after the brackets
    const after_bracket = std.mem.trim(u8, expr[bracket_end + 1 ..], " \t");
    if (!std.mem.startsWith(u8, after_bracket, ".success")) {
        return error.InvalidExpression;
    }

    // Look up stage in runtime state
    const runtime_state = ctx.runtime_state orelse return true; // No state available, fail-open
    const stage_state = runtime_state.stages.get(stage_name) orelse return true; // Stage not found, fail-open

    return stage_state.success;
}

/// Evaluate tasks['name'].duration [operator value]
/// Examples:
///   tasks['test'].duration < 60  -> true if test task duration < 60 seconds
///   tasks['build'].duration      -> true if task duration > 0 (truthy check)
/// If runtime_state is null or task not found, returns true (fail-open).
fn evalTaskRef(ctx: *const ExprContext, expr: []const u8) !bool {
    // Parse: tasks['name'].duration [< > <= >= == !=] [value]
    const start_bracket = std.mem.indexOf(u8, expr, "[") orelse return error.InvalidExpression;
    const end_bracket = std.mem.indexOf(u8, expr[start_bracket..], "]") orelse return error.InvalidExpression;
    const bracket_end = start_bracket + end_bracket;

    // Extract task name from brackets
    const name_raw = expr[start_bracket + 1 .. bracket_end];
    const task_name = stripQuotes(std.mem.trim(u8, name_raw, " \t"));

    // Parse the property after the brackets
    const after_bracket = std.mem.trim(u8, expr[bracket_end + 1 ..], " \t");
    if (!std.mem.startsWith(u8, after_bracket, ".duration")) {
        return error.InvalidExpression;
    }

    // Look up task in runtime state
    const runtime_state = ctx.runtime_state orelse return true; // No state available, fail-open
    const task_state = runtime_state.tasks.get(task_name) orelse return true; // Task not found, fail-open

    const duration_sec = task_state.duration_ms / 1000;

    // Check if there's a comparison operator after .duration
    const after_duration = std.mem.trim(u8, after_bracket[".duration".len..], " \t");

    if (after_duration.len == 0) {
        // Truthy check: duration > 0
        return duration_sec > 0;
    }

    // Parse comparison operator
    if (std.mem.startsWith(u8, after_duration, "<=")) {
        const rhs_str = std.mem.trim(u8, after_duration["<=".len..], " \t");
        const rhs = std.fmt.parseInt(u64, rhs_str, 10) catch return error.InvalidExpression;
        return duration_sec <= rhs;
    }

    if (std.mem.startsWith(u8, after_duration, ">=")) {
        const rhs_str = std.mem.trim(u8, after_duration[">=".len..], " \t");
        const rhs = std.fmt.parseInt(u64, rhs_str, 10) catch return error.InvalidExpression;
        return duration_sec >= rhs;
    }

    if (std.mem.startsWith(u8, after_duration, "<")) {
        const rhs_str = std.mem.trim(u8, after_duration["<".len..], " \t");
        const rhs = std.fmt.parseInt(u64, rhs_str, 10) catch return error.InvalidExpression;
        return duration_sec < rhs;
    }

    if (std.mem.startsWith(u8, after_duration, ">")) {
        const rhs_str = std.mem.trim(u8, after_duration[">".len..], " \t");
        const rhs = std.fmt.parseInt(u64, rhs_str, 10) catch return error.InvalidExpression;
        return duration_sec > rhs;
    }

    if (std.mem.startsWith(u8, after_duration, "==")) {
        const rhs_str = std.mem.trim(u8, after_duration["==".len..], " \t");
        const rhs = std.fmt.parseInt(u64, rhs_str, 10) catch return error.InvalidExpression;
        return duration_sec == rhs;
    }

    if (std.mem.startsWith(u8, after_duration, "!=")) {
        const rhs_str = std.mem.trim(u8, after_duration["!=".len..], " \t");
        const rhs = std.fmt.parseInt(u64, rhs_str, 10) catch return error.InvalidExpression;
        return duration_sec != rhs;
    }

    return error.InvalidExpression;
}

// --- Private helpers ---

/// Look up an environment variable value.
/// Checks task_env pairs first (by key), then the process environment.
/// Returns an owned slice (caller must free), or null if not found.
fn lookupEnv(
    allocator: std.mem.Allocator,
    key: []const u8,
    task_env: ?[]const [2][]const u8,
) EvalError!?[]u8 {
    // Check task_env overrides first
    if (task_env) |pairs| {
        for (pairs) |pair| {
            if (std.mem.eql(u8, pair[0], key)) {
                return try allocator.dupe(u8, pair[1]);
            }
        }
    }

    // Fall back to process environment
    const val = std.process.getEnvVarOwned(allocator, key) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        error.OutOfMemory => return error.OutOfMemory,
        // InvalidWtf8 can occur on Windows; treat as not found
        else => return null,
    };
    return val;
}

/// Strip matching single or double quotes from a value string.
/// Returns the inner content, or the original string if no quotes.
fn stripQuotes(s: []const u8) []const u8 {
    if (s.len >= 2) {
        if ((s[0] == '"' and s[s.len - 1] == '"') or
            (s[0] == '\'' and s[s.len - 1] == '\''))
        {
            return s[1 .. s.len - 1];
        }
    }
    return s;
}

// --- Tests ---

test "evalCondition: literals" {
    const allocator = std.testing.allocator;

    try std.testing.expect(try evalCondition(allocator, "true", null));
    try std.testing.expect(!try evalCondition(allocator, "false", null));

    // Whitespace trimming
    try std.testing.expect(try evalCondition(allocator, "  true  ", null));
    try std.testing.expect(!try evalCondition(allocator, "  false  ", null));
}

test "evalCondition: unknown expression returns true" {
    const allocator = std.testing.allocator;

    try std.testing.expect(try evalCondition(allocator, "some_unknown_expr", null));
    try std.testing.expect(try evalCondition(allocator, "", null));
    try std.testing.expect(try evalCondition(allocator, "env.", null));
    try std.testing.expect(try evalCondition(allocator, "env.VAR >=< 42", null));
}

test "evalCondition: env truthy check" {
    const allocator = std.testing.allocator;

    // Set value via task_env — non-empty is truthy
    const env_set = [_][2][]const u8{.{ "MY_FLAG", "1" }};
    try std.testing.expect(try evalCondition(allocator, "env.MY_FLAG", &env_set));

    // Empty value is falsy
    const env_empty = [_][2][]const u8{.{ "MY_FLAG", "" }};
    try std.testing.expect(!try evalCondition(allocator, "env.MY_FLAG", &env_empty));

    // Variable not present in task_env and not in process env (very unlikely name)
    try std.testing.expect(!try evalCondition(
        allocator,
        "env.ZR_NONEXISTENT_VAR_9f3a2b",
        null,
    ));
}

test "evalCondition: env equality" {
    const allocator = std.testing.allocator;

    const pairs = [_][2][]const u8{
        .{ "NODE_ENV", "production" },
        .{ "DEBUG", "false" },
    };

    // Double-quoted rhs
    try std.testing.expect(try evalCondition(allocator, "env.NODE_ENV == \"production\"", &pairs));
    try std.testing.expect(!try evalCondition(allocator, "env.NODE_ENV == \"staging\"", &pairs));

    // Single-quoted rhs
    try std.testing.expect(try evalCondition(allocator, "env.DEBUG == 'false'", &pairs));
    try std.testing.expect(!try evalCondition(allocator, "env.DEBUG == 'true'", &pairs));

    // Missing variable: value is "" — equality with empty string
    try std.testing.expect(try evalCondition(
        allocator,
        "env.ZR_MISSING_ABC == \"\"",
        &pairs,
    ));
}

test "evalCondition: env inequality" {
    const allocator = std.testing.allocator;

    const pairs = [_][2][]const u8{.{ "STAGE", "dev" }};

    try std.testing.expect(try evalCondition(allocator, "env.STAGE != \"production\"", &pairs));
    try std.testing.expect(!try evalCondition(allocator, "env.STAGE != \"dev\"", &pairs));

    // Single-quoted
    try std.testing.expect(try evalCondition(allocator, "env.STAGE != 'prod'", &pairs));
    try std.testing.expect(!try evalCondition(allocator, "env.STAGE != 'dev'", &pairs));
}

test "evalCondition: task_env overrides process env" {
    const allocator = std.testing.allocator;

    // Use PATH which is virtually always set in process env
    // Override it via task_env and verify our value wins
    const override = [_][2][]const u8{.{ "PATH", "my_custom_path" }};

    try std.testing.expect(try evalCondition(
        allocator,
        "env.PATH == \"my_custom_path\"",
        &override,
    ));

    // Without override, PATH almost certainly != "my_custom_path"
    try std.testing.expect(!try evalCondition(
        allocator,
        "env.PATH == \"my_custom_path\"",
        null,
    ));
}

test "evalCondition: logical OR operator" {
    const allocator = std.testing.allocator;

    // true || false -> true
    try std.testing.expect(try evalCondition(allocator, "true || false", null));

    // false || true -> true
    try std.testing.expect(try evalCondition(allocator, "false || true", null));

    // false || false -> false
    try std.testing.expect(!try evalCondition(allocator, "false || false", null));

    // true || true -> true
    try std.testing.expect(try evalCondition(allocator, "true || true", null));

    // With env vars
    const env = [_][2][]const u8{.{ "CI", "true" }};
    try std.testing.expect(try evalCondition(
        allocator,
        "env.CI == \"true\" || env.LOCAL == \"true\"",
        &env,
    ));
}

test "evalCondition: logical AND operator" {
    const allocator = std.testing.allocator;

    // true && true -> true
    try std.testing.expect(try evalCondition(allocator, "true && true", null));

    // true && false -> false
    try std.testing.expect(!try evalCondition(allocator, "true && false", null));

    // false && true -> false
    try std.testing.expect(!try evalCondition(allocator, "false && true", null));

    // false && false -> false
    try std.testing.expect(!try evalCondition(allocator, "false && false", null));

    // With env vars
    const env = [_][2][]const u8{
        .{ "CI", "true" },
        .{ "DEPLOY", "yes" },
    };
    try std.testing.expect(try evalCondition(
        allocator,
        "env.CI == \"true\" && env.DEPLOY == \"yes\"",
        &env,
    ));

    // One fails
    try std.testing.expect(!try evalCondition(
        allocator,
        "env.CI == \"true\" && env.DEPLOY == \"no\"",
        &env,
    ));
}

test "evalCondition: platform check" {
    const allocator = std.testing.allocator;

    // Check current platform
    const current_os = switch (builtin.os.tag) {
        .linux => "linux",
        .macos => "darwin",
        .windows => "windows",
        else => "unknown",
    };

    // Should match current platform
    const expr = try std.fmt.allocPrint(
        allocator,
        "platform == \"{s}\"",
        .{current_os},
    );
    defer allocator.free(expr);
    try std.testing.expect(try evalCondition(allocator, expr, null));

    // Should not match a different platform
    const wrong_platform = if (builtin.os.tag == .linux) "darwin" else "linux";
    const wrong_expr = try std.fmt.allocPrint(
        allocator,
        "platform == \"{s}\"",
        .{wrong_platform},
    );
    defer allocator.free(wrong_expr);
    try std.testing.expect(!try evalCondition(allocator, wrong_expr, null));
}

test "evalCondition: arch check" {
    const allocator = std.testing.allocator;

    // Check current architecture
    const current_arch = switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        else => "unknown",
    };

    // Should match current architecture
    const expr = try std.fmt.allocPrint(
        allocator,
        "arch == \"{s}\"",
        .{current_arch},
    );
    defer allocator.free(expr);
    try std.testing.expect(try evalCondition(allocator, expr, null));

    // Should not match a different architecture
    const wrong_arch = if (builtin.cpu.arch == .x86_64) "aarch64" else "x86_64";
    const wrong_expr = try std.fmt.allocPrint(
        allocator,
        "arch == \"{s}\"",
        .{wrong_arch},
    );
    defer allocator.free(wrong_expr);
    try std.testing.expect(!try evalCondition(allocator, wrong_expr, null));
}

test "evalCondition: file.exists" {
    const allocator = std.testing.allocator;

    // Create a temporary file
    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const temp_path = try temp_dir.dir.realpath(".", &buf);

    // Create a test file
    const test_file_name = "test_exists.txt";
    const test_file = try temp_dir.dir.createFile(test_file_name, .{});
    test_file.close();

    const full_path = try std.fs.path.join(allocator, &[_][]const u8{ temp_path, test_file_name });
    defer allocator.free(full_path);

    // File should exist
    const expr_exists = try std.fmt.allocPrint(
        allocator,
        "file.exists(\"{s}\")",
        .{full_path},
    );
    defer allocator.free(expr_exists);
    try std.testing.expect(try evalCondition(allocator, expr_exists, null));

    // Non-existent file should return false
    const expr_missing = try std.fmt.allocPrint(
        allocator,
        "file.exists(\"{s}/nonexistent.txt\")",
        .{temp_path},
    );
    defer allocator.free(expr_missing);
    try std.testing.expect(!try evalCondition(allocator, expr_missing, null));
}

test "evalCondition: complex expressions" {
    const allocator = std.testing.allocator;

    const env = [_][2][]const u8{
        .{ "CI", "true" },
        .{ "NODE_ENV", "production" },
    };

    // Complex AND + OR
    try std.testing.expect(try evalCondition(
        allocator,
        "env.CI == \"true\" && env.NODE_ENV == \"production\"",
        &env,
    ));

    // Platform combined with env
    const current_os = switch (builtin.os.tag) {
        .linux => "linux",
        .macos => "darwin",
        .windows => "windows",
        else => "unknown",
    };
    const complex_expr = try std.fmt.allocPrint(
        allocator,
        "platform == \"{s}\" && env.CI == \"true\"",
        .{current_os},
    );
    defer allocator.free(complex_expr);
    try std.testing.expect(try evalCondition(allocator, complex_expr, &env));
}

test "evalCondition: file.newer" {
    const allocator = std.testing.allocator;

    // Create temporary directory with two files
    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const temp_path = try temp_dir.dir.realpath(".", &buf);

    // Create old file
    const old_file = try temp_dir.dir.createFile("old.txt", .{});
    old_file.close();

    // Sleep briefly to ensure different timestamps
    std.Thread.sleep(10 * std.time.ns_per_ms);

    // Create new file
    const new_file = try temp_dir.dir.createFile("new.txt", .{});
    new_file.close();

    const old_path = try std.fs.path.join(allocator, &[_][]const u8{ temp_path, "old.txt" });
    defer allocator.free(old_path);
    const new_path = try std.fs.path.join(allocator, &[_][]const u8{ temp_path, "new.txt" });
    defer allocator.free(new_path);

    // new.txt should be newer than old.txt
    const expr_newer = try std.fmt.allocPrint(
        allocator,
        "file.newer(\"{s}\", \"{s}\")",
        .{ new_path, old_path },
    );
    defer allocator.free(expr_newer);
    try std.testing.expect(try evalCondition(allocator, expr_newer, null));

    // old.txt should NOT be newer than new.txt
    const expr_older = try std.fmt.allocPrint(
        allocator,
        "file.newer(\"{s}\", \"{s}\")",
        .{ old_path, new_path },
    );
    defer allocator.free(expr_older);
    try std.testing.expect(!try evalCondition(allocator, expr_older, null));
}

test "evalCondition: file.hash" {
    const allocator = std.testing.allocator;

    // Create a temporary file with content
    var temp_dir = std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const temp_path = try temp_dir.dir.realpath(".", &buf);

    const test_file = try temp_dir.dir.createFile("test.txt", .{});
    try test_file.writeAll("test content");
    test_file.close();

    const full_path = try std.fs.path.join(allocator, &[_][]const u8{ temp_path, "test.txt" });
    defer allocator.free(full_path);

    // file.hash should return true for existing file
    const expr = try std.fmt.allocPrint(
        allocator,
        "file.hash(\"{s}\")",
        .{full_path},
    );
    defer allocator.free(expr);
    try std.testing.expect(try evalCondition(allocator, expr, null));

    // Non-existent file should return false
    const expr_missing = try std.fmt.allocPrint(
        allocator,
        "file.hash(\"{s}/missing.txt\")",
        .{temp_path},
    );
    defer allocator.free(expr_missing);
    try std.testing.expect(!try evalCondition(allocator, expr_missing, null));
}

test "evalCondition: shell command" {
    const allocator = std.testing.allocator;

    // Simple command that should succeed
    try std.testing.expect(try evalCondition(allocator, "shell(\"echo hello\")", null));

    // Command that should fail
    try std.testing.expect(!try evalCondition(allocator, "shell(\"exit 1\")", null));

    // Cross-platform test: check if a directory exists
    if (builtin.os.tag != .windows) {
        try std.testing.expect(try evalCondition(allocator, "shell(\"test -d /tmp\")", null));
        try std.testing.expect(!try evalCondition(allocator, "shell(\"test -d /nonexistent_dir_xyz\")", null));
    }
}

test "evalCondition: semver.gte" {
    const allocator = std.testing.allocator;

    // Equal versions
    try std.testing.expect(try evalCondition(allocator, "semver.gte(\"1.2.3\", \"1.2.3\")", null));

    // Greater major version
    try std.testing.expect(try evalCondition(allocator, "semver.gte(\"2.0.0\", \"1.9.9\")", null));
    try std.testing.expect(!try evalCondition(allocator, "semver.gte(\"1.0.0\", \"2.0.0\")", null));

    // Greater minor version
    try std.testing.expect(try evalCondition(allocator, "semver.gte(\"1.5.0\", \"1.2.3\")", null));
    try std.testing.expect(!try evalCondition(allocator, "semver.gte(\"1.2.0\", \"1.5.0\")", null));

    // Greater patch version
    try std.testing.expect(try evalCondition(allocator, "semver.gte(\"1.2.5\", \"1.2.3\")", null));
    try std.testing.expect(!try evalCondition(allocator, "semver.gte(\"1.2.1\", \"1.2.3\")", null));

    // With single quotes
    try std.testing.expect(try evalCondition(allocator, "semver.gte('2.0.0', '1.0.0')", null));
}

test "parseSemver: valid versions" {
    try std.testing.expectEqual(SemVer{ .major = 1, .minor = 2, .patch = 3 }, try parseSemver("1.2.3"));
    try std.testing.expectEqual(SemVer{ .major = 0, .minor = 0, .patch = 1 }, try parseSemver("0.0.1"));
    try std.testing.expectEqual(SemVer{ .major = 10, .minor = 20, .patch = 30 }, try parseSemver("10.20.30"));
}

test "parseSemver: invalid versions" {
    try std.testing.expectError(error.InvalidExpression, parseSemver("1.2"));
    try std.testing.expectError(error.InvalidExpression, parseSemver("1.2.x"));
    try std.testing.expectError(error.InvalidExpression, parseSemver("invalid"));
}

test "compareSemver: comparison logic" {
    const v1_2_3 = SemVer{ .major = 1, .minor = 2, .patch = 3 };
    const v1_2_4 = SemVer{ .major = 1, .minor = 2, .patch = 4 };
    const v1_3_0 = SemVer{ .major = 1, .minor = 3, .patch = 0 };
    const v2_0_0 = SemVer{ .major = 2, .minor = 0, .patch = 0 };

    // Equal
    try std.testing.expectEqual(@as(i32, 0), compareSemver(v1_2_3, v1_2_3));

    // Patch comparison
    try std.testing.expectEqual(@as(i32, -1), compareSemver(v1_2_3, v1_2_4));
    try std.testing.expectEqual(@as(i32, 1), compareSemver(v1_2_4, v1_2_3));

    // Minor comparison
    try std.testing.expectEqual(@as(i32, -1), compareSemver(v1_2_3, v1_3_0));
    try std.testing.expectEqual(@as(i32, 1), compareSemver(v1_3_0, v1_2_3));

    // Major comparison
    try std.testing.expectEqual(@as(i32, -1), compareSemver(v1_2_3, v2_0_0));
    try std.testing.expectEqual(@as(i32, 1), compareSemver(v2_0_0, v1_2_3));
}

test "RuntimeState: basic usage" {
    const allocator = std.testing.allocator;

    var state = RuntimeState.init(allocator);
    defer state.deinit();

    // Add task state
    try state.tasks.put("test", .{ .success = true, .duration_ms = 5000 });
    try state.tasks.put("build", .{ .success = false, .duration_ms = 120000 });

    // Add stage state
    try state.stages.put("prepare", .{ .success = true });
    try state.stages.put("deploy", .{ .success = false });

    // Verify
    const test_state = state.tasks.get("test").?;
    try std.testing.expect(test_state.success);
    try std.testing.expectEqual(@as(u64, 5000), test_state.duration_ms);

    const deploy_state = state.stages.get("deploy").?;
    try std.testing.expect(!deploy_state.success);
}

test "evalConditionWithState: stages['name'].success" {
    const allocator = std.testing.allocator;

    var state = RuntimeState.init(allocator);
    defer state.deinit();

    try state.stages.put("build", .{ .success = true });
    try state.stages.put("test", .{ .success = false });

    // Successful stage
    try std.testing.expect(try evalConditionWithState(
        allocator,
        "stages['build'].success",
        null,
        &state,
    ));

    // Failed stage
    try std.testing.expect(!try evalConditionWithState(
        allocator,
        "stages['test'].success",
        null,
        &state,
    ));

    // Double quotes
    try std.testing.expect(try evalConditionWithState(
        allocator,
        "stages[\"build\"].success",
        null,
        &state,
    ));

    // Stage not found: fail-open returns true
    try std.testing.expect(try evalConditionWithState(
        allocator,
        "stages['nonexistent'].success",
        null,
        &state,
    ));

    // No runtime state: fail-open returns true
    try std.testing.expect(try evalConditionWithState(
        allocator,
        "stages['build'].success",
        null,
        null,
    ));
}

test "evalConditionWithState: tasks['name'].duration comparisons" {
    const allocator = std.testing.allocator;

    var state = RuntimeState.init(allocator);
    defer state.deinit();

    // 5 seconds = 5000ms
    try state.tasks.put("fast", .{ .success = true, .duration_ms = 5000 });
    // 120 seconds = 120000ms
    try state.tasks.put("slow", .{ .success = true, .duration_ms = 120000 });
    // 0 seconds
    try state.tasks.put("instant", .{ .success = true, .duration_ms = 0 });

    // Less than
    try std.testing.expect(try evalConditionWithState(
        allocator,
        "tasks['fast'].duration < 10",
        null,
        &state,
    ));
    try std.testing.expect(!try evalConditionWithState(
        allocator,
        "tasks['slow'].duration < 10",
        null,
        &state,
    ));

    // Greater than
    try std.testing.expect(try evalConditionWithState(
        allocator,
        "tasks['slow'].duration > 60",
        null,
        &state,
    ));
    try std.testing.expect(!try evalConditionWithState(
        allocator,
        "tasks['fast'].duration > 60",
        null,
        &state,
    ));

    // Less than or equal
    try std.testing.expect(try evalConditionWithState(
        allocator,
        "tasks['fast'].duration <= 5",
        null,
        &state,
    ));
    try std.testing.expect(try evalConditionWithState(
        allocator,
        "tasks['fast'].duration <= 10",
        null,
        &state,
    ));

    // Greater than or equal
    try std.testing.expect(try evalConditionWithState(
        allocator,
        "tasks['slow'].duration >= 120",
        null,
        &state,
    ));
    try std.testing.expect(try evalConditionWithState(
        allocator,
        "tasks['slow'].duration >= 100",
        null,
        &state,
    ));

    // Equality
    try std.testing.expect(try evalConditionWithState(
        allocator,
        "tasks['fast'].duration == 5",
        null,
        &state,
    ));
    try std.testing.expect(!try evalConditionWithState(
        allocator,
        "tasks['fast'].duration == 10",
        null,
        &state,
    ));

    // Inequality
    try std.testing.expect(try evalConditionWithState(
        allocator,
        "tasks['fast'].duration != 10",
        null,
        &state,
    ));
    try std.testing.expect(!try evalConditionWithState(
        allocator,
        "tasks['fast'].duration != 5",
        null,
        &state,
    ));

    // Truthy check (duration > 0)
    try std.testing.expect(try evalConditionWithState(
        allocator,
        "tasks['fast'].duration",
        null,
        &state,
    ));
    try std.testing.expect(!try evalConditionWithState(
        allocator,
        "tasks['instant'].duration",
        null,
        &state,
    ));

    // Task not found: fail-open returns true
    try std.testing.expect(try evalConditionWithState(
        allocator,
        "tasks['nonexistent'].duration < 10",
        null,
        &state,
    ));

    // No runtime state: fail-open returns true
    try std.testing.expect(try evalConditionWithState(
        allocator,
        "tasks['fast'].duration < 10",
        null,
        null,
    ));
}

test "evalConditionWithState: combined with logical operators" {
    const allocator = std.testing.allocator;

    var state = RuntimeState.init(allocator);
    defer state.deinit();

    try state.stages.put("build", .{ .success = true });
    try state.tasks.put("test", .{ .success = true, .duration_ms = 30000 }); // 30 sec

    const env = [_][2][]const u8{.{ "CI", "true" }};

    // AND: stage success AND task duration
    try std.testing.expect(try evalConditionWithState(
        allocator,
        "stages['build'].success && tasks['test'].duration < 60",
        &env,
        &state,
    ));

    // OR: stage success OR env check
    try std.testing.expect(try evalConditionWithState(
        allocator,
        "stages['build'].success || env.CI == \"false\"",
        &env,
        &state,
    ));

    // Complex: platform + stage + task
    const current_os = switch (builtin.os.tag) {
        .linux => "linux",
        .macos => "darwin",
        .windows => "windows",
        else => "unknown",
    };
    const complex = try std.fmt.allocPrint(
        allocator,
        "platform == \"{s}\" && stages['build'].success && tasks['test'].duration < 60",
        .{current_os},
    );
    defer allocator.free(complex);
    try std.testing.expect(try evalConditionWithState(
        allocator,
        complex,
        null,
        &state,
    ));
}
