const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;
const HELLO_TOML = helpers.HELLO_TOML;

test "3927: which displays task location and details" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "which", "hello" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "is defined in:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Command:") != null);
}

test "3928: which with nonexistent task fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "which", "nonexistent" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "not found") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Hint: Run 'zr list'") != null);
}

test "3929: which shows task description when present" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml_with_desc =
        \\[tasks.build]
        \\cmd = "make"
        \\description = "Build the project"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml_with_desc);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "which", "build" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Description:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Build the project") != null);
}

test "3930: which shows dependencies when present" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml_with_deps =
        \\[tasks.test]
        \\cmd = "npm test"
        \\deps = ["build", "lint"]
        \\
        \\[tasks.build]
        \\cmd = "npm run build"
        \\
        \\[tasks.lint]
        \\cmd = "npm run lint"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml_with_deps);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "which", "test" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Dependencies:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint") != null);
}

test "3931: which shows tags when present" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml_with_tags =
        \\[tasks.deploy]
        \\cmd = "npm run deploy"
        \\tags = ["production", "critical"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml_with_tags);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "which", "deploy" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Tags:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "production") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "critical") != null);
}

test "3932: which shows complete task with all metadata" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const complete_toml =
        \\[tasks.integration]
        \\cmd = "npm run integration"
        \\description = "Run integration tests"
        \\deps = ["build"]
        \\tags = ["test", "ci"]
        \\
        \\[tasks.build]
        \\cmd = "npm run build"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, complete_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "which", "integration" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Check all sections are present
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Command:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Description:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Dependencies:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Tags:") != null);
}

test "3933: which shows absolute config file path" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "which", "hello" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show absolute path (contains /)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "/") != null);
    // Path should end with zr.toml
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "zr.toml") != null);
}

test "3934: which works with minimal task definition" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const minimal_toml =
        \\[tasks.minimal]
        \\cmd = "echo minimal"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, minimal_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "which", "minimal" }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "minimal") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "echo minimal") != null);
    // Should not show Description/Dependencies/Tags sections (not present)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Description:") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Dependencies:") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Tags:") == null);
}
