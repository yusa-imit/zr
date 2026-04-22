const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ────────────────────────────────────────────────────────────────────────────
// Test 1: Basic param with default value
// ────────────────────────────────────────────────────────────────────────────

test "task params: basic param with default value" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.deploy]
        \\cmd = "echo Deploying to {{env}}"
        \\params = [
        \\  { name = "env", default = "dev", description = "Target environment" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run without providing param → should use default "dev"
    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Deploying to dev") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 2: Required param (no default) fails if not provided
// ────────────────────────────────────────────────────────────────────────────

test "task params: required param fails without value" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.deploy]
        \\cmd = "echo Deploying to {{env}}"
        \\params = [
        \\  { name = "env", description = "Target environment (required)" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run without required param → should fail with error
    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0); // Expect failure
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "required") != null or
        std.mem.indexOf(u8, combined, "missing") != null or
        std.mem.indexOf(u8, combined, "env") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 3: Multiple params with mix of required/optional
// ────────────────────────────────────────────────────────────────────────────

test "task params: multiple params mixed required and optional" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.deploy]
        \\cmd = "echo Deploying to {{env}} in {{region}}"
        \\params = [
        \\  { name = "env", description = "Environment (required)" },
        \\  { name = "region", default = "us-east-1", description = "AWS region" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Provide only required param → optional uses default
    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy", "env=prod" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Deploying to prod in us-east-1") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 4: Positional param syntax
// ────────────────────────────────────────────────────────────────────────────

test "task params: positional arguments" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.greet]
        \\cmd = "echo Hello {{name}} from {{city}}"
        \\params = [
        \\  { name = "name", default = "World" },
        \\  { name = "city", default = "Earth" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Positional syntax: zr run greet Alice London
    var result = try runZr(allocator, &.{ "--config", config, "run", "greet", "Alice", "London" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Hello Alice from London") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 5: Named param syntax (key=value)
// ────────────────────────────────────────────────────────────────────────────

test "task params: named key=value syntax" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.deploy]
        \\cmd = "echo Deploy {{app}} version {{version}}"
        \\params = [
        \\  { name = "app", default = "web" },
        \\  { name = "version", default = "1.0.0" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Named syntax: version=2.0 app=api
    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy", "version=2.0", "app=api" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Deploy api version 2.0") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 6: --param flag syntax
// ────────────────────────────────────────────────────────────────────────────

test "task params: --param flag syntax" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.deploy]
        \\cmd = "echo Deploying to {{env}}"
        \\params = [
        \\  { name = "env", default = "dev" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // --param syntax: zr run deploy --param env=staging
    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy", "--param", "env=staging" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Deploying to staging") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 7: Mixed positional and named params
// ────────────────────────────────────────────────────────────────────────────

test "task params: mixed positional and named syntax" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.build]
        \\cmd = "echo Building {{target}} mode={{mode}} cores={{cores}}"
        \\params = [
        \\  { name = "target", default = "app" },
        \\  { name = "mode", default = "debug" },
        \\  { name = "cores", default = "4" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Mixed: positional "lib" + named "cores=8"
    var result = try runZr(allocator, &.{ "--config", config, "run", "build", "lib", "cores=8" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Building lib") != null);
    try std.testing.expect(std.mem.indexOf(u8, combined, "cores=8") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 8: Type validation - string (basic)
// ────────────────────────────────────────────────────────────────────────────

test "task params: type validation string" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.deploy]
        \\cmd = "echo Environment: {{env}}"
        \\params = [
        \\  { name = "env", type = "string", default = "dev" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy", "env=production" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Environment: production") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 9: {{param}} interpolation in cmd field
// ────────────────────────────────────────────────────────────────────────────

test "task params: interpolation in cmd field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.test]
        \\cmd = "echo Running tests with pattern={{pattern}} verbose={{verbose}}"
        \\params = [
        \\  { name = "pattern", default = "*" },
        \\  { name = "verbose", default = "false" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "test", "pattern=unit*", "verbose=true" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "pattern=unit*") != null);
    try std.testing.expect(std.mem.indexOf(u8, combined, "verbose=true") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 10: {{param}} interpolation in env field
// ────────────────────────────────────────────────────────────────────────────

test "task params: interpolation in env field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.serve]
        \\cmd = "echo PORT=$PORT HOST=$HOST"
        \\env = { PORT = "{{port}}", HOST = "{{host}}" }
        \\params = [
        \\  { name = "port", default = "3000" },
        \\  { name = "host", default = "localhost" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "serve", "port=8080", "host=0.0.0.0" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "PORT=8080") != null);
    try std.testing.expect(std.mem.indexOf(u8, combined, "HOST=0.0.0.0") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 11: Help display shows params
// ────────────────────────────────────────────────────────────────────────────

test "task params: --help shows available params" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.deploy]
        \\description = "Deploy application"
        \\cmd = "echo deploying"
        \\params = [
        \\  { name = "env", default = "dev", description = "Target environment" },
        \\  { name = "region", default = "us-east-1", description = "AWS region" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy", "--help" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    // Check params are displayed in help
    try std.testing.expect(std.mem.indexOf(u8, combined, "env") != null);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Target environment") != null);
    try std.testing.expect(std.mem.indexOf(u8, combined, "region") != null);
    try std.testing.expect(std.mem.indexOf(u8, combined, "default") != null or
        std.mem.indexOf(u8, combined, "dev") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 12: List display shows params
// ────────────────────────────────────────────────────────────────────────────

test "task params: list command shows task params" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.deploy]
        \\cmd = "echo deploying"
        \\params = [
        \\  { name = "env", default = "dev" },
        \\  { name = "region", default = "us-east-1" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Check list output shows params (e.g., "deploy(env="dev", region="us-east-1")")
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "deploy") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "env") != null or
        std.mem.indexOf(u8, result.stdout, "params") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 13: History tracking records actual params
// ────────────────────────────────────────────────────────────────────────────

test "task params: history records actual param values" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.deploy]
        \\cmd = "echo Deploying to {{env}}"
        \\params = [
        \\  { name = "env", default = "dev" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with param
    var result1 = try runZr(allocator, &.{ "--config", config, "run", "deploy", "env=production" }, tmp_path);
    defer result1.deinit();

    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);

    // Check history shows the param
    var result2 = try runZr(allocator, &.{ "--config", config, "history", "--limit", "1" }, tmp_path);
    defer result2.deinit();

    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result2.stdout, result2.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "env") != null or
        std.mem.indexOf(u8, combined, "production") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 14: Workflow param passing
// ────────────────────────────────────────────────────────────────────────────

test "task params: workflow passes params to tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.deploy]
        \\cmd = "echo Deploying to {{env}}"
        \\params = [
        \\  { name = "env", default = "dev" }
        \\]
        \\
        \\[workflows.release]
        \\tasks = [
        \\  { name = "deploy", params = { env = "production" } }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "workflow", "release" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Deploying to production") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 15: Error - unknown param provided
// ────────────────────────────────────────────────────────────────────────────

test "task params: error on unknown param" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.deploy]
        \\cmd = "echo deploying"
        \\params = [
        \\  { name = "env", default = "dev" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Provide unknown param "unknown"
    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy", "unknown=value" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "unknown") != null or
        std.mem.indexOf(u8, combined, "not defined") != null or
        std.mem.indexOf(u8, combined, "invalid") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 16: Param override - CLI > default
// ────────────────────────────────────────────────────────────────────────────

test "task params: CLI override beats default" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.build]
        \\cmd = "echo Mode: {{mode}}"
        \\params = [
        \\  { name = "mode", default = "debug" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // CLI provides mode=release → overrides default "debug"
    var result = try runZr(allocator, &.{ "--config", config, "run", "build", "mode=release" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Mode: release") != null);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Mode: debug") == null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 17: Empty params array (backward compat)
// ────────────────────────────────────────────────────────────────────────────

test "task params: empty params array backward compatible" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.build]
        \\cmd = "echo Building"
        \\params = []
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Building") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 18: Param with spaces in value
// ────────────────────────────────────────────────────────────────────────────

test "task params: param value with spaces" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.commit]
        \\cmd = "echo Commit message: {{message}}"
        \\params = [
        \\  { name = "message", default = "default commit" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "commit", "message=feat: add new feature" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Commit message: feat: add new feature") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 19: Boolean param type
// ────────────────────────────────────────────────────────────────────────────

test "task params: boolean param type" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.test]
        \\cmd = "echo Debug mode: {{debug}}"
        \\params = [
        \\  { name = "debug", type = "bool", default = "false" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "test", "debug=true" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Debug mode: true") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 20: Number param type
// ────────────────────────────────────────────────────────────────────────────

test "task params: number param type" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.bench]
        \\cmd = "echo Running benchmark iterations={{iterations}}"
        \\params = [
        \\  { name = "iterations", type = "number", default = "100" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "bench", "iterations=1000" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "iterations=1000") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 21: Type mismatch error
// ────────────────────────────────────────────────────────────────────────────

test "task params: type mismatch error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.bench]
        \\cmd = "echo Running"
        \\params = [
        \\  { name = "iterations", type = "number", default = "100" }
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Provide non-number value to number param
    var result = try runZr(allocator, &.{ "--config", config, "run", "bench", "iterations=not-a-number" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "type") != null or
        std.mem.indexOf(u8, combined, "number") != null or
        std.mem.indexOf(u8, combined, "invalid") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 22: Task without params field (backward compat)
// ────────────────────────────────────────────────────────────────────────────

test "task params: no params field backward compatible" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params_toml =
        \\[tasks.build]
        \\cmd = "echo Building"
        \\description = "Build project"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, params_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);
    try std.testing.expect(std.mem.indexOf(u8, combined, "Building") != null);
}
