const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const runZrEnv = helpers.runZrEnv;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Settings [settings] Section Tests ────────────────────────────────────────
//
// Tests for [settings] section with default_profile support:
// 1. default_profile field is parsed and applied when no --profile or ZR_PROFILE
// 2. --profile flag overrides default_profile from settings
// 3. ZR_PROFILE env var overrides default_profile from settings
// 4. Friendly error when default_profile refers to nonexistent profile
// 5. [settings] section parses alongside other sections without breaking
// 6. default_profile works with run command (smoke test)
// 7. Backward compatibility: no default_profile = no profile applied
//

test "21000: [settings] default_profile applies dev profile vars when no --profile flag" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[settings]
        \\default_profile = "dev"
        \\
        \\[vars]
        \\ENV = "production"
        \\
        \\[profiles.dev]
        \\
        \\[profiles.dev.vars]
        \\ENV = "development"
        \\
        \\[tasks.show-env]
        \\cmd = "echo ENV={{ENV}}"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run WITHOUT --profile flag; default_profile should be applied
    var result = try runZr(allocator, &.{ "--config", config, "run", "show-env" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show development value from default_profile, not production from [vars]
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ENV=development") != null);
}

test "21001: --profile flag overrides [settings] default_profile" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[settings]
        \\default_profile = "dev"
        \\
        \\[vars]
        \\ENV = "production"
        \\
        \\[profiles.dev]
        \\[profiles.dev.vars]
        \\ENV = "development"
        \\
        \\[profiles.staging]
        \\[profiles.staging.vars]
        \\ENV = "staging"
        \\
        \\[tasks.show-env]
        \\cmd = "echo ENV={{ENV}}"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run WITH --profile staging; should override default_profile
    var result = try runZr(allocator, &.{ "--config", config, "--profile", "staging", "run", "show-env" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show staging value from --profile flag, not development from default_profile
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ENV=staging") != null);
}

test "21002: ZR_PROFILE env var overrides [settings] default_profile" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[settings]
        \\default_profile = "dev"
        \\
        \\[vars]
        \\ENV = "production"
        \\
        \\[profiles.dev]
        \\[profiles.dev.vars]
        \\ENV = "development"
        \\
        \\[profiles.prod]
        \\[profiles.prod.vars]
        \\ENV = "production-active"
        \\
        \\[tasks.show-env]
        \\cmd = "echo ENV={{ENV}}"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Set ZR_PROFILE environment variable
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("ZR_PROFILE", "prod");

    // Run with ZR_PROFILE=prod; should override default_profile
    var result = try runZrEnv(allocator, &.{ "--config", config, "run", "show-env" }, tmp_path, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show production-active from ZR_PROFILE, not development from default_profile
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ENV=production-active") != null);
}

test "21003: Missing profile referenced in default_profile gives friendly error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[settings]
        \\default_profile = "nonexistent"
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "build" }, tmp_path);
    defer result.deinit();

    // Should exit with error code
    try std.testing.expect(result.exit_code != 0);
    // Should mention the missing profile name
    const stderr_or_stdout = if (result.stderr.len > 0) result.stderr else result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, stderr_or_stdout, "nonexistent") != null);
}

test "21004: [settings] section parses alongside [tasks], [vars], [profiles]" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[settings]
        \\default_profile = "staging"
        \\
        \\[vars]
        \\APP_NAME = "myapp"
        \\VERSION = "1.0.0"
        \\
        \\[tasks.hello]
        \\cmd = "echo Hello {{APP_NAME}}"
        \\
        \\[tasks.deploy]
        \\cmd = "echo Deploying {{APP_NAME}} v{{VERSION}}"
        \\
        \\[profiles.dev]
        \\[profiles.dev.vars]
        \\VERSION = "0.0.0"
        \\
        \\[profiles.staging]
        \\[profiles.staging.vars]
        \\VERSION = "1.0.0"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Run without --profile; should use default_profile "staging"
    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Verify all sections parsed correctly
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "myapp") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "1.0.0") != null);
}

test "21005: default_profile works with run command (smoke test)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[settings]
        \\default_profile = "test"
        \\
        \\[profiles.test]
        \\[profiles.test.vars]
        \\RESULT = "success"
        \\
        \\[tasks.verify]
        \\cmd = "echo Test result: {{RESULT}}"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "verify" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "success") != null);
}

test "21006: No default_profile in settings = backward compatible (no profile applied)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[vars]
        \\GREETING = "Hello world"
        \\
        \\[tasks.greet]
        \\cmd = "echo {{GREETING}}"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // No [settings] section at all
    var result = try runZr(allocator, &.{ "--config", config, "run", "greet" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Hello world") != null);
}

test "21007: Profile selection priority: --profile > ZR_PROFILE > default_profile" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[settings]
        \\default_profile = "dev"
        \\
        \\[profiles.dev]
        \\[profiles.dev.vars]
        \\ENV = "dev"
        \\
        \\[profiles.staging]
        \\[profiles.staging.vars]
        \\ENV = "staging"
        \\
        \\[profiles.prod]
        \\[profiles.prod.vars]
        \\ENV = "prod"
        \\
        \\[tasks.show]
        \\cmd = "echo {{ENV}}"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // Set ZR_PROFILE=staging but pass --profile=prod
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("ZR_PROFILE", "staging");

    var result = try runZrEnv(allocator, &.{ "--config", config, "--profile", "prod", "run", "show" }, tmp_path, &env_map);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // --profile has highest priority, so should use "prod"
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "prod") != null);
}
