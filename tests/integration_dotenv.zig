const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;
const writeTmpConfigPath = helpers.writeTmpConfigPath;

// ── .env File Auto-Loading & Variable Substitution Tests ────────────────────
//
// These tests verify the v1.55.0 features:
// - .env file auto-loading from project root
// - Variable substitution (${VAR} expansion) in TOML values
//
// EXPECTED BEHAVIOR:
// - .env file parsed and merged into all task environments
// - Task-specific env takes precedence over .env values
// - ${VAR} syntax expanded in cmd, cwd, env values using task env + .env
// - load_dotenv = false disables .env loading
// - Missing .env file is silently ignored
// - Malformed .env file is silently ignored
//

test "dotenv: basic .env file loaded into task environment" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env file
    const dotenv_content =
        \\MY_VAR=from_dotenv
        \\OTHER_VAR=hello_world
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = dotenv_content });

    // Create config with task that uses env vars
    const config_toml =
        \\[tasks.print]
        \\cmd = "echo $MY_VAR $OTHER_VAR"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Show task - should include .env variables in environment
    var result = try runZr(allocator, &.{ "--config", config, "show", "print" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // .env variables should be in task environment
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "from_dotenv") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hello_world") != null);
}

test "dotenv: task-specific env overrides .env values" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env file
    const dotenv_content =
        \\MY_VAR=from_dotenv
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = dotenv_content });

    // Create config with task that overrides MY_VAR
    const config_toml =
        \\[tasks.override]
        \\cmd = "echo $MY_VAR"
        \\env = { MY_VAR = "from_task" }
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Show task - task env should override .env
    var result = try runZr(allocator, &.{ "--config", config, "show", "override" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Task-specific value takes precedence
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "from_task") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "from_dotenv") == null);
}

test "dotenv: load_dotenv = false disables .env loading" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env file
    const dotenv_content =
        \\MY_VAR=from_dotenv
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = dotenv_content });

    // Create config with load_dotenv disabled
    const config_toml =
        \\load_dotenv = false
        \\
        \\[tasks.no_env]
        \\cmd = "echo $MY_VAR"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Show task - .env variables should NOT be present
    var result = try runZr(allocator, &.{ "--config", config, "show", "no_env" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // .env value should not be loaded
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "from_dotenv") == null);
}

test "dotenv: missing .env file silently ignored" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // No .env file created

    // Create config (should not fail)
    const config_toml =
        \\[tasks.task]
        \\cmd = "echo hi"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // List tasks - should succeed even without .env
    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task") != null);
}

test "dotenv: malformed .env file silently ignored" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create malformed .env file
    const dotenv_content =
        \\INVALID LINE WITHOUT EQUALS
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = dotenv_content });

    // Create config (should not fail)
    const config_toml =
        \\[tasks.task]
        \\cmd = "echo hi"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // List tasks - should succeed even with malformed .env
    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "varsubst: basic variable substitution in cmd" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env file
    const dotenv_content =
        \\PROJECT=myapp
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = dotenv_content });

    // Create config with ${VAR} in cmd
    const config_toml =
        \\[tasks.build]
        \\cmd = "echo Building ${PROJECT}"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Show task - ${PROJECT} should be expanded
    var result = try runZr(allocator, &.{ "--config", config, "show", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Variable should be expanded in cmd
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Building myapp") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "${PROJECT}") == null);
}

test "varsubst: variable substitution in cwd" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env file
    const dotenv_content =
        \\WORKDIR=/tmp/work
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = dotenv_content });

    // Create config with ${VAR} in cwd
    const config_toml =
        \\[tasks.task]
        \\cmd = "pwd"
        \\cwd = "${WORKDIR}/subdir"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Show task - ${WORKDIR} should be expanded in cwd
    var result = try runZr(allocator, &.{ "--config", config, "show", "task" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Variable should be expanded in cwd
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "/tmp/work/subdir") != null);
}

test "varsubst: variable substitution in env values" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env file
    const dotenv_content =
        \\BASE_PATH=/usr/local
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = dotenv_content });

    // Create config with ${VAR} in env value
    const config_toml =
        \\[tasks.task]
        \\cmd = "echo $FULL_PATH"
        \\env = { FULL_PATH = "${BASE_PATH}/bin" }
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Show task - ${BASE_PATH} should be expanded in env value
    var result = try runZr(allocator, &.{ "--config", config, "show", "task" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Variable should be expanded in env value
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "/usr/local/bin") != null);
}

test "varsubst: multiple variables in one string" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env file
    const dotenv_content =
        \\USER=alice
        \\HOST=localhost
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = dotenv_content });

    // Create config with multiple ${VAR} in cmd
    const config_toml =
        \\[tasks.ssh]
        \\cmd = "ssh ${USER}@${HOST}"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Show task - both variables should be expanded
    var result = try runZr(allocator, &.{ "--config", config, "show", "ssh" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Both variables should be expanded
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ssh alice@localhost") != null);
}

test "varsubst: undefined variable expands to empty string" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // No .env file with NONEXISTENT var

    // Create config with undefined ${VAR}
    const config_toml =
        \\[tasks.task]
        \\cmd = "echo prefix_${NONEXISTENT}_suffix"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Show task - undefined var should expand to empty string
    var result = try runZr(allocator, &.{ "--config", config, "show", "task" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Undefined variable should expand to empty string
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "prefix__suffix") != null);
}

test "varsubst: escaped dollar sign not expanded" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env file
    const dotenv_content =
        \\VAR=value
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = dotenv_content });

    // Create config with escaped ${VAR}
    const config_toml =
        \\[tasks.task]
        \\cmd = "echo \\${VAR}"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Show task - escaped ${VAR} should remain as literal
    var result = try runZr(allocator, &.{ "--config", config, "show", "task" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Escaped variable should not be expanded
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "${VAR}") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "value") == null);
}

test "dotenv+varsubst: .env and variable substitution work together" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env file with BASE_URL
    const dotenv_content =
        \\BASE_URL=https://api.example.com
        \\API_KEY=secret123
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = dotenv_content });

    // Create config that uses ${BASE_URL} from .env
    const config_toml =
        \\[tasks.api]
        \\cmd = "curl ${BASE_URL}/endpoint"
        \\env = { FULL_URL = "${BASE_URL}/v1" }
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Show task - variables from .env should be expanded
    var result = try runZr(allocator, &.{ "--config", config, "show", "api" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // .env variable should be expanded in both cmd and env
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "https://api.example.com/endpoint") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "https://api.example.com/v1") != null);
}

test "dotenv+varsubst: task env overrides .env for substitution" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env file
    const dotenv_content =
        \\PREFIX=from_dotenv
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = dotenv_content });

    // Create config where task env overrides PREFIX, then uses it in cmd
    const config_toml =
        \\[tasks.task]
        \\cmd = "echo ${PREFIX}"
        \\env = { PREFIX = "from_task" }
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Show task - ${PREFIX} should use task env value, not .env
    var result = try runZr(allocator, &.{ "--config", config, "show", "task" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Task env value should be used for substitution
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "echo from_task") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "from_dotenv") == null);
}

test "dotenv: comments and empty lines in .env file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env file with comments and empty lines
    const dotenv_content =
        \\# This is a comment
        \\
        \\MY_VAR=value1
        \\# Another comment
        \\OTHER_VAR=value2
        \\
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = dotenv_content });

    // Create config
    const config_toml =
        \\[tasks.task]
        \\cmd = "echo $MY_VAR $OTHER_VAR"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Show task - should load variables correctly
    var result = try runZr(allocator, &.{ "--config", config, "show", "task" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Both variables should be loaded despite comments/empty lines
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "value1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "value2") != null);
}

test "dotenv: quoted values in .env file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env file with quoted values
    const dotenv_content =
        \\SINGLE='single quoted value'
        \\DOUBLE="double quoted value"
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = dotenv_content });

    // Create config
    const config_toml =
        \\[tasks.task]
        \\cmd = "echo $SINGLE $DOUBLE"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Show task - quoted values should be loaded
    var result = try runZr(allocator, &.{ "--config", config, "show", "task" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Quoted values should be loaded (quotes stripped by parser)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "single quoted value") != null or
        std.mem.indexOf(u8, result.stdout, "single") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "double quoted value") != null or
        std.mem.indexOf(u8, result.stdout, "double") != null);
}
