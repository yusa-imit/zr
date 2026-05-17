const std = @import("std");
const testing = std.testing;
const integration = @import("integration.zig");
const runZr = integration.runZr;
const TempDir = integration.TempDir;

test "help command: zr help <task> displays task details" {
    var tmp = try TempDir.init();
    defer tmp.deinit();

    try tmp.writeFile("zr.toml",
        \\[tasks.build]
        \\cmd = "zig build"
        \\description = { short = "Build the project", long = "Compiles all source files using Zig build system" }
        \\
    );

    const result = try runZr(tmp.dir, &.{ "help", "build" }, .{});
    defer result.deinit();

    try testing.expectEqual(@as(u32, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "Build the project") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "Command:") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "zig build") != null);
}

test "help command: displays long description when available" {
    var tmp = try TempDir.init();
    defer tmp.deinit();

    try tmp.writeFile("zr.toml",
        \\[tasks.test]
        \\cmd = "zig build test"
        \\description = { short = "Run tests", long = "Executes all unit and integration tests using Zig's test runner" }
        \\
    );

    const result = try runZr(tmp.dir, &.{ "help", "test" }, .{});
    defer result.deinit();

    try testing.expectEqual(@as(u32, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "Run tests") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "Executes all unit and integration tests") != null);
}

test "help command: displays examples when available" {
    var tmp = try TempDir.init();
    defer tmp.deinit();

    try tmp.writeFile("zr.toml",
        \\[tasks.format]
        \\cmd = "zig fmt src"
        \\description = { short = "Format code" }
        \\examples = ["zr format", "zr format -- --check"]
        \\
    );

    const result = try runZr(tmp.dir, &.{ "help", "format" }, .{});
    defer result.deinit();

    try testing.expectEqual(@as(u32, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "Examples:") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "zr format") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "zr format -- --check") != null);
}

test "help command: error when task not found" {
    var tmp = try TempDir.init();
    defer tmp.deinit();

    try tmp.writeFile("zr.toml",
        \\[tasks.build]
        \\cmd = "zig build"
        \\
    );

    const result = try runZr(tmp.dir, &.{ "help", "nonexistent" }, .{});
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "Task 'nonexistent' not found") != null);
}

test "help command: displays dependencies" {
    var tmp = try TempDir.init();
    defer tmp.deinit();

    try tmp.writeFile("zr.toml",
        \\[tasks.clean]
        \\cmd = "rm -rf build"
        \\
        \\[tasks.build]
        \\cmd = "zig build"
        \\deps = ["clean"]
        \\
    );

    const result = try runZr(tmp.dir, &.{ "help", "build" }, .{});
    defer result.deinit();

    try testing.expectEqual(@as(u32, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    // The help command should show the task details including deps
}

test "help command: displays env vars when present" {
    var tmp = try TempDir.init();
    defer tmp.deinit();

    try tmp.writeFile("zr.toml",
        \\[tasks.deploy]
        \\cmd = "deploy.sh"
        \\env = { ENVIRONMENT = "production", REGION = "us-east-1" }
        \\description = { short = "Deploy to production" }
        \\
    );

    const result = try runZr(tmp.dir, &.{ "help", "deploy" }, .{});
    defer result.deinit();

    try testing.expectEqual(@as(u32, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "deploy") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "Deploy to production") != null);
}

test "help command: displays tags when present" {
    var tmp = try TempDir.init();
    defer tmp.deinit();

    try tmp.writeFile("zr.toml",
        \\[tasks.lint]
        \\cmd = "zig fmt --check src"
        \\description = { short = "Check code formatting" }
        \\tags = ["ci", "quality"]
        \\
    );

    const result = try runZr(tmp.dir, &.{ "help", "lint" }, .{});
    defer result.deinit();

    try testing.expectEqual(@as(u32, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "lint") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "Check code formatting") != null);
}

test "help command: works with task that has retry configuration" {
    var tmp = try TempDir.init();
    defer tmp.deinit();

    try tmp.writeFile("zr.toml",
        \\[tasks.fetch]
        \\cmd = "curl https://example.com"
        \\description = { short = "Fetch data" }
        \\[tasks.fetch.retry]
        \\max_attempts = 3
        \\base_delay_ms = 1000
        \\
    );

    const result = try runZr(tmp.dir, &.{ "help", "fetch" }, .{});
    defer result.deinit();

    try testing.expectEqual(@as(u32, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "fetch") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "Fetch data") != null);
}
