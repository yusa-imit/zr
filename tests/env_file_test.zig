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

// ── Variable Interpolation in .env Files ────────────────────────────────────
//
// Tests for variable expansion in .env file values.
// Supports: ${VAR}, $VAR, $$ escape, recursive expansion, circular detection
//
// EXPECTED BEHAVIOR:
// - ${VAR} syntax: expands VAR reference in braces
// - $VAR syntax: expands VAR without braces (alphanumeric + underscore only)
// - $$ escape: expands to literal $ character
// - Recursive: VAR1=${VAR2}, VAR2=value => VAR1 expands to value
// - Circular detection: VAR1=${VAR2}, VAR2=${VAR1} => error or warning
// - Undefined: ${UNDEFINED} => preserved as-is (not expanded)
// - Mixed: PATH=/usr/bin:${OLD_PATH} => interpolates OLD_PATH only
//

test "interpolation: basic ${VAR} expansion in .env file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env with variable reference
    const env_content =
        \\NAME=World
        \\GREETING=Hello ${NAME}
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task to use interpolated value
    const config_toml =
        \\[tasks.greeting]
        \\cmd = "echo $GREETING"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "greeting" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Hello World") != null);
}

test "interpolation: simple $VAR expansion (no braces)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env with simple variable reference
    const env_content =
        \\HOME=/home/alice
        \\PATH_VAR=$HOME/bin
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task
    const config_toml =
        \\[tasks.show-path]
        \\cmd = "echo $PATH_VAR"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "show-path" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "/home/alice/bin") != null);
}

test "interpolation: $$ escape to literal dollar sign" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env with $$ escape
    const env_content =
        \\PRICE=100
        \\COST=Price is $$${PRICE}
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task
    const config_toml =
        \\[tasks.cost]
        \\cmd = "echo $COST"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "cost" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Price is $100") != null);
}

test "interpolation: recursive expansion (VAR1=${VAR2}, VAR2=value)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env with nested variable references
    const env_content =
        \\BASE_URL=https://api.example.com
        \\API_URL=${BASE_URL}/v1
        \\ENDPOINT=${API_URL}/users
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task
    const config_toml =
        \\[tasks.api-call]
        \\cmd = "echo $ENDPOINT"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "api-call" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "https://api.example.com/v1/users") != null);
}

test "interpolation: cross-file expansion (var in .env.local references var in .env)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create base .env
    const env_base =
        \\DB_HOST=localhost
        \\DB_PORT=5432
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_base });

    // Create .env.local that references base vars
    const env_local =
        \\DB_URL=postgresql://${DB_HOST}:${DB_PORT}/mydb
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env.local", .data = env_local });

    // Create task with multiple env_files
    const config_toml =
        \\[tasks.db-connect]
        \\cmd = "echo $DB_URL"
        \\env_file = [".env", ".env.local"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "db-connect" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "postgresql://localhost:5432/mydb") != null);
}

test "interpolation: circular reference detection (VAR1=${VAR2}, VAR2=${VAR1})" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env with circular reference
    const env_content =
        \\CIRCULAR_A=${CIRCULAR_B}
        \\CIRCULAR_B=${CIRCULAR_A}
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task that uses circular var
    const config_toml =
        \\[tasks.circular]
        \\cmd = "echo $CIRCULAR_A"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "circular" }, tmp_path);
    defer result.deinit();

    // Should fail due to circular reference
    try std.testing.expect(result.exit_code != 0);
}

test "interpolation: undefined variable expansion (${UNDEFINED} stays as-is)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env with reference to undefined var
    const env_content =
        \\DEFINED=value
        \\WITH_UNDEFINED=Defined: ${DEFINED}, Undefined: ${MISSING}
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task
    const config_toml =
        \\[tasks.show-vars]
        \\cmd = "echo $WITH_UNDEFINED"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "show-vars" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Defined variable should be expanded, undefined should stay as-is
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Defined: value") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Undefined: ${MISSING}") != null);
}

test "interpolation: mixed interpolation and literals (PATH=/usr/bin:${OLD_PATH})" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env with mixed content
    const env_content =
        \\OLD_PATH=/opt/bin:/usr/local/bin
        \\NEW_PATH=/usr/bin:${OLD_PATH}:/custom/bin
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task
    const config_toml =
        \\[tasks.path-test]
        \\cmd = "echo $NEW_PATH"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "path-test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "/usr/bin:/opt/bin:/usr/local/bin:/custom/bin") != null);
}

test "interpolation: multiple variables in single value" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env with multiple vars in one value
    const env_content =
        \\FIRST=hello
        \\SECOND=world
        \\GREETING=${FIRST}-${SECOND}!
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task
    const config_toml =
        \\[tasks.multi-var]
        \\cmd = "echo $GREETING"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "multi-var" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hello-world!") != null);
}

test "interpolation: variable with underscores and numbers in name" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env with complex variable names
    const env_content =
        \\DB_HOST_1=host1.example.com
        \\DB_PORT_1=5432
        \\CONN_STRING=db://${DB_HOST_1}:${DB_PORT_1}
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task
    const config_toml =
        \\[tasks.conn]
        \\cmd = "echo $CONN_STRING"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "conn" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "db://host1.example.com:5432") != null);
}

test "interpolation: task env overrides interpolated env_file values" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env with interpolated vars
    const env_content =
        \\BASE=/opt
        \\FULL_PATH=${BASE}/app
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task that overrides BASE env var (which should change FULL_PATH expansion)
    const config_toml =
        \\[tasks.override-test]
        \\cmd = "echo $FULL_PATH"
        \\env_file = ".env"
        \\env = { BASE = "/home/custom" }
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "override-test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Task env should override, so BASE becomes /home/custom
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "/home/custom/app") != null);
}

test "interpolation: empty variable value in interpolation" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env with empty variable
    const env_content =
        \\EMPTY=
        \\MESSAGE=Start${EMPTY}End
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task
    const config_toml =
        \\[tasks.empty-var]
        \\cmd = "echo $MESSAGE"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "empty-var" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Empty variable should result in adjacent text: StartEnd
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "StartEnd") != null);
}

test "interpolation: escape sequence prevents variable expansion" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env where $$ prevents expansion
    const env_content =
        \\PRICE=100
        \\ESCAPED=Cost: $${PRICE}
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task
    const config_toml =
        \\[tasks.escape-test]
        \\cmd = "echo $ESCAPED"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "escape-test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // $$ becomes single $, so ${PRICE} stays literal (not expanded)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Cost: ${PRICE}") != null);
}

test "interpolation: three-level recursive expansion" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create .env with three levels of nesting
    const env_content =
        \\LEVEL3=final_value
        \\LEVEL2=${LEVEL3}
        \\LEVEL1=${LEVEL2}
        \\MESSAGE=Result: ${LEVEL1}
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = ".env", .data = env_content });

    // Create task
    const config_toml =
        \\[tasks.three-level]
        \\cmd = "echo $MESSAGE"
        \\env_file = ".env"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "three-level" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Result: final_value") != null);
}
