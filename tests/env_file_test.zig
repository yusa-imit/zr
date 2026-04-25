const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── .env File Support for Individual Tasks ────────────────────────────────────
//
// These tests verify the Enhanced Environment Variable Management milestone:
// - Task-level env_file loading (distinct from global .env auto-loading)
// - env_file field in task config: env_file = ".env" or env_file = [".env.local", ".env"]
// - Priority order: task env > env_file > system env
// - Multiple .env files with override semantics (later files override earlier)
// - Basic .env file format: KEY=value, quoted values, comments, empty lines
// - Error handling: missing files, invalid format
// - Workspace inheritance: child tasks inherit parent env_file
//
// EXPECTED BEHAVIOR:
// - Single env_file: loads variables from specified file into task environment
// - Multiple env_files: loads all files in order, with later files overriding earlier
// - Task env takes precedence: task-specific env vars override env_file vars
// - System env fallback: variables not in task env or env_file come from system
// - Quoted values: "value with spaces" handled correctly
// - Comments: # lines and inline comments ignored
// - Empty lines: ignored without error
// - Missing file: error or warning (implementation-specific)
// - Invalid format: silently ignored or warned (implementation-specific)
// - Workspace inheritance: workspace env_file inherited by child tasks
//

test "env_file: single .env file loads into task environment" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env file
    const env_content =
        \\DB_HOST=localhost
        \\DB_PORT=5432
        \\DB_NAME=myapp
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task config with env_file
    const config_toml =
        \\[tasks.db-connect]
        \\cmd = "echo Connecting to $DB_HOST:$DB_PORT/$DB_NAME"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run task and verify env vars are loaded
    var result = try runZr(allocator, &.{ "--config", config, "run", "db-connect" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "localhost") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "5432") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "myapp") != null);
}

test "env_file: multiple .env files with override semantics" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env (base)
    const env_base =
        \\API_URL=https://api.example.com
        \\API_KEY=base_key
        \\LOG_LEVEL=info
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_base });

    // Create .env.local (override)
    const env_local =
        \\API_KEY=local_key_override
        \\DEBUG=true
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env.local", .data = env_local });

    // Create task with multiple env_files
    const config_toml =
        \\[tasks.api-test]
        \\cmd = "echo API_KEY=$API_KEY LOG_LEVEL=$LOG_LEVEL DEBUG=$DEBUG"
        \\env_file = [".env", ".env.local"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "api-test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Later file (.env.local) should override API_KEY
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "local_key_override") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "base_key") == null);
    // Variables unique to each file should both be present
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "info") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "true") != null);
}

test "env_file: task env overrides env_file values" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env file
    const env_content =
        \\MODE=development
        \\PORT=3000
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task with both env_file and inline env
    const config_toml =
        \\[tasks.start-server]
        \\cmd = "echo Mode=$MODE Port=$PORT"
        \\env_file = ".env"
        \\env = { MODE = "production" }
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "start-server" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Task env should override env_file
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "production") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "development") == null);
    // Non-overridden vars should still be present
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "3000") != null);
}

test "env_file: quoted values in .env file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env with quoted values
    const env_content =
        \\SIMPLE=no_quotes
        \\QUOTED="value with spaces"
        \\SINGLE='single quoted'
        \\MULTIWORD=first second third
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task to print values
    const config_toml =
        \\[tasks.show-vars]
        \\cmd = "echo Simple=$SIMPLE Quoted=$QUOTED Single=$SINGLE Multi=$MULTIWORD"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "show-vars" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "no_quotes") != null);
    // Quoted values should work (handling varies by implementation)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "spaces") != null or
                          std.mem.indexOf(u8, result.stdout, "quoted") != null);
}

test "env_file: comments and empty lines ignored" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env with comments and empty lines
    const env_content =
        \\# This is a comment
        \\VAR1=value1
        \\
        \\# Another comment
        \\VAR2=value2
        \\# VAR3=should_not_load (commented out)
        \\
        \\VAR4=value4
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task to verify loading
    const config_toml =
        \\[tasks.test-comments]
        \\cmd = "echo $VAR1 $VAR2 $VAR4"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "test-comments" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "value1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "value2") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "value4") != null);
    // Commented variables should not be loaded
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "should_not_load") == null);
}

test "env_file: env_file vars available in task command execution" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env with critical variables
    const env_content =
        \\JAVA_HOME=/usr/lib/jvm/java-17
        \\MAVEN_OPTS=-Xmx1024m
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task that depends on env vars
    const config_toml =
        \\[tasks.build]
        \\cmd = "echo Building with $JAVA_HOME and $MAVEN_OPTS"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "/usr/lib/jvm/java-17") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "-Xmx1024m") != null);
}

test "env_file: missing .env file returns error or graceful fallback" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create task with non-existent env_file
    const config_toml =
        \\[tasks.task]
        \\cmd = "echo test"
        \\env_file = ".env.missing"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run should fail or show warning
    var result = try runZr(allocator, &.{ "--config", config, "run", "task" }, tmp_path);
    defer result.deinit();

    // Should either fail (exit_code != 0) or show error in stderr
    const error_indicated = result.exit_code != 0 or
                           std.mem.indexOf(u8, result.stderr, "missing") != null or
                           std.mem.indexOf(u8, result.stderr, "not found") != null or
                           std.mem.indexOf(u8, result.stderr, "error") != null;
    try std.testing.expect(error_indicated);
}

test "env_file: relative path resolution for env_file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create subdirectory structure
    try tmp.dir.makeDir("configs");

    // Create .env in subdirectory
    const env_content =
        \\SUBDIR_VAR=from_subdir
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = "configs/.env", .data = env_content });

    // Create task with relative path to env file
    const config_toml =
        \\[tasks.test-subdir]
        \\cmd = "echo $SUBDIR_VAR"
        \\env_file = "configs/.env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "test-subdir" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "from_subdir") != null);
}

test "env_file: env_file with spaces and special characters in values" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env with special characters
    const env_content =
        \\MESSAGE=Hello World!
        \\PATH_VAR=/usr/bin:/usr/local/bin
        \\JSON_DATA={"key":"value"}
        \\URL=https://example.com:8080/api?key=123
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task to output values
    const config_toml =
        \\[tasks.special-chars]
        \\cmd = "echo MESSAGE=$MESSAGE PATH=$PATH_VAR URL=$URL"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "special-chars" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "/usr") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "example.com") != null);
}

test "env_file: workspace env_file inheritance by child tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env file for workspace
    const env_content =
        \\SHARED_VAR=shared_value
        \\WORKSPACE_VAR=workspace_specific
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create workspace with env_file, then child task
    const config_toml =
        \\env_file = ".env"
        \\
        \\[tasks.parent]
        \\cmd = "echo SHARED=$SHARED_VAR WORKSPACE=$WORKSPACE_VAR"
        \\
        \\[tasks.child]
        \\cmd = "echo SHARED=$SHARED_VAR WORKSPACE=$WORKSPACE_VAR"
        \\deps = ["parent"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "child" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Both parent and child should have access to workspace env_file vars
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "shared_value") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "workspace_specific") != null);
}

test "env_file: invalid .env file format returns error or is silently ignored" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env with invalid format
    const env_content =
        \\VALID_VAR=value
        \\INVALID LINE WITHOUT EQUALS
        \\ANOTHER_VALID=value2
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task
    const config_toml =
        \\[tasks.test-invalid]
        \\cmd = "echo $VALID_VAR $ANOTHER_VALID"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "test-invalid" }, tmp_path);
    defer result.deinit();

    // Should either fail with error or silently skip invalid lines and load valid ones
    if (result.exit_code == 0) {
        // Valid lines should have loaded
        try std.testing.expect(std.mem.indexOf(u8, result.stdout, "value") != null);
    } else {
        // Invalid format error is acceptable
        try std.testing.expect(std.mem.indexOf(u8, result.stderr, "invalid") != null or
                              std.mem.indexOf(u8, result.stderr, "error") != null or
                              std.mem.indexOf(u8, result.stderr, "malformed") != null);
    }
}

test "env_file: empty .env file handled gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create empty .env file
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = "" });

    // Create task with env_file
    const config_toml =
        \\[tasks.test-empty]
        \\cmd = "echo test"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "test-empty" }, tmp_path);
    defer result.deinit();

    // Empty file should not cause error
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
}

test "env_file: multiple overlapping env_files with same variables" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create base .env
    const env_base =
        \\DB_USER=admin
        \\DB_PASS=default_pass
        \\DB_HOST=localhost
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_base });

    // Create .env.development (overrides)
    const env_dev =
        \\DB_HOST=dev.example.com
        \\DEBUG=true
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env.development", .data = env_dev });

    // Create .env.local (final overrides)
    const env_local =
        \\DB_PASS=local_secret
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env.local", .data = env_local });

    // Task with multiple env_files in specific order
    const config_toml =
        \\[tasks.multi-override]
        \\cmd = "echo USER=$DB_USER PASS=$DB_PASS HOST=$DB_HOST DEBUG=$DEBUG"
        \\env_file = [".env", ".env.development", ".env.local"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "multi-override" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Each variable should have the value from the last file that defines it
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "USER=admin") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "PASS=local_secret") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "HOST=dev.example.com") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "DEBUG=true") != null);
}
