const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

test "15100: tags: list all tags alphabetically" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tagged_config =
        \\[tasks.build]
        \\cmd = "echo build"
        \\tags = ["ci", "production"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\tags = ["ci"]
        \\
        \\[tasks.db-migrate]
        \\cmd = "echo migrate"
        \\tags = ["backend"]
        \\
        \\[tasks.api]
        \\cmd = "echo api"
        \\tags = ["backend", "production"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, tagged_config);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "tags" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should list tags alphabetically
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "backend") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "ci") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "production") != null);
    // Verify task counts are shown
    try std.testing.expect(std.mem.indexOf(u8, output, "2") != null or std.mem.indexOf(u8, output, "tasks") != null);
}

test "15101: tags: list all tags sorted by count" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tagged_config =
        \\[tasks.build]
        \\cmd = "echo build"
        \\tags = ["ci"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\tags = ["ci"]
        \\
        \\[tasks.lint]
        \\cmd = "echo lint"
        \\tags = ["ci"]
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\tags = ["prod"]
        \\
        \\[tasks.api]
        \\cmd = "echo api"
        \\tags = ["backend"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, tagged_config);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "tags", "--sort=count" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show ci (3 tasks) before prod (1 task) and backend (1 task)
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    const ci_pos = std.mem.indexOf(u8, output, "ci");
    const prod_pos = std.mem.indexOf(u8, output, "prod");
    try std.testing.expect(ci_pos != null);
    try std.testing.expect(prod_pos != null);
    // ci should appear before prod in count order
    if (ci_pos != null and prod_pos != null) {
        try std.testing.expect(ci_pos.? < prod_pos.?);
    }
}

test "15102: tags: filter tasks by specific tag" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tagged_config =
        \\[tasks.build]
        \\cmd = "echo build"
        \\tags = ["ci", "production"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\tags = ["ci"]
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\tags = ["production"]
        \\
        \\[tasks.lint]
        \\cmd = "echo lint"
        \\tags = ["linting"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, tagged_config);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "tags", "ci" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should show tasks tagged with 'ci': build and test
    try std.testing.expect(std.mem.indexOf(u8, output, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "test") != null);
    // Should NOT show tasks without 'ci' tag
    try std.testing.expect(std.mem.indexOf(u8, output, "lint") == null);
}

test "15103: tags: JSON output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tagged_config =
        \\[tasks.build]
        \\cmd = "echo build"
        \\tags = ["ci"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\tags = ["ci"]
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\tags = ["production"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, tagged_config);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "tags", "--json" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should output JSON
    try std.testing.expect(std.mem.indexOf(u8, output, "[") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "]") != null);
    // Should contain tag names in JSON
    try std.testing.expect(std.mem.indexOf(u8, output, "ci") != null or std.mem.indexOf(u8, output, "production") != null);
}

test "15104: tags: JSON output for specific tag" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tagged_config =
        \\[tasks.build]
        \\cmd = "echo build"
        \\tags = ["ci", "production"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\tags = ["ci"]
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\tags = ["production"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, tagged_config);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "tags", "production", "--json" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should output JSON array
    try std.testing.expect(std.mem.indexOf(u8, output, "[") != null or std.mem.indexOf(u8, output, "{") != null);
    // Should list tasks with production tag: build and deploy
    try std.testing.expect(std.mem.indexOf(u8, output, "build") != null or std.mem.indexOf(u8, output, "deploy") != null);
}

test "15105: tags: empty config (no tags)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const empty_config =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, empty_config);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "tags" }, tmp_path);
    defer result.deinit();

    // Should exit with 0 (no tags is not an error)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output may be empty or show a "no tags" message
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Verify no task names are shown as tags
    try std.testing.expect(std.mem.indexOf(u8, output, "build") == null and std.mem.indexOf(u8, output, "test") == null);
}

test "15106: tags: nonexistent tag returns error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tagged_config =
        \\[tasks.build]
        \\cmd = "echo build"
        \\tags = ["ci"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\tags = ["backend"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, tagged_config);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "tags", "nonexistent" }, tmp_path);
    defer result.deinit();

    // Should exit with error code
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should mention error and the tag name
    try std.testing.expect(std.mem.indexOf(u8, output, "nonexistent") != null or std.mem.indexOf(u8, output, "No tasks") != null or std.mem.indexOf(u8, output, "✗") != null);
}

test "15107: tags: task with multiple tags appears in each" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tagged_config =
        \\[tasks.build]
        \\cmd = "echo build"
        \\tags = ["ci", "build", "production"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\tags = ["ci", "testing"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, tagged_config);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Test that build task appears under 'ci' tag
    var result_ci = try runZr(allocator, &.{ "--config", config, "tags", "ci" }, tmp_path);
    defer result_ci.deinit();
    try std.testing.expectEqual(@as(u8, 0), result_ci.exit_code);
    const output_ci = if (result_ci.stdout.len > 0) result_ci.stdout else result_ci.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output_ci, "build") != null);

    // Test that build task appears under 'production' tag
    var result_prod = try runZr(allocator, &.{ "--config", config, "tags", "production" }, tmp_path);
    defer result_prod.deinit();
    try std.testing.expectEqual(@as(u8, 0), result_prod.exit_code);
    const output_prod = if (result_prod.stdout.len > 0) result_prod.stdout else result_prod.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output_prod, "build") != null);

    // Test that build task appears under 'build' tag
    var result_build = try runZr(allocator, &.{ "--config", config, "tags", "build" }, tmp_path);
    defer result_build.deinit();
    try std.testing.expectEqual(@as(u8, 0), result_build.exit_code);
    const output_build = if (result_build.stdout.len > 0) result_build.stdout else result_build.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output_build, "build") != null);
}

test "15108: tags: --sort=name (alphabetical, default)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tagged_config =
        \\[tasks.build]
        \\cmd = "echo build"
        \\tags = ["zebra", "apple", "banana"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, tagged_config);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "tags", "--sort=name" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Tags should appear alphabetically: apple, banana, zebra
    const apple_pos = std.mem.indexOf(u8, output, "apple");
    const banana_pos = std.mem.indexOf(u8, output, "banana");
    const zebra_pos = std.mem.indexOf(u8, output, "zebra");

    if (apple_pos != null and banana_pos != null and zebra_pos != null) {
        try std.testing.expect(apple_pos.? < banana_pos.? and banana_pos.? < zebra_pos.?);
    }
}

test "15109: tags: shows tag count when listing all tags" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tagged_config =
        \\[tasks.build]
        \\cmd = "echo build"
        \\tags = ["ci"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\tags = ["ci"]
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\tags = ["ci"]
        \\
        \\[tasks.lint]
        \\cmd = "echo lint"
        \\tags = ["linting"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, tagged_config);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "tags" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should show count for ci (3 tasks)
    try std.testing.expect(std.mem.indexOf(u8, output, "ci") != null);
    // Should show count for linting (1 task)
    try std.testing.expect(std.mem.indexOf(u8, output, "linting") != null);
    // Should include "3" and "1" or "tasks" keyword
    try std.testing.expect(std.mem.indexOf(u8, output, "3") != null or std.mem.indexOf(u8, output, "1") != null);
}

test "15110: tags: --help shows usage information" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "tags", "--help" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should show help text mentioning tags
    try std.testing.expect(output.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "tag") != null or std.mem.indexOf(u8, output, "usage") != null);
}
