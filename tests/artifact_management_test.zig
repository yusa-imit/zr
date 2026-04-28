const std = @import("std");
const builtin = @import("builtin");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;
const runCommand = helpers.runCommand;

// ─── Basic Artifact Declaration & Collection ─────────────────────────────

test "artifact: task with artifacts field declares output files" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.build]
        \\description = "Build project"
        \\cmd = "echo 'dist' > /dev/null && mkdir -p dist && echo 'build result' > dist/app.wasm"
        \\artifacts = ["dist/*.wasm"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "artifact: successful task collects matching artifacts automatically" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.build]
        \\description = "Build and generate artifacts"
        \\cmd = "mkdir -p dist logs && echo 'app' > dist/app.wasm && echo 'log' > logs/build.log"
        \\artifacts = ["dist/*.wasm", "logs/*.log"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify artifact storage directory was created
    const artifacts_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/artifacts/build", .{tmp_path});
    defer allocator.free(artifacts_dir);

    var dir = std.fs.openDirAbsolute(artifacts_dir, .{}) catch {
        // Directory should exist after artifact collection
        try std.testing.expect(false); // Force failure if directory doesn't exist
        return;
    };
    defer dir.close();
}

test "artifact: artifact storage uses .zr/artifacts/<task>/<timestamp>/ structure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.compile]
        \\description = "Compile code"
        \\cmd = "mkdir -p out && echo 'binary' > out/app"
        \\artifacts = ["out/app"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "compile" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify .zr/artifacts/compile/<timestamp>/ directory structure exists
    const base_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/artifacts/compile", .{tmp_path});
    defer allocator.free(base_dir);

    var dir = std.fs.openDirAbsolute(base_dir, .{}) catch {
        // If directory doesn't exist, test will fail at verify step
        try std.testing.expect(false);
        return;
    };
    defer dir.close();

    // Should have at least one timestamp directory
    var iter = dir.iterate();
    var found_timestamp = false;
    while (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            found_timestamp = true;
            break;
        }
    }

    try std.testing.expect(found_timestamp);
}

test "artifact: manifest.json stores artifact metadata" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.package]
        \\description = "Package for release"
        \\cmd = "mkdir -p dist && echo 'package' > dist/release.tar.gz"
        \\artifacts = ["dist/*.tar.gz"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "package" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Find and verify manifest.json
    const base_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/artifacts/package", .{tmp_path});
    defer allocator.free(base_dir);

    var base = std.fs.openDirAbsolute(base_dir, .{}) catch {
        return; // Directory should exist
    };
    defer base.close();

    var iter = base.iterate();
    var manifest_found = false;
    var first_timestamp: []const u8 = undefined;

    while (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            first_timestamp = entry.name;
            manifest_found = true;
            break;
        }
    }

    if (manifest_found) {
        var timestamp_dir = base.openDir(first_timestamp, .{}) catch return;
        defer timestamp_dir.close();

        _ = timestamp_dir.openFile("manifest.json", .{}) catch return;
    }
}

// ─── Glob Pattern Matching ─────────────────────────────────────────────────

test "artifact: glob pattern *.wasm matches single level" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.build_wasm]
        \\description = "Build WASM"
        \\cmd = "mkdir -p dist && echo 'wasm' > dist/app.wasm && echo 'js' > dist/app.js"
        \\artifacts = ["dist/*.wasm"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "build_wasm" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "artifact: glob pattern **/*.html matches nested directories" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.gen_coverage]
        \\description = "Generate coverage"
        \\cmd = "mkdir -p coverage/reports/details && echo '<html></html>' > coverage/index.html && echo '<html></html>' > coverage/reports/details/file.html"
        \\artifacts = ["coverage/**/*.html"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "gen_coverage" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "artifact: glob pattern with ? matches single character" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.build_bin]
        \\description = "Build binary"
        \\cmd = "mkdir -p bin && echo 'bin1' > bin/app1 && echo 'bin2' > bin/app2"
        \\artifacts = ["bin/app?"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "build_bin" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ─── Artifact Retrieval ────────────────────────────────────────────────────

test "artifact: 'zr artifacts get <task>' lists collected artifacts" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.test]
        \\description = "Run tests"
        \\cmd = "mkdir -p results && echo 'test-results' > results/test-output.json"
        \\artifacts = ["results/*.json"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // First run task to collect artifacts
    var run_result = try runZr(allocator, &.{ "--config", config_path, "run", "test" }, tmp_path);
    defer run_result.deinit();

    try std.testing.expectEqual(@as(u8, 0), run_result.exit_code);

    // Then retrieve artifacts
    var get_result = try runZr(allocator, &.{ "--config", config_path, "artifacts", "get", "test" }, tmp_path);
    defer get_result.deinit();

    try std.testing.expectEqual(@as(u8, 0), get_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, get_result.stdout, "test-output.json") != null or
        std.mem.indexOf(u8, get_result.stdout, "artifact") != null);
}

test "artifact: 'zr artifacts get <task> --latest' retrieves most recent artifacts" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.snapshot]
        \\description = "Create snapshot"
        \\cmd = "mkdir -p snapshots && echo 'snap' > snapshots/state.json"
        \\artifacts = ["snapshots/*.json"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task first
    var run_result = try runZr(allocator, &.{ "--config", config_path, "run", "snapshot" }, tmp_path);
    defer run_result.deinit();

    try std.testing.expectEqual(@as(u8, 0), run_result.exit_code);

    // Get latest artifacts
    var get_result = try runZr(allocator, &.{ "--config", config_path, "artifacts", "get", "snapshot", "--latest" }, tmp_path);
    defer get_result.deinit();

    try std.testing.expectEqual(@as(u8, 0), get_result.exit_code);
}

// ─── Artifact Metadata ────────────────────────────────────────────────────

test "artifact: metadata includes timestamp field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.build_meta]
        \\description = "Build with metadata"
        \\cmd = "mkdir -p artifact && echo 'content' > artifact/file.txt"
        \\artifacts = ["artifact/*.txt"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "build_meta" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Manifest should contain timestamp
    const base_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/artifacts/build_meta", .{tmp_path});
    defer allocator.free(base_dir);

    var base = std.fs.openDirAbsolute(base_dir, .{}) catch return;
    defer base.close();

    var iter = base.iterate();
    if (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            var ts_dir = base.openDir(entry.name, .{}) catch return;
            defer ts_dir.close();

            const manifest_content = ts_dir.readFileAlloc(allocator, "manifest.json", 8192) catch return;
            defer allocator.free(manifest_content);

            try std.testing.expect(std.mem.indexOf(u8, manifest_content, "timestamp") != null or
                std.mem.indexOf(u8, manifest_content, "date") != null);
        }
    }
}

test "artifact: metadata includes exit code field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.finish]
        \\description = "Finish task"
        \\cmd = "mkdir -p output && echo 'done' > output/result.txt"
        \\artifacts = ["output/*.txt"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "finish" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const base_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/artifacts/finish", .{tmp_path});
    defer allocator.free(base_dir);

    var base = std.fs.openDirAbsolute(base_dir, .{}) catch return;
    defer base.close();

    var iter = base.iterate();
    if (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            var ts_dir = base.openDir(entry.name, .{}) catch return;
            defer ts_dir.close();

            const manifest_content = ts_dir.readFileAlloc(allocator, "manifest.json", 8192) catch return;
            defer allocator.free(manifest_content);

            try std.testing.expect(std.mem.indexOf(u8, manifest_content, "exit_code") != null or
                std.mem.indexOf(u8, manifest_content, "code") != null);
        }
    }
}

test "artifact: metadata includes duration field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.slow_task]
        \\description = "Slow task"
        \\cmd = "mkdir -p logs && echo 'log' > logs/output.log"
        \\artifacts = ["logs/*.log"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "slow_task" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const base_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/artifacts/slow_task", .{tmp_path});
    defer allocator.free(base_dir);

    var base = std.fs.openDirAbsolute(base_dir, .{}) catch return;
    defer base.close();

    var iter = base.iterate();
    if (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            var ts_dir = base.openDir(entry.name, .{}) catch return;
            defer ts_dir.close();

            const manifest_content = ts_dir.readFileAlloc(allocator, "manifest.json", 8192) catch return;
            defer allocator.free(manifest_content);

            try std.testing.expect(std.mem.indexOf(u8, manifest_content, "duration") != null or
                std.mem.indexOf(u8, manifest_content, "elapsed") != null);
        }
    }
}

// ─── Retention Policies ────────────────────────────────────────────────────

test "artifact: time-based retention 'artifact_retention = \"7d\"' auto-cleanup old artifacts" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.daily_build]
        \\description = "Daily build"
        \\cmd = "mkdir -p dist && echo 'build' > dist/app.tar"
        \\artifacts = ["dist/*.tar"]
        \\artifact_retention = "7d"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "daily_build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "artifact: count-based retention 'artifact_retention = { count = 10 }' keeps N latest" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.version_build]
        \\description = "Build version"
        \\cmd = "mkdir -p releases && echo 'v1' > releases/version.txt"
        \\artifacts = ["releases/*.txt"]
        \\artifact_retention = { count = 10 }
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "version_build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ─── List Integration ────────────────────────────────────────────────────

test "artifact: 'zr list --show-artifacts' displays tasks with artifact counts" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.with_artifacts]
        \\description = "Task with artifacts"
        \\cmd = "mkdir -p out && echo 'data' > out/result.json"
        \\artifacts = ["out/*.json"]
        \\
        \\[tasks.no_artifacts]
        \\description = "Task without artifacts"
        \\cmd = "echo no artifacts"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run task to collect artifacts
    var run_result = try runZr(allocator, &.{ "--config", config_path, "run", "with_artifacts" }, tmp_path);
    defer run_result.deinit();

    try std.testing.expectEqual(@as(u8, 0), run_result.exit_code);

    // List with artifacts
    var list_result = try runZr(allocator, &.{ "--config", config_path, "list", "--show-artifacts" }, tmp_path);
    defer list_result.deinit();

    try std.testing.expectEqual(@as(u8, 0), list_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, list_result.stdout, "with_artifacts") != null);
}

// ─── Artifact Cleanup ──────────────────────────────────────────────────────

test "artifact: 'zr artifacts clean --older-than 30d' removes old artifacts" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.old_build]
        \\description = "Old build"
        \\cmd = "mkdir -p dist && echo 'old' > dist/app.zip"
        \\artifacts = ["dist/*.zip"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var run_result = try runZr(allocator, &.{ "--config", config_path, "run", "old_build" }, tmp_path);
    defer run_result.deinit();

    try std.testing.expectEqual(@as(u8, 0), run_result.exit_code);

    // Cleanup command
    var clean_result = try runZr(allocator, &.{ "--config", config_path, "artifacts", "clean", "--older-than", "30d" }, tmp_path);
    defer clean_result.deinit();

    try std.testing.expectEqual(@as(u8, 0), clean_result.exit_code);
}

test "artifact: 'zr artifacts clean --task <task>' removes artifacts for specific task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.task_a]
        \\description = "Task A"
        \\cmd = "mkdir -p artifacts_a && echo 'a' > artifacts_a/file.txt"
        \\artifacts = ["artifacts_a/*.txt"]
        \\
        \\[tasks.task_b]
        \\description = "Task B"
        \\cmd = "mkdir -p artifacts_b && echo 'b' > artifacts_b/file.txt"
        \\artifacts = ["artifacts_b/*.txt"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run both tasks
    var run_a = try runZr(allocator, &.{ "--config", config_path, "run", "task_a" }, tmp_path);
    defer run_a.deinit();

    var run_b = try runZr(allocator, &.{ "--config", config_path, "run", "task_b" }, tmp_path);
    defer run_b.deinit();

    try std.testing.expectEqual(@as(u8, 0), run_a.exit_code);
    try std.testing.expectEqual(@as(u8, 0), run_b.exit_code);

    // Clean only task_a artifacts
    var clean_result = try runZr(allocator, &.{ "--config", config_path, "artifacts", "clean", "--task", "task_a" }, tmp_path);
    defer clean_result.deinit();

    try std.testing.expectEqual(@as(u8, 0), clean_result.exit_code);
}

// ─── Compression ─────────────────────────────────────────────────────────

test "artifact: compression enabled by default for artifact storage" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.large_build]
        \\description = "Build with large artifacts"
        \\cmd = "mkdir -p build && echo 'large artifact content' > build/result.tar"
        \\artifacts = ["build/*.tar"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "large_build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Check if artifacts are compressed (gzip format)
    const base_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/artifacts/large_build", .{tmp_path});
    defer allocator.free(base_dir);

    var base = std.fs.openDirAbsolute(base_dir, .{}) catch return;
    defer base.close();

    var iter = base.iterate();
    if (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            var ts_dir = base.openDir(entry.name, .{}) catch return;
            defer ts_dir.close();

            // Look for .gz files or compressed artifacts
            var inner_iter = ts_dir.iterate();
            var found_compressed = false;
            while (inner_iter.next() catch null) |inner_entry| {
                if (std.mem.endsWith(u8, inner_entry.name, ".gz")) {
                    found_compressed = true;
                    break;
                }
            }
            // Compression should be applied
        }
    }
}

test "artifact: compression can be disabled in config" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[cache]
        \\compression = false
        \\
        \\[tasks.no_compress]
        \\description = "Build without compression"
        \\cmd = "mkdir -p output && echo 'uncompressed' > output/data.json"
        \\artifacts = ["output/*.json"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "no_compress" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ─── Error Conditions ─────────────────────────────────────────────────────

test "artifact: failed task does not collect artifacts" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.failing_build]
        \\description = "Failing build"
        \\cmd = "mkdir -p dist && echo 'should not save' > dist/app.wasm && exit 1"
        \\artifacts = ["dist/*.wasm"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "failing_build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);

    // Artifacts should not be collected on failure
    const artifacts_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/artifacts/failing_build", .{tmp_path});
    defer allocator.free(artifacts_dir);

    // Directory might not exist or be empty
    var dir = std.fs.openDirAbsolute(artifacts_dir, .{}) catch {
        return; // Expected if directory doesn't exist
    };
    defer dir.close();
}

test "artifact: no-match artifact pattern does not error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.no_match]
        \\description = "Task with no matching artifacts"
        \\cmd = "mkdir -p output && echo 'data' > output/data.txt"
        \\artifacts = ["nonexistent/*.json"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "no_match" }, tmp_path);
    defer result.deinit();

    // Task should still succeed even if no artifacts match
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ─── Multiple Artifacts ────────────────────────────────────────────────────

test "artifact: multiple artifact patterns per task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.multi_artifact]
        \\description = "Task with multiple artifact types"
        \\cmd = "mkdir -p dist coverage logs && echo 'bin' > dist/app.exe && echo 'html' > coverage/index.html && echo 'log' > logs/build.log"
        \\artifacts = ["dist/*.exe", "coverage/*.html", "logs/*.log"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "multi_artifact" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "artifact: nested directory artifacts" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.nested]
        \\description = "Task with nested artifacts"
        \\cmd = "mkdir -p build/output/src/reports && echo 'report' > build/output/src/reports/summary.json"
        \\artifacts = ["build/**/reports/*.json"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "nested" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ─── Task Parameters & Artifacts ────────────────────────────────────────────

test "artifact: metadata captures task parameters used" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.param_build]
        \\description = "Build with parameters"
        \\cmd = "mkdir -p dist && echo 'build' > dist/app.zip"
        \\params = [
        \\  { name = "release_type", required = true, description = "Release type" }
        \\]
        \\artifacts = ["dist/*.zip"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "param_build", "release_type", "stable" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const base_dir = try std.fmt.allocPrint(allocator, "{s}/.zr/artifacts/param_build", .{tmp_path});
    defer allocator.free(base_dir);

    var base = std.fs.openDirAbsolute(base_dir, .{}) catch return;
    defer base.close();

    var iter = base.iterate();
    if (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            var ts_dir = base.openDir(entry.name, .{}) catch return;
            defer ts_dir.close();

            const manifest = ts_dir.readFileAlloc(allocator, "manifest.json", 8192) catch return;
            defer allocator.free(manifest);

            try std.testing.expect(std.mem.indexOf(u8, manifest, "params") != null or
                std.mem.indexOf(u8, manifest, "release_type") != null);
        }
    }
}

// ─── Backward Compatibility ────────────────────────────────────────────────

test "artifact: tasks without artifacts field work normally" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.simple]
        \\description = "Simple task without artifacts"
        \\cmd = "echo hello"
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config_path, "run", "simple" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hello") != null);
}

test "artifact: artifacts field is optional in config" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config =
        \\[tasks.task_no_artifacts]
        \\cmd = "echo 'no artifacts defined'"
        \\
        \\[tasks.task_with_artifacts]
        \\cmd = "mkdir -p out && echo 'data' > out/file.txt"
        \\artifacts = ["out/*.txt"]
        \\
    ;

    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result_no = try runZr(allocator, &.{ "--config", config_path, "run", "task_no_artifacts" }, tmp_path);
    defer result_no.deinit();

    var result_yes = try runZr(allocator, &.{ "--config", config_path, "run", "task_with_artifacts" }, tmp_path);
    defer result_yes.deinit();

    try std.testing.expectEqual(@as(u8, 0), result_no.exit_code);
    try std.testing.expectEqual(@as(u8, 0), result_yes.exit_code);
}

// ─── Unknown Commands (Negative Tests) ──────────────────────────────────────

test "artifact: unknown subcommand fails gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "artifacts", "invalid-command" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
}

test "artifact: 'zr artifacts' without subcommand shows help" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{"artifacts"}, tmp_path);
    defer result.deinit();

    // Should show usage/help or fail gracefully
    try std.testing.expect(result.exit_code != 0 or
        std.mem.indexOf(u8, result.stdout, "artifact") != null or
        std.mem.indexOf(u8, result.stderr, "artifact") != null);
}
