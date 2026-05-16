/// Integration tests for interactive workflow visualizer (v1.58.0)
const std = @import("std");
const helpers = @import("helpers.zig");

// Test 3907: Interactive visualizer generates valid HTML
test "graph --interactive generates valid HTML" {
    const allocator = std.testing.allocator;
    var runner = try helpers.TestRunner.init(allocator);
    defer runner.deinit();

    const config =
        \\[tasks.build]
        \\cmd = "echo Building..."
        \\
        \\[tasks.test]
        \\cmd = "echo Testing..."
        \\deps = ["build"]
        \\
        \\[tasks.deploy]
        \\cmd = "echo Deploying..."
        \\deps = ["test"]
    ;

    try runner.writeConfig(config);

    const result = try runner.run(&[_][]const u8{ "graph", "--interactive" });

    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "<!DOCTYPE html>") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "zr Task Graph") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "d3.v7.min.js") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "deploy") != null);
}

// Test 3908: Interactive visualizer shows task details
test "graph --interactive includes task commands and dependencies" {
    const allocator = std.testing.allocator;
    var runner = try helpers.TestRunner.init(allocator);
    defer runner.deinit();

    const config =
        \\[tasks.lint]
        \\cmd = "eslint src/"
        \\description = "Lint source code"
        \\tags = ["quality", "ci"]
        \\
        \\[tasks.format]
        \\cmd = "prettier --write src/"
        \\deps = ["lint"]
    ;

    try runner.writeConfig(config);

    const result = try runner.run(&[_][]const u8{ "graph", "--interactive" });

    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "eslint src/") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "prettier --write src/") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Lint source code") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "quality") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ci") != null);
}

// Test 3909: Interactive visualizer shows critical path
test "graph --interactive highlights critical path" {
    const allocator = std.testing.allocator;
    var runner = try helpers.TestRunner.init(allocator);
    defer runner.deinit();

    const config =
        \\[tasks.a]
        \\cmd = "echo A"
        \\
        \\[tasks.b]
        \\cmd = "echo B"
        \\deps = ["a"]
        \\
        \\[tasks.c]
        \\cmd = "echo C"
        \\deps = ["b"]
        \\
        \\[tasks.d]
        \\cmd = "echo D"
        \\deps = ["a"]
    ;

    try runner.writeConfig(config);

    const result = try runner.run(&[_][]const u8{ "graph", "--interactive" });

    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "critical_path") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Critical Path") != null);
}

// Test 3910: Interactive visualizer includes filter controls
test "graph --interactive includes filter controls" {
    const allocator = std.testing.allocator;
    var runner = try helpers.TestRunner.init(allocator);
    defer runner.deinit();

    const config =
        \\[tasks.build]
        \\cmd = "make"
        \\tags = ["ci"]
    ;

    try runner.writeConfig(config);

    const result = try runner.run(&[_][]const u8{ "graph", "--interactive" });

    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "id=\"search\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "id=\"status-filter\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "id=\"tag-filter\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "id=\"reset-zoom\"") != null);
}

// Test 3911: Interactive visualizer includes export buttons
test "graph --interactive includes export functionality" {
    const allocator = std.testing.allocator;
    var runner = try helpers.TestRunner.init(allocator);
    defer runner.deinit();

    const config =
        \\[tasks.test]
        \\cmd = "npm test"
    ;

    try runner.writeConfig(config);

    const result = try runner.run(&[_][]const u8{ "graph", "--interactive" });

    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "id=\"export-svg\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "id=\"export-png\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Export SVG") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Export PNG") != null);
}

// Test 3912: Interactive visualizer handles empty config
test "graph --interactive handles config with no tasks" {
    const allocator = std.testing.allocator;
    var runner = try helpers.TestRunner.init(allocator);
    defer runner.deinit();

    const config =
        \\# Empty config
    ;

    try runner.writeConfig(config);

    const result = try runner.run(&[_][]const u8{ "graph", "--interactive" });

    // Should still generate HTML with empty graph
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "<!DOCTYPE html>") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "nodes: [") != null);
}

// Test 3913: Interactive visualizer shows task environment variables
test "graph --interactive includes environment variables" {
    const allocator = std.testing.allocator;
    var runner = try helpers.TestRunner.init(allocator);
    defer runner.deinit();

    const config =
        \\[tasks.deploy]
        \\cmd = "deploy.sh"
        \\env = { NODE_ENV = "production", PORT = "3000" }
    ;

    try runner.writeConfig(config);

    const result = try runner.run(&[_][]const u8{ "graph", "--interactive" });

    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "NODE_ENV") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "production") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "PORT") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "3000") != null);
}

// Test 3914: --type=tasks --format=interactive works
test "graph --type=tasks --format=interactive generates HTML" {
    const allocator = std.testing.allocator;
    var runner = try helpers.TestRunner.init(allocator);
    defer runner.deinit();

    const config =
        \\[tasks.build]
        \\cmd = "make"
    ;

    try runner.writeConfig(config);

    const result = try runner.run(&[_][]const u8{ "graph", "--type=tasks", "--format=interactive" });

    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "<!DOCTYPE html>") != null);
}

// Test 3915: --type=tasks requires interactive format
test "graph --type=tasks without --interactive shows error" {
    const allocator = std.testing.allocator;
    var runner = try helpers.TestRunner.init(allocator);
    defer runner.deinit();

    const config =
        \\[tasks.build]
        \\cmd = "make"
    ;

    try runner.writeConfig(config);

    const result = try runner.run(&[_][]const u8{ "graph", "--type=tasks" });

    try std.testing.expect(result.exit_code == 1);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "only supports --interactive") != null);
}

// Test 3916: Interactive visualizer handles complex dependency graph
test "graph --interactive handles complex multi-level dependencies" {
    const allocator = std.testing.allocator;
    var runner = try helpers.TestRunner.init(allocator);
    defer runner.deinit();

    const config =
        \\[tasks.a]
        \\cmd = "echo A"
        \\
        \\[tasks.b]
        \\cmd = "echo B"
        \\deps = ["a"]
        \\
        \\[tasks.c]
        \\cmd = "echo C"
        \\deps = ["a"]
        \\
        \\[tasks.d]
        \\cmd = "echo D"
        \\deps = ["b", "c"]
        \\
        \\[tasks.e]
        \\cmd = "echo E"
        \\deps = ["d"]
    ;

    try runner.writeConfig(config);

    const result = try runner.run(&[_][]const u8{ "graph", "--interactive" });

    try std.testing.expect(result.exit_code == 0);
    // All 5 tasks should be in the output
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "name:\"a\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "name:\"b\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "name:\"c\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "name:\"d\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "name:\"e\"") != null);
}
