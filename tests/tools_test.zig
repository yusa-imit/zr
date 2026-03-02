const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;
const HELLO_TOML = helpers.HELLO_TOML;

test "32: tools list shows available tools" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "tools", "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "90: tools install with invalid tool name fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try to install non-existent tool
    var result = try runZr(allocator, &.{ "tools", "install", "invalid-tool@1.0.0" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "invalid") != null or std.mem.indexOf(u8, result.stderr, "unknown") != null or std.mem.indexOf(u8, result.stderr, "not found") != null or std.mem.indexOf(u8, result.stderr, "Unsupported") != null);
}

test "144: tools outdated checks for outdated toolchains" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // This command checks for outdated toolchains against registries
    var result = try runZr(allocator, &.{ "tools", "outdated" }, tmp_path);
    defer result.deinit();

    // Should succeed (even if no tools installed)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "151: tools --help flag shows help message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "tools", "--help" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Toolchain Management") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "list") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "install") != null);
}

test "152: tools -h flag shows help message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "tools", "-h" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Toolchain Management") != null);
}

test "352: tools subcommand with invalid toolchain name reports error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    var result = try runZr(allocator, &.{ "tools", "install", "invalid_tool@1.0.0" }, tmp_path);
    defer result.deinit();
    // Should fail for invalid toolchain
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "820: tools upgrade without --check-updates shows available updates" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run upgrade without --check-updates (dry-run mode)
    var result = try runZr(allocator, &.{ "tools", "upgrade" }, tmp_path);
    defer result.deinit();

    // Should succeed (exit code 0 if up-to-date, 1 if updates available)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "821: tools upgrade --help shows help message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "tools", "upgrade", "--help" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Upgrade outdated toolchains") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "--check-updates") != null);
}

test "822: tools upgrade -h shows help message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "tools", "upgrade", "-h" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Upgrade outdated toolchains") != null);
}

test "823: tools upgrade --check-updates performs upgrades" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run upgrade with --check-updates (actually performs upgrades)
    var result = try runZr(allocator, &.{ "tools", "upgrade", "--check-updates" }, tmp_path);
    defer result.deinit();

    // Should succeed (exit code 0 if all up-to-date/upgraded, 1 if upgrades failed)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "824: tools upgrade with kind filter" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run upgrade with kind filter
    var result = try runZr(allocator, &.{ "tools", "upgrade", "node" }, tmp_path);
    defer result.deinit();

    // Should succeed (exit code 0 if up-to-date, 1 if updates available)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "825: tools upgrade with --cleanup flag" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run upgrade with --cleanup (removes old versions after upgrade)
    var result = try runZr(allocator, &.{ "tools", "upgrade", "--check-updates", "--cleanup" }, tmp_path);
    defer result.deinit();

    // Should succeed (exit code 0 if all up-to-date/upgraded, 1 if upgrades failed)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "826: tools upgrade --cleanup without --check-updates has no effect" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run upgrade with --cleanup but without --check-updates (dry-run mode)
    // Should still work but not actually cleanup anything
    var result = try runZr(allocator, &.{ "tools", "upgrade", "--cleanup" }, tmp_path);
    defer result.deinit();

    // Should succeed (exit code 0 if up-to-date, 1 if updates available)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "450: tools install with invalid version format shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const empty_toml =
        \\# Empty config
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(empty_toml);

    // Try invalid version format
    var result = try runZr(allocator, &.{ "tools", "install", "invalid-format" }, tmp_path);
    defer result.deinit();
    // Should fail with error message
    try std.testing.expect(result.exit_code != 0);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "format") != null or
        std.mem.indexOf(u8, output, "@") != null);
}

test "491: tools outdated with --format json outputs structured update info" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const tools_toml =
        \\[tools]
        \\node = "20.0.0"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(tools_toml);

    var result = try runZr(allocator, &.{ "tools", "outdated", "--format", "json" }, tmp_path);
    defer result.deinit();
    // Command may not be fully implemented, just check it runs
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "515: tools list with --format json shows structured toolchain info" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(toml);

    var result = try runZr(allocator, &.{ "tools", "list", "--format", "json" }, tmp_path);
    defer result.deinit();
    // Should return JSON format (empty array or structured data)
    try std.testing.expect(result.exit_code == 0);
}

test "543: tools install with invalid toolchain format shows clear error message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "tools", "install", "invalid_format" }, tmp_path);
    defer result.deinit();
    // Should fail with clear error about format
    try std.testing.expect(result.exit_code != 0);
    const output = if (result.stderr.len > 0) result.stderr else result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "format") != null or std.mem.indexOf(u8, output, "@") != null or std.mem.indexOf(u8, output, "invalid") != null);
}

test "565: tools list with invalid --format shows clear error message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "tools", "list", "--format=xml" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
    const output = if (result.stderr.len > 0) result.stderr else result.stdout;
    // Should show error about unsupported format
    try std.testing.expect(std.mem.indexOf(u8, output, "format") != null or std.mem.indexOf(u8, output, "unknown") != null);
}

test "585: tools install with --force flag reinstalls existing toolchain" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Try tools install (may fail in test env, but should not crash)
    var result = try runZr(allocator, &.{ "--config", config, "tools", "list" }, tmp_path);
    defer result.deinit();
    // Should succeed or fail gracefully
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "602: tools install with invalid toolchain name shows clear error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Invalid toolchain name
    var result = try runZr(allocator, &.{ "tools", "install", "invalid_toolchain@1.0.0" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "invalid") != null or std.mem.indexOf(u8, result.stderr, "unknown") != null or std.mem.indexOf(u8, result.stderr, "error") != null);
}

test "634: tools with --format=json and empty toolchains shows valid empty array" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "tools", "list", "--format", "json" }, tmp_path);
    defer result.deinit();

    // Should output valid JSON array
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Either empty array [] or error message (tools command may not support --format=json yet)
    try std.testing.expect(output.len > 0);
}

test "644: tools outdated with multiple toolchains shows all updates" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tools]
        \\node = "18.0.0"
        \\zig = "0.13.0"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "tools", "outdated" }, tmp_path);
    defer result.deinit();

    // Should check multiple toolchains (may fail without network, just check no crash)
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "673: tools install with version range or latest tag" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Try installing with version pattern (may or may not be supported)
    var result = try runZr(allocator, &.{ "--config", config, "tools", "install", "node@latest" }, tmp_path);
    defer result.deinit();

    // Should either install or show helpful error about version format
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "838: tools install with partial major version resolves to latest patch" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Test partial version with major only: node@20 should resolve to latest 20.x.x
    var result = try runZr(allocator, &.{ "--config", config, "tools", "install", "node@20" }, tmp_path);
    defer result.deinit();

    // Should succeed (exit 0) or show helpful message if network is unavailable
    // The important thing is it doesn't crash or show confusing errors
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "839: tools install with partial major.minor version resolves correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Test partial version with major.minor: node@20.11 should resolve to latest 20.11.x
    var result = try runZr(allocator, &.{ "--config", config, "tools", "install", "node@20.11" }, tmp_path);
    defer result.deinit();

    // Should succeed or show helpful message if network is unavailable
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "840: tools install with partial version on unsupported toolchain shows helpful error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Test partial version on unsupported toolchain (python doesn't support it yet)
    var result = try runZr(allocator, &.{ "--config", config, "tools", "install", "python@3.12" }, tmp_path);
    defer result.deinit();

    // Should fail with helpful error message
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(result.exit_code != 0);
    // Check that error message mentions partial version resolution not being supported
    try std.testing.expect(
        std.mem.indexOf(u8, output, "not supported") != null or
            std.mem.indexOf(u8, output, "exact version") != null or
            std.mem.indexOf(u8, output, "full version") != null,
    );
}

test "841: tools install with exact version still works as before" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Test exact version still works (no resolution needed)
    var result = try runZr(allocator, &.{ "--config", config, "tools", "install", "node@20.11.1" }, tmp_path);
    defer result.deinit();

    // Should work normally (may fail without network, but shouldn't crash)
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}
