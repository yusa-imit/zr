const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Task Argument Passthrough Tests ────────────────────────────────────────
//
// Tests for `zr run <task> -- <raw args...>` feature (Task Argument Passthrough):
//
// The `--` separator terminates zr's own flag/param parsing and passes all
// remaining arguments through to the task as an environment variable ZR_ARGS.
// Args are shell-quoted (each arg wrapped in single quotes, with internal '
// replaced by '\''). The quoted args are space-joined into a single string.
//
// 42000: Basic passthrough — `zr run <task> -- --flag value` injects ZR_ARGS
// 42001: No `--` present — ZR_ARGS unset, task behaves normally
// 42002: `--` with nothing after — ZR_ARGS set to empty string
// 42003: Args with spaces get shell-quoted correctly (survive as one word)
// 42004: `--` combined with task param before it (param + ZR_ARGS both work)
// 42005: `--` combined with `--env KEY=value` before it (both env vars work)
//

// Test 42000: Basic passthrough — `zr run <task> -- --flag value` injects ZR_ARGS
test "task_args: basic passthrough with -- separator" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task that echoes ZR_ARGS to verify it was set
    const toml =
        \\[tasks.echo-args]
        \\cmd = "echo ZR_ARGS=$ZR_ARGS"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    // Run: zr run echo-args -- --verbose --dry-run
    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "echo-args", "--", "--verbose", "--dry-run" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Expect output contains the shell-quoted args: '--verbose' '--dry-run'
    try testing.expect(std.mem.indexOf(u8, combined, "'--verbose'") != null);
    try testing.expect(std.mem.indexOf(u8, combined, "'--dry-run'") != null);
}

// Test 42001: No `--` present — ZR_ARGS unset, task behaves normally
test "task_args: without -- separator, ZR_ARGS is unset" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task that tries to reference ZR_ARGS
    const toml =
        \\[tasks.check-args]
        \\cmd = "sh -c 'if [ -z \"$ZR_ARGS\" ]; then echo UNSET; else echo SET_TO:$ZR_ARGS; fi'"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    // Run WITHOUT --: zr run check-args
    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "check-args" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Expect output indicates ZR_ARGS is UNSET
    try testing.expect(std.mem.indexOf(u8, combined, "UNSET") != null);
}

// Test 42002: `--` with nothing after — ZR_ARGS set to empty string
test "task_args: -- with no args after it sets ZR_ARGS to empty string" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task that checks if ZR_ARGS is explicitly empty (vs unset)
    const toml =
        \\[tasks.check-empty]
        \\cmd = "sh -c 'if [ -z \"$ZR_ARGS\" ]; then if [ \"${ZR_ARGS+x}\" = \"x\" ]; then echo EMPTY; else echo UNSET; fi; else echo NONEMPTY; fi'"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    // Run with trailing --: zr run check-empty --
    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "check-empty", "--" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Expect output indicates ZR_ARGS is explicitly EMPTY (not UNSET)
    try testing.expect(std.mem.indexOf(u8, combined, "EMPTY") != null);
}

// Test 42003: Args with spaces get shell-quoted correctly (survive as one word)
test "task_args: arguments with spaces are shell-quoted correctly" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task that re-parses ZR_ARGS via `eval "set -- $ZR_ARGS"` — this is the
    // pattern real tasks use to reconstruct argv from the quoted string. Only
    // `eval` re-tokenizes and strips the quotes; a plain unquoted expansion
    // would just word-split on the literal quote characters.
    const toml =
        \\[tasks.count-words]
        \\cmd = "sh -c 'eval \"set -- $ZR_ARGS\"; echo COUNT=$#; echo FIRST=[$1]'"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    // Run: zr run count-words -- "hello world" --flag
    // Expected: ZR_ARGS="'hello world' '--flag'" (2 quoted args, joined with space)
    // After eval re-parses it, "hello world" survives as a single positional arg.
    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "count-words", "--", "hello world", "--flag" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Verify exactly 2 args were reconstructed, and "hello world" stayed as one word
    try testing.expect(std.mem.indexOf(u8, combined, "COUNT=2") != null);
    try testing.expect(std.mem.indexOf(u8, combined, "FIRST=[hello world]") != null);
}

// Test 42004: `--` combined with task param before it (param + ZR_ARGS both work)
test "task_args: -- with task param before it applies both param and ZR_ARGS" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task with declared param, also echoes ZR_ARGS
    const toml =
        \\[tasks.deploy]
        \\cmd = "sh -c 'echo ENV={{env_name}} && echo ARGS=$ZR_ARGS'"
        \\params = [ { name = "env_name", default = "staging" } ]
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    // Run: zr run deploy env_name=prod -- --verbose
    // Expect: param env_name=prod is substituted, AND ZR_ARGS contains '--verbose'
    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "deploy", "env_name=prod", "--", "--verbose" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Verify both param substitution and ZR_ARGS are present
    try testing.expect(std.mem.indexOf(u8, combined, "ENV=prod") != null);
    try testing.expect(std.mem.indexOf(u8, combined, "'--verbose'") != null);
}

// Test 42005: `--` combined with `--env KEY=value` before it (both env vars work)
test "task_args: -- with --env before it applies both env injections" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Task that uses two environment variables
    const toml =
        \\[tasks.run-with-env]
        \\cmd = "sh -c 'echo CUSTOM_VAR=$CUSTOM_VAR && echo ARGS=$ZR_ARGS'"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    // Run: zr run run-with-env --env CUSTOM_VAR=hello -- --flag
    // Expect: CUSTOM_VAR injected AND ZR_ARGS contains '--flag'
    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "run-with-env", "--env", "CUSTOM_VAR=hello", "--", "--flag" }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const combined = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer testing.allocator.free(combined);

    // Verify both env injections are present
    try testing.expect(std.mem.indexOf(u8, combined, "CUSTOM_VAR=hello") != null);
    try testing.expect(std.mem.indexOf(u8, combined, "'--flag'") != null);
}
