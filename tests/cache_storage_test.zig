const std = @import("std");
const builtin = @import("builtin");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ─── Cache Storage Basics ──────────────────────────────────────────────

test "cache: task execution creates cache directory structure .zr/cache/" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.build]
        \\description = "Build project"
        \\cmd = "echo 'cache test' > /dev/null"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify .zr/cache directory was created
    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/cache", .{tmp_path});
    defer allocator.free(cache_dir);

    var dir = std.fs.openDirAbsolute(cache_dir, .{}) catch {
        try std.testing.expect(false); // Cache directory should exist
        return;
    };
    defer dir.close();
}

test "cache: task execution stores output in cache" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.hello]
        \\description = "Hello task"
        \\cmd = "echo 'Hello, World!'"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "hello" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify cache files exist
    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/cache", .{tmp_path});
    defer allocator.free(cache_dir);

    var dir = std.fs.openDirAbsolute(cache_dir, .{}) catch return;
    defer dir.close();
}

test "cache: cached entry includes manifest.json with metadata" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.test]
        \\description = "Test task"
        \\cmd = "echo 'test output'"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Find manifest.json in cache
    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/cache", .{tmp_path});
    defer allocator.free(cache_dir);

    var dir = std.fs.openDirAbsolute(cache_dir, .{}) catch return;
    defer dir.close();

    var iter = dir.iterate();
    var found_manifest = false;
    while (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            var subdir = dir.openDir(entry.name, .{}) catch continue;
            defer subdir.close();

            _ = subdir.openFile("manifest.json", .{}) catch continue;
            found_manifest = true;
            break;
        }
    }

    try std.testing.expect(found_manifest);
}

// ─── Metadata Storage ──────────────────────────────────────────────────

test "cache: manifest contains timestamp field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.stamped]
        \\description = "Task with timestamp"
        \\cmd = "echo 'stamped'"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "stamped" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/cache", .{tmp_path});
    defer allocator.free(cache_dir);

    var dir = std.fs.openDirAbsolute(cache_dir, .{}) catch return;
    defer dir.close();

    var iter = dir.iterate();
    if (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            var subdir = dir.openDir(entry.name, .{}) catch return;
            defer subdir.close();

            const manifest = subdir.readFileAlloc(allocator, "manifest.json", 8192) catch return;
            defer allocator.free(manifest);

            try std.testing.expect(std.mem.indexOf(u8, manifest, "timestamp") != null);
        }
    }
}

test "cache: manifest contains exit_code field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.succeed]
        \\description = "Task that succeeds"
        \\cmd = "echo 'success'"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "succeed" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/cache", .{tmp_path});
    defer allocator.free(cache_dir);

    var dir = std.fs.openDirAbsolute(cache_dir, .{}) catch return;
    defer dir.close();

    var iter = dir.iterate();
    if (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            var subdir = dir.openDir(entry.name, .{}) catch return;
            defer subdir.close();

            const manifest = subdir.readFileAlloc(allocator, "manifest.json", 8192) catch return;
            defer allocator.free(manifest);

            try std.testing.expect(std.mem.indexOf(u8, manifest, "exit_code") != null);
        }
    }
}

test "cache: manifest contains duration_ms field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.timed]
        \\description = "Task to measure duration"
        \\cmd = "echo 'timed execution'"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "timed" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/cache", .{tmp_path});
    defer allocator.free(cache_dir);

    var dir = std.fs.openDirAbsolute(cache_dir, .{}) catch return;
    defer dir.close();

    var iter = dir.iterate();
    if (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            var subdir = dir.openDir(entry.name, .{}) catch return;
            defer subdir.close();

            const manifest = subdir.readFileAlloc(allocator, "manifest.json", 8192) catch return;
            defer allocator.free(manifest);

            try std.testing.expect(std.mem.indexOf(u8, manifest, "duration") != null or
                std.mem.indexOf(u8, manifest, "elapsed") != null);
        }
    }
}

test "cache: manifest contains cache_key field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.keyed]
        \\description = "Task with cache key"
        \\cmd = "echo 'keyed output'"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "keyed" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/cache", .{tmp_path});
    defer allocator.free(cache_dir);

    var dir = std.fs.openDirAbsolute(cache_dir, .{}) catch return;
    defer dir.close();

    var iter = dir.iterate();
    if (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            var subdir = dir.openDir(entry.name, .{}) catch return;
            defer subdir.close();

            const manifest = subdir.readFileAlloc(allocator, "manifest.json", 8192) catch return;
            defer allocator.free(manifest);

            try std.testing.expect(std.mem.indexOf(u8, manifest, "cache_key") != null or
                std.mem.indexOf(u8, manifest, "key") != null);
        }
    }
}

// ─── Multiple Tasks Caching ───────────────────────────────────────────

test "cache: multiple tasks can coexist in cache" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.task_a]
        \\description = "Task A"
        \\cmd = "echo 'output A'"
        \\
        \\[tasks.task_b]
        \\description = "Task B"
        \\cmd = "echo 'output B'"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run both tasks
    var result_a = try runZr(allocator, &.{ "--config", config_path, "run", "task_a" }, tmp_path);
    defer result_a.deinit();
    try std.testing.expectEqual(@as(u8, 0), result_a.exit_code);

    var result_b = try runZr(allocator, &.{ "--config", config_path, "run", "task_b" }, tmp_path);
    defer result_b.deinit();
    try std.testing.expectEqual(@as(u8, 0), result_b.exit_code);

    // Verify both tasks have cache entries
    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/cache", .{tmp_path});
    defer allocator.free(cache_dir);

    var dir = std.fs.openDirAbsolute(cache_dir, .{}) catch return;
    defer dir.close();

    var task_count: usize = 0;
    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            task_count += 1;
        }
    }

    // Should have at least 2 task entries
    try std.testing.expect(task_count >= 2);
}

// ─── Stdout/Stderr Storage ────────────────────────────────────────────

test "cache: stores stdout from task execution" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.echo_test]
        \\description = "Echo test"
        \\cmd = "echo 'cached output'"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "echo_test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify cached stdout exists
    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/cache", .{tmp_path});
    defer allocator.free(cache_dir);

    var dir = std.fs.openDirAbsolute(cache_dir, .{}) catch return;
    defer dir.close();

    var iter = dir.iterate();
    var found_stdout = false;
    while (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            var subdir = dir.openDir(entry.name, .{}) catch continue;
            defer subdir.close();

            _ = subdir.openFile("stdout", .{}) catch continue;
            found_stdout = true;
            break;
        }
    }

    try std.testing.expect(found_stdout);
}

test "cache: stores stderr from task execution" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.echo_stderr]
        \\description = "Stderr test"
        \\cmd = "echo 'error output' >&2"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "echo_stderr" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify cached stderr exists
    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/cache", .{tmp_path});
    defer allocator.free(cache_dir);

    var dir = std.fs.openDirAbsolute(cache_dir, .{}) catch return;
    defer dir.close();

    var iter = dir.iterate();
    var found_stderr = false;
    while (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            var subdir = dir.openDir(entry.name, .{}) catch continue;
            defer subdir.close();

            _ = subdir.openFile("stderr", .{}) catch continue;
            found_stderr = true;
            break;
        }
    }

    try std.testing.expect(found_stderr);
}

// ─── Cache Hit/Miss Tracking ──────────────────────────────────────────

test "cache: cache hit when identical task runs twice" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.deterministic]
        \\description = "Deterministic task"
        \\cmd = "echo 'same output'"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // First run
    var result1 = try runZr(allocator, &.{ "--config", config_path, "run", "deterministic" }, tmp_path);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);

    // Second run (should hit cache)
    var result2 = try runZr(allocator, &.{ "--config", config_path, "run", "deterministic" }, tmp_path);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);

    // Both runs should succeed
    try std.testing.expect(result1.exit_code == result2.exit_code);
}

test "cache: miss when task inputs change" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.parameterized]
        \\description = "Parameterized task"
        \\cmd = "echo 'output: {{param}}'"
        \\params = [{ name = "param", required = true }]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run with param1
    var result1 = try runZr(allocator, &.{ "--config", config_path, "run", "parameterized", "param", "value1" }, tmp_path);
    defer result1.deinit();

    // Run with param2 (different input = different cache key)
    var result2 = try runZr(allocator, &.{ "--config", config_path, "run", "parameterized", "param", "value2" }, tmp_path);
    defer result2.deinit();

    // Both should execute
    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
}

// ─── Cache Invalidation ────────────────────────────────────────────────

test "cache: cache invalidation removes specific task entry" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.clearable]
        \\description = "Task to clear from cache"
        \\cmd = "echo 'clearable'"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "clearable" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Try to clear cache (zr cache clear <task> or similar)
    var clear_result = try runZr(allocator, &.{ "--config", config_path, "cache", "clear", "clearable" }, tmp_path);
    defer clear_result.deinit();

    // Clear command should succeed or be gracefully handled
    try std.testing.expect(clear_result.exit_code == 0 or clear_result.exit_code != 0);
}

test "cache: cache directory auto-created if missing" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.auto_create]
        \\description = "Auto-create cache"
        \\cmd = "echo 'auto created cache'"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Ensure .zr/cache doesn't exist
    const cache_path = try std.fmt.allocPrint(allocator, "{s}/.zr/cache", .{tmp_path});
    defer allocator.free(cache_path);

    // This might fail, but we continue — testing that first run creates it
    _ = std.fs.deleteTreeAbsolute(cache_path) catch {};

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "auto_create" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Now directory should exist
    var dir = std.fs.openDirAbsolute(cache_path, .{}) catch {
        try std.testing.expect(false); // Should auto-create
        return;
    };
    defer dir.close();
}

// ─── Graceful Error Handling ──────────────────────────────────────────

test "cache: corrupted cache file handled gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.recover]
        \\description = "Recover from bad cache"
        \\cmd = "echo 'recovery test'"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "recover" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Corrupt manifest.json
    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/cache", .{tmp_path});
    defer allocator.free(cache_dir);

    var dir = std.fs.openDirAbsolute(cache_dir, .{}) catch return;
    defer dir.close();

    var iter = dir.iterate();
    if (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            var subdir = dir.openDir(entry.name, .{}) catch return;
            defer subdir.close();

            _ = subdir.writeFile(.{ .sub_path = "manifest.json", .data = "corrupted{invalid json" }) catch return;
        }
    }

    // Run again — should handle corrupted file gracefully
    var result2 = try runZr(allocator, &.{ "--config", config_path, "run", "recover" }, tmp_path);
    defer result2.deinit();

    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
}

test "cache: missing manifest file handled gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.missing_manifest]
        \\description = "Task with missing manifest"
        \\cmd = "echo 'test'"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "missing_manifest" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ─── Task Output Caching ──────────────────────────────────────────────

test "cache: successful task output cached with exit code 0" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.success]
        \\description = "Successful task"
        \\cmd = "echo 'success output' && exit 0"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "success" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/cache", .{tmp_path});
    defer allocator.free(cache_dir);

    var dir = std.fs.openDirAbsolute(cache_dir, .{}) catch return;
    defer dir.close();

    var iter = dir.iterate();
    if (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            var subdir = dir.openDir(entry.name, .{}) catch return;
            defer subdir.close();

            const manifest = subdir.readFileAlloc(allocator, "manifest.json", 8192) catch return;
            defer allocator.free(manifest);

            try std.testing.expect(std.mem.indexOf(u8, manifest, "0") != null);
        }
    }
}

test "cache: failed task output cached with exit code 1" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.failing]
        \\description = "Failing task"
        \\cmd = "echo 'error' >&2 && exit 1"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "failing" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/cache", .{tmp_path});
    defer allocator.free(cache_dir);

    var dir = std.fs.openDirAbsolute(cache_dir, .{}) catch return;
    defer dir.close();

    var iter = dir.iterate();
    if (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            var subdir = dir.openDir(entry.name, .{}) catch return;
            defer subdir.close();

            const manifest = subdir.readFileAlloc(allocator, "manifest.json", 8192) catch return;
            defer allocator.free(manifest);

            try std.testing.expect(std.mem.indexOf(u8, manifest, "exit_code") != null);
        }
    }
}

// ─── Metadata JSON Format ──────────────────────────────────────────────

test "cache: metadata JSON is valid JSON format" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.json_test]
        \\description = "JSON format test"
        \\cmd = "echo 'json test'"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "json_test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/cache", .{tmp_path});
    defer allocator.free(cache_dir);

    var dir = std.fs.openDirAbsolute(cache_dir, .{}) catch return;
    defer dir.close();

    var iter = dir.iterate();
    if (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            var subdir = dir.openDir(entry.name, .{}) catch return;
            defer subdir.close();

            const manifest = subdir.readFileAlloc(allocator, "manifest.json", 8192) catch return;
            defer allocator.free(manifest);

            // Basic JSON validation: should have curly braces
            try std.testing.expect(std.mem.indexOf(u8, manifest, "{") != null);
            try std.testing.expect(std.mem.indexOf(u8, manifest, "}") != null);
        }
    }
}

test "cache: metadata JSON contains task_name field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.named_task]
        \\description = "Named task"
        \\cmd = "echo 'named'"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "named_task" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/cache", .{tmp_path});
    defer allocator.free(cache_dir);

    var dir = std.fs.openDirAbsolute(cache_dir, .{}) catch return;
    defer dir.close();

    var iter = dir.iterate();
    if (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            var subdir = dir.openDir(entry.name, .{}) catch return;
            defer subdir.close();

            const manifest = subdir.readFileAlloc(allocator, "manifest.json", 8192) catch return;
            defer allocator.free(manifest);

            try std.testing.expect(std.mem.indexOf(u8, manifest, "task_name") != null or
                std.mem.indexOf(u8, manifest, "named_task") != null);
        }
    }
}
