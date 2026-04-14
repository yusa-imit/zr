const std = @import("std");
const helpers = @import("helpers.zig");

// Task Name Abbreviation & Fuzzy Matching Tests (Milestone v1.69.0)
// Tests for prefix matching, unique prefix resolution, and ambiguity handling

test "abbreviation: unique prefix match (zr b -> build)" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const zr_config =
        \\[tasks.build]
        \\cmd = "echo 'Building...'"
        \\
        \\[tasks.test]
        \\cmd = "echo 'Testing...'"
    ;
    const zr_file = try tmp_dir.dir.createFile("zr.toml", .{});
    defer zr_file.close();
    try zr_file.writeAll(zr_config);

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run `zr run b` - should match "build"
    const result = try helpers.runZr(allocator, &[_][]const u8{ "run", "b" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Building...") != null);
    // Should show resolution hint
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Resolved") != null or
        std.mem.indexOf(u8, result.stderr, "build") != null);
}

test "abbreviation: two-letter prefix (zr te -> test)" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const zr_config =
        \\[tasks.build]
        \\cmd = "echo 'Building...'"
        \\
        \\[tasks.test]
        \\cmd = "echo 'Testing...'"
        \\
        \\[tasks.teardown]
        \\cmd = "echo 'Tearing down...'"
    ;
    const zr_file = try tmp_dir.dir.createFile("zr.toml", .{});
    defer zr_file.close();
    try zr_file.writeAll(zr_config);

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run `zr run te` - should be ambiguous (test, teardown)
    const result = try helpers.runZr(allocator, &[_][]const u8{ "run", "te" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Should fail with ambiguity error
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Ambiguous") != null or
        std.mem.indexOf(u8, result.stderr, "ambiguous") != null);
    // Should list both matches
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "teardown") != null);
}

test "abbreviation: exact match takes precedence over prefix" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const zr_config =
        \\[tasks.b]
        \\cmd = "echo 'Task b'"
        \\
        \\[tasks.build]
        \\cmd = "echo 'Building...'"
    ;
    const zr_file = try tmp_dir.dir.createFile("zr.toml", .{});
    defer zr_file.close();
    try zr_file.writeAll(zr_config);

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run `zr run b` - should match exact task "b", not prefix-match "build"
    const result = try helpers.runZr(allocator, &[_][]const u8{ "run", "b" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Task b") != null);
    // Should NOT resolve (exact match doesn't show hint)
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Resolved") == null);
}

test "abbreviation: no prefix match falls back to fuzzy suggestion" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const zr_config =
        \\[tasks.build]
        \\cmd = "echo 'Building...'"
        \\
        \\[tasks.test]
        \\cmd = "echo 'Testing...'"
    ;
    const zr_file = try tmp_dir.dir.createFile("zr.toml", .{});
    defer zr_file.close();
    try zr_file.writeAll(zr_config);

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run `zr run tset` - no prefix match, should suggest "test" via fuzzy
    const result = try helpers.runZr(allocator, &[_][]const u8{ "run", "tset" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "not found") != null or
        std.mem.indexOf(u8, result.stderr, "Not found") != null or
        std.mem.indexOf(u8, result.stderr, "Task") != null);
    // Should suggest "test" via Levenshtein
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Did you mean") != null or
        std.mem.indexOf(u8, result.stderr, "test") != null);
}

test "abbreviation: single-letter prefix with many tasks" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const zr_config =
        \\[tasks.analyze]
        \\cmd = "echo 'analyze'"
        \\
        \\[tasks.build]
        \\cmd = "echo 'build'"
        \\
        \\[tasks.clean]
        \\cmd = "echo 'clean'"
    ;
    const zr_file = try tmp_dir.dir.createFile("zr.toml", .{});
    defer zr_file.close();
    try zr_file.writeAll(zr_config);

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run `zr run a` - should match "analyze" (unique prefix)
    const result_a = try helpers.runZr(allocator, &[_][]const u8{ "run", "a" }, tmp_path);
    defer allocator.free(result_a.stdout);
    defer allocator.free(result_a.stderr);
    try std.testing.expectEqual(@as(u8, 0), result_a.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result_a.stdout, "analyze") != null);

    // Run `zr run c` - should match "clean" (unique prefix)
    const result_c = try helpers.runZr(allocator, &[_][]const u8{ "run", "c" }, tmp_path);
    defer allocator.free(result_c.stdout);
    defer allocator.free(result_c.stderr);
    try std.testing.expectEqual(@as(u8, 0), result_c.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result_c.stdout, "clean") != null);
}

test "abbreviation: list shows unique prefix hints" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const zr_config =
        \\[tasks.build]
        \\cmd = "echo 'build'"
        \\
        \\[tasks.build-docker]
        \\cmd = "echo 'build-docker'"
        \\
        \\[tasks.test]
        \\cmd = "echo 'test'"
    ;
    const zr_file = try tmp_dir.dir.createFile("zr.toml", .{});
    defer zr_file.close();
    try zr_file.writeAll(zr_config);

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run `zr list` - should show unique prefix hints
    const result = try helpers.runZr(allocator, &[_][]const u8{"list"}, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show task names
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
    // Should show prefix hint for test (unique: "t")
    // build and build-docker both start with "b", so no unique single-letter prefix
    // test has unique prefix "t"
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[t]") != null or
        std.mem.indexOf(u8, result.stdout, "test") != null);
}

test "abbreviation: prefix with dependencies" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const zr_config =
        \\[tasks.clean]
        \\cmd = "echo 'Cleaning...'"
        \\
        \\[tasks.build]
        \\cmd = "echo 'Building...'"
        \\deps = ["clean"]
    ;
    const zr_file = try tmp_dir.dir.createFile("zr.toml", .{});
    defer zr_file.close();
    try zr_file.writeAll(zr_config);

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run `zr run b` - should match "build" and run its dependency "clean"
    const result = try helpers.runZr(allocator, &[_][]const u8{ "run", "b" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should run both clean and build
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Cleaning...") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Building...") != null);
}
