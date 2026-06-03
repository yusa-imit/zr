const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Profile Enhancement Tests ────────────────────────────────────────────
//
// Tests for Profile enhancement features:
// 1. Profile description field (displayed in `zr list --profiles`)
// 2. Profile vars override section ([profiles.X.vars] overrides [vars])
//

test "16000: list --profiles shows profile name with description" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[profiles.prod]
        \\description = "Production environment with strict settings"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--profiles" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "prod") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Production environment with strict settings") != null);
}

test "16001: list --profiles shows profile name only without description (backward compat)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[profiles.dev]
        \\env = { NODE_ENV = "development" }
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--profiles" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "dev") != null);
}

test "16002: run --profile X applies profile vars override to task execution" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[vars]
        \\VERSION = "1.0.0"
        \\ENV = "dev"
        \\
        \\[profiles.prod]
        \\
        \\[profiles.prod.vars]
        \\ENV = "prod"
        \\VERSION = "1.2.0"
        \\
        \\[tasks.deploy]
        \\cmd = "echo ENV={{ENV}} VERSION={{VERSION}}"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "--profile", "prod", "run", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ENV=prod") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "VERSION=1.2.0") != null);
}

test "16003: profile vars override is partial — unmatched keys unchanged" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[vars]
        \\A = "original-a"
        \\B = "original-b"
        \\C = "original-c"
        \\
        \\[profiles.staging]
        \\
        \\[profiles.staging.vars]
        \\A = "override-a"
        \\
        \\[tasks.print-vars]
        \\cmd = "echo A={{A}} B={{B}} C={{C}}"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "--profile", "staging", "run", "print-vars" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "A=override-a") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "B=original-b") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "C=original-c") != null);
}

test "16004: profile env and vars work together" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[vars]
        \\VERSION = "1.0.0"
        \\
        \\[profiles.prod]
        \\env = { NODE_ENV = "production" }
        \\
        \\[profiles.prod.vars]
        \\VERSION = "2.0.0"
        \\
        \\[tasks.deploy]
        \\cmd = "echo VERSION={{VERSION}} NODE_ENV=$NODE_ENV"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "--profile", "prod", "run", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "VERSION=2.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "NODE_ENV=production") != null);
}

test "16005: unknown var key in profile.vars section is added to vars pool" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[vars]
        \\A = "a-value"
        \\
        \\[profiles.special]
        \\
        \\[profiles.special.vars]
        \\B = "new-b-value"
        \\
        \\[tasks.show]
        \\cmd = "echo A={{A}} B={{B}}"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "--profile", "special", "run", "show" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "A=a-value") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "B=new-b-value") != null);
}

test "16006: run without --profile still works (no regression)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[vars]
        \\VERSION = "1.0.0"
        \\
        \\[tasks.deploy]
        \\cmd = "echo VERSION={{VERSION}}"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "run", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "VERSION=1.0.0") != null);
}

test "16007: list --profiles with multiple profiles shows all with descriptions" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[profiles.dev]
        \\description = "Development profile"
        \\
        \\[profiles.prod]
        \\description = "Production profile"
        \\
        \\[profiles.test-env]
        \\env = { CI = "true" }
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--profiles" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "dev") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "prod") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test-env") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Development profile") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Production profile") != null);
}
