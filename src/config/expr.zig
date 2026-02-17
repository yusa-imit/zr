const std = @import("std");

pub const EvalError = error{OutOfMemory};

/// Evaluate a condition expression string.
/// `task_env` contains per-task env overrides (checked first before process env).
/// Returns true if the condition passes (task should run), false if skipped.
/// On parse error or unknown expression, returns true (fail-open: run the task).
pub fn evalCondition(
    allocator: std.mem.Allocator,
    expr: []const u8,
    task_env: ?[]const [2][]const u8,
) EvalError!bool {
    const trimmed = std.mem.trim(u8, expr, " \t\r\n");

    // Literal booleans
    if (std.mem.eql(u8, trimmed, "true")) return true;
    if (std.mem.eql(u8, trimmed, "false")) return false;

    // env.VAR_NAME [operator "value"]
    if (!std.mem.startsWith(u8, trimmed, "env.")) {
        // Unknown expression: fail-open
        return true;
    }

    // Extract variable name: chars up to space, '=', '!', or end of string
    const after_prefix = trimmed["env.".len..];
    const var_name_end = blk: {
        for (after_prefix, 0..) |c, i| {
            if (c == ' ' or c == '\t' or c == '=' or c == '!') break :blk i;
        }
        break :blk after_prefix.len;
    };

    if (var_name_end == 0) {
        // "env." with no variable name — fail-open
        return true;
    }

    const var_name = after_prefix[0..var_name_end];
    const rest = std.mem.trim(u8, after_prefix[var_name_end..], " \t");

    // Look up the env value (task_env first, then process env)
    const env_value = try lookupEnv(allocator, var_name, task_env);
    defer if (env_value) |v| allocator.free(v);

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

    // Unrecognized operator: fail-open
    return true;
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
