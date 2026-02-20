const std = @import("std");
const builtin = @import("builtin");

pub const EvalError = error{ OutOfMemory, InvalidExpression };

const ExprContext = struct {
    allocator: std.mem.Allocator,
    task_env: ?[]const [2][]const u8,
};

/// Evaluate a condition expression string.
/// `task_env` contains per-task env overrides (checked first before process env).
/// Returns true if the condition passes (task should run), false if skipped.
/// On parse error or unknown expression, returns true (fail-open: run the task).
pub fn evalCondition(
    allocator: std.mem.Allocator,
    expr: []const u8,
    task_env: ?[]const [2][]const u8,
) EvalError!bool {
    const ctx = ExprContext{
        .allocator = allocator,
        .task_env = task_env,
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

    // Environment variable check
    if (std.mem.startsWith(u8, trimmed, "env.")) {
        return evalEnvCheck(ctx, trimmed);
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
