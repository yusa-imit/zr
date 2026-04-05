const std = @import("std");
const helpers = @import("helpers.zig");

const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

test "4000: builtin template list shows all categories" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create minimal config
    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{ "template", "list", "--builtin" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Available templates") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[build]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[test]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[lint]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[deploy]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[ci]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[release]") != null);
}

test "4001: builtin template list shows specific templates" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{ "template", "list", "--builtin" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Check for some specific templates
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "go-build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "cargo-build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "pytest") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "eslint") != null);
}

test "4002: builtin template show displays go-build details" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{ "template", "show", "go-build", "--builtin" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Template: go-build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Category: build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Variables:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "PROJECT_NAME") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "OUTPUT_DIR") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Template content:") != null);
}

test "4003: builtin template show with nonexistent template shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{ "template", "show", "nonexistent", "--builtin" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Template 'nonexistent' not found") != null or
        std.mem.indexOf(u8, result.stdout, "not found") != null);
}

test "4004: builtin template add go-build with variables" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{
        "template",
        "add",
        "go-build",
        "--builtin",
        "--var",
        "PROJECT_NAME=myapp",
        "--var",
        "OUTPUT_DIR=./bin",
    }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[tasks.build]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "myapp") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "./bin") != null);
}

test "4005: builtin template add with missing required variable shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    // go-build requires PROJECT_NAME
    const result = try runZr(allocator, &[_][]const u8{
        "template",
        "add",
        "go-build",
        "--builtin",
    }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Required variable") != null or
        std.mem.indexOf(u8, result.stdout, "PROJECT_NAME") != null);
}

test "4006: builtin template add uses default values" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{
        "template",
        "add",
        "go-build",
        "--builtin",
        "--var",
        "PROJECT_NAME=myapp",
        // Not providing OUTPUT_DIR or CGO_ENABLED - should use defaults
    }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Default OUTPUT_DIR is "./bin"
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "./bin") != null);
    // Default CGO_ENABLED is "0"
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "CGO_ENABLED") != null);
}

test "4007: builtin template add cargo-build" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{
        "template",
        "add",
        "cargo-build",
        "--builtin",
        "--var",
        "PROFILE=release",
    }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[tasks.build]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "cargo build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "release") != null);
}

test "4008: builtin template add pytest" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{
        "template",
        "add",
        "pytest",
        "--builtin",
        "--var",
        "TEST_DIR=tests/",
    }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[tasks.test]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "pytest") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "tests/") != null);
}

test "4009: builtin template add eslint" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{
        "template",
        "add",
        "eslint",
        "--builtin",
        "--var",
        "TARGET=src/",
    }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[tasks.lint]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "eslint") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "src/") != null);
}
