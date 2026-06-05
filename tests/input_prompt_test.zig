const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Integration Tests for Input Prompting Feature ───────────────────────────
//
// Tests for Interactive Task Input Prompting feature:
// When a task has `input_prompt` entries, values can be provided via:
// 1. --input KEY=VALUE CLI flag (overrides prompt/default)
// 2. --non-interactive mode (uses defaults or fails for required inputs)
// 3. Interactive prompt (in tty mode, asks user)
//
// Template substitution:
// - {{ENV}}, {{TAG}}, etc. in cmd/env fields receive input values
// - Priority: --input > --param > interactive prompt/default
//

test "18000: --input flag bypasses prompt and uses provided value" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.deploy]
        \\cmd = "echo {{ENV}}"
        \\input_prompt = [{name="ENV", prompt="Target environment:", default="staging"}]
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy", "--input", "ENV=prod", "--non-interactive" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "prod") != null);
}

test "18001: --non-interactive with required input (no default) fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.deploy]
        \\cmd = "echo {{ENV}}"
        \\input_prompt = [{name="ENV", prompt="Target environment (required):"}]
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try to run with --non-interactive but no --input (required input, no default)
    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy", "--non-interactive" }, tmp_path);
    defer result.deinit();

    // Should fail with non-zero exit code
    try std.testing.expect(result.exit_code != 0);

    // Error message should mention the input name or indicate missing input
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "ENV") != null or
        std.mem.indexOf(u8, combined, "required") != null or
        std.mem.indexOf(u8, combined, "input") != null);
}

test "18002: --non-interactive with default uses default value in substitution" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo Building {{TAG}}"
        \\input_prompt = [{name="TAG", prompt="Version tag:", default="v1.0.0"}]
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with --non-interactive (no --input provided, should use default)
    var result = try runZr(allocator, &.{ "--config", config, "run", "build", "--non-interactive" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "v1.0.0") != null);
}

test "18003: type=number validation rejects non-numeric values" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.measure]
        \\cmd = "echo {{COUNT}}"
        \\input_prompt = [{name="COUNT", prompt="Count:", type="number"}]
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try to provide non-numeric value with type=number
    var result = try runZr(allocator, &.{ "--config", config, "run", "measure", "--input", "COUNT=abc", "--non-interactive" }, tmp_path);
    defer result.deinit();

    // Should fail with validation error
    try std.testing.expect(result.exit_code != 0);

    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "COUNT") != null or
        std.mem.indexOf(u8, combined, "number") != null or
        std.mem.indexOf(u8, combined, "invalid") != null);
}

test "18004: choices validation rejects invalid choice" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.deploy]
        \\cmd = "echo {{ENV}}"
        \\input_prompt = [{name="ENV", prompt="Environment:", choices=["prod", "staging"]}]
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try to provide value not in choices list
    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy", "--input", "ENV=invalid", "--non-interactive" }, tmp_path);
    defer result.deinit();

    // Should fail with validation error
    try std.testing.expect(result.exit_code != 0);

    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "ENV") != null or
        std.mem.indexOf(u8, combined, "choice") != null or
        std.mem.indexOf(u8, combined, "invalid") != null);
}

test "18005: choices validation passes for valid choice" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.deploy]
        \\cmd = "echo {{ENV}}"
        \\input_prompt = [{name="ENV", prompt="Environment:", choices=["prod", "staging"]}]
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Provide valid choice from list
    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy", "--input", "ENV=prod", "--non-interactive" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "prod") != null);
}

test "18006: --input takes precedence over --param for same key" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo {{VERSION}}"
        \\input_prompt = [{name="VERSION", prompt="Version:", default="1.0.0"}]
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Provide both --input and --param; --input should win
    var result = try runZr(allocator, &.{ "--config", config, "run", "build", "--input", "VERSION=2.0.0", "--param", "VERSION=3.0.0", "--non-interactive" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show 2.0.0 from --input, not 3.0.0 from --param
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "2.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "3.0.0") == null);
}

test "18007: --dry-run shows input prompts with defaults" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.deploy]
        \\cmd = "deploy.sh"
        \\input_prompt = [{name="ENV", prompt="Target environment:", default="staging"}]
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy", "--dry-run" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    // Output should show input prompt name and default value
    try std.testing.expect(std.mem.indexOf(u8, combined, "ENV") != null);
    try std.testing.expect(std.mem.indexOf(u8, combined, "staging") != null);
}

test "18008: zr explain shows input_prompt section" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.deploy]
        \\cmd = "deploy.sh"
        \\input_prompt = [{name="ENV", prompt="Target environment:"}]
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Output should contain input prompt name and prompt text
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ENV") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Target environment") != null);
}

test "18009: zr explain --json includes input_prompts array" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.deploy]
        \\cmd = "deploy.sh"
        \\input_prompt = [{name="ENV", prompt="Environment:", default="staging"}]
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "explain", "deploy", "--json" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // JSON output should include input_prompts array
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "input_prompts") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ENV") != null);
}

test "18010: task with no input_prompt is unaffected (backward compat)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.simple]
        \\cmd = "echo hello"
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "simple" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hello") != null);
}

test "18011: multiple input_prompt entries all collected" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.multi]
        \\cmd = "echo {{ENV}} {{TAG}} {{REGION}}"
        \\input_prompt = [
        \\  {name="ENV", prompt="Environment:", default="dev"},
        \\  {name="TAG", prompt="Tag:", default="v1"},
        \\  {name="REGION", prompt="Region:", default="us-east-1"}
        \\]
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Provide some values, use defaults for others
    var result = try runZr(allocator, &.{
        "--config", config, "run", "multi",
        "--input", "ENV=prod",
        "--input", "TAG=v2.0",
        "--non-interactive",
    }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should have prod (provided), v2.0 (provided), and us-east-1 (default)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "prod") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "v2.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "us-east-1") != null);
}

test "18012: type=bool rejects non-bool value" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.toggle]
        \\cmd = "echo {{FLAG}}"
        \\input_prompt = [{name="FLAG", prompt="Enable feature?:", type="bool"}]
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try to provide non-bool value
    var result = try runZr(allocator, &.{ "--config", config, "run", "toggle", "--input", "FLAG=notabool", "--non-interactive" }, tmp_path);
    defer result.deinit();

    // Should fail with validation error
    try std.testing.expect(result.exit_code != 0);

    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "FLAG") != null or
        std.mem.indexOf(u8, combined, "bool") != null or
        std.mem.indexOf(u8, combined, "invalid") != null);
}
