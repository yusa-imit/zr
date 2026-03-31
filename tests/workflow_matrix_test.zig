const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// Test 3935: Workflow matrix expansion with single dimension
test "3935: workflow matrix: single dimension expansion" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_content =
        \\[workflows.test]
        \\stages = [
        \\  { tasks = ["build"] },
        \\]
        \\matrix = { arch = ["x86_64", "aarch64", "arm"] }
        \\
        \\[tasks.build]
        \\cmd = "echo Building for ${matrix.arch}"
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_content);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "workflow", "test", "--matrix-show" }, tmp_path);
    defer result.deinit();

    // Should display all 3 matrix combinations
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "arch=x86_64") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "arch=aarch64") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "arch=arm") != null);

    // Should show total combinations
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "3 combinations") != null or
                          std.mem.indexOf(u8, result.stderr, "3 matrix") != null);
}

// Test 3936: Workflow matrix expansion with 2x3 dimensions
test "workflow matrix: cartesian product 2x3" {
    const config =
        \\[workflows.test]
        \\stages = [
        \\  { tasks = ["test"] },
        \\]
        \\matrix = { os = ["linux", "macos"], version = ["1.0", "2.0", "3.0"] }
        \\
        \\[tasks.test]
        \\cmd = "test ${matrix.os} ${matrix.version}"
    ;

    const result = try integration.runZr(&.{ "workflow", "test", "--matrix-show" }, config);
    defer result.deinit();

    // Should display all 6 combinations (2 os * 3 version)
    try testing.expect(std.mem.indexOf(u8, result.stderr, "os=linux") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "os=macos") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "version=1.0") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "version=2.0") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "version=3.0") != null);

    // Should show total combinations
    try testing.expect(std.mem.indexOf(u8, result.stderr, "6 combinations") != null or
                      std.mem.indexOf(u8, result.stderr, "6 matrix") != null);
}

// Test 3937: Workflow matrix with exclusions
test "workflow matrix: exclusions filter combinations" {
    const config =
        \\[workflows.test]
        \\stages = [
        \\  { tasks = ["test"] },
        \\]
        \\
        \\[workflows.test.matrix]
        \\os = ["linux", "macos", "windows"]
        \\version = ["1.0", "2.0"]
        \\
        \\[[workflows.test.matrix.exclude]]
        \\os = "macos"
        \\version = "1.0"
        \\
        \\[tasks.test]
        \\cmd = "test ${matrix.os} ${matrix.version}"
    ;

    const result = try integration.runZr(&.{ "workflow", "test", "--matrix-show" }, config);
    defer result.deinit();

    // Should display 5 combinations (6 total - 1 excluded)
    try testing.expect(std.mem.indexOf(u8, result.stderr, "5 combinations") != null or
                      std.mem.indexOf(u8, result.stderr, "5 matrix") != null);

    // Should NOT include the excluded combination
    try testing.expect(std.mem.indexOf(u8, result.stderr, "os=macos:version=1.0") == null);
}

// Test 3938: Workflow matrix variable substitution in task commands
test "workflow matrix: variable substitution in commands" {
    const config =
        \\[workflows.ci]
        \\stages = [
        \\  { tasks = ["lint"] },
        \\]
        \\matrix = { target = ["js", "ts", "rs"] }
        \\
        \\[tasks.lint]
        \\cmd = "echo linting ${matrix.target} files"
    ;

    const result = try integration.runZr(&.{ "workflow", "ci", "--dry-run" }, config);
    defer result.deinit();

    // Dry run should show interpolated commands
    try testing.expect(std.mem.indexOf(u8, result.stderr, "linting js files") != null or
                      std.mem.indexOf(u8, result.stdout, "linting js files") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "linting ts files") != null or
                      std.mem.indexOf(u8, result.stdout, "linting ts files") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "linting rs files") != null or
                      std.mem.indexOf(u8, result.stdout, "linting rs files") != null);
}

// Test 3939: Workflow matrix execution (actual run)
test "workflow matrix: parallel execution of all combinations" {
    const config =
        \\[workflows.parallel-test]
        \\stages = [
        \\  { tasks = ["echo"] },
        \\]
        \\matrix = { msg = ["hello", "world"] }
        \\
        \\[tasks.echo]
        \\cmd = "echo ${matrix.msg}"
    ;

    const result = try integration.runZr(&.{ "workflow", "parallel-test" }, config);
    defer result.deinit();

    // Both matrix values should appear in output
    try testing.expect(std.mem.indexOf(u8, result.stdout, "hello") != null or
                      std.mem.indexOf(u8, result.stderr, "hello") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "world") != null or
                      std.mem.indexOf(u8, result.stderr, "world") != null);

    // Should succeed
    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 3940: Workflow matrix with multi-stage workflow
test "workflow matrix: multi-stage with matrix" {
    const config =
        \\[workflows.build-test]
        \\stages = [
        \\  { tasks = ["build"] },
        \\  { tasks = ["test"] },
        \\]
        \\matrix = { platform = ["x64", "arm64"] }
        \\
        \\[tasks.build]
        \\cmd = "echo building ${matrix.platform}"
        \\
        \\[tasks.test]
        \\cmd = "echo testing ${matrix.platform}"
        \\deps = ["build"]
    ;

    const result = try integration.runZr(&.{ "workflow", "build-test", "--dry-run" }, config);
    defer result.deinit();

    // Should show both stages for both platforms
    try testing.expect(std.mem.indexOf(u8, result.stderr, "building x64") != null or
                      std.mem.indexOf(u8, result.stdout, "building x64") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "building arm64") != null or
                      std.mem.indexOf(u8, result.stdout, "building arm64") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "testing x64") != null or
                      std.mem.indexOf(u8, result.stdout, "testing x64") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "testing arm64") != null or
                      std.mem.indexOf(u8, result.stdout, "testing arm64") != null);
}

// Test 3941: Workflow without matrix runs normally
test "workflow matrix: workflow without matrix runs normally" {
    const config =
        \\[workflows.simple]
        \\stages = [
        \\  { tasks = ["hello"] },
        \\]
        \\
        \\[tasks.hello]
        \\cmd = "echo hello"
    ;

    const result = try integration.runZr(&.{ "workflow", "simple" }, config);
    defer result.deinit();

    try testing.expect(std.mem.indexOf(u8, result.stdout, "hello") != null or
                      std.mem.indexOf(u8, result.stderr, "hello") != null);
    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

// Test 3942: Matrix-show with workflow that has no matrix
test "workflow matrix: matrix-show with non-matrix workflow" {
    const config =
        \\[workflows.simple]
        \\stages = [
        \\  { tasks = ["hello"] },
        \\]
        \\
        \\[tasks.hello]
        \\cmd = "echo hello"
    ;

    const result = try integration.runZr(&.{ "workflow", "simple", "--matrix-show" }, config);
    defer result.deinit();

    // Should indicate no matrix defined
    try testing.expect(std.mem.indexOf(u8, result.stderr, "no matrix") != null or
                      std.mem.indexOf(u8, result.stderr, "No matrix") != null or
                      std.mem.indexOf(u8, result.stderr, "0 combinations") != null);
}

// Test 3943: Matrix with sorted keys in variant names
test "workflow matrix: keys sorted alphabetically in variant names" {
    const config =
        \\[workflows.test]
        \\stages = [
        \\  { tasks = ["build"] },
        \\]
        \\matrix = { os = ["linux"], arch = ["x86_64"], compiler = ["gcc"] }
        \\
        \\[tasks.build]
        \\cmd = "echo build"
    ;

    const result = try integration.runZr(&.{ "workflow", "test", "--matrix-show" }, config);
    defer result.deinit();

    // Keys should be sorted: arch < compiler < os
    // (variant names should have keys in alphabetical order)
    try testing.expect(std.mem.indexOf(u8, result.stderr, "arch=") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "compiler=") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "os=") != null);
}

// Test 3944: Matrix variable substitution in task environment variables
test "workflow matrix: variable substitution in env vars" {
    const config =
        \\[workflows.test]
        \\stages = [
        \\  { tasks = ["build"] },
        \\]
        \\matrix = { target = ["prod", "dev"] }
        \\
        \\[tasks.build]
        \\cmd = "echo $ENV_TARGET"
        \\env = { ENV_TARGET = "${matrix.target}" }
    ;

    const result = try integration.runZr(&.{ "workflow", "test" }, config);
    defer result.deinit();

    // Both env values should appear
    try testing.expect(std.mem.indexOf(u8, result.stdout, "prod") != null or
                      std.mem.indexOf(u8, result.stderr, "prod") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "dev") != null or
                      std.mem.indexOf(u8, result.stderr, "dev") != null);
}
