const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Task Dependency Visualization Enhancements Tests ──────────────────────────
//
// Tests for zr graph command enhancements (v1.95.0 milestone):
// 1. --format=mermaid outputs Mermaid flowchart
// 2. --group=<name> filters to namespace prefix tasks
// 3. --from=<task> shows task and all downstream dependents
// 4. --to=<task> shows task and all upstream dependencies
// 5. --depth=<n> limits traversal depth
// 6. --cycles-only shows cyclic tasks or "no cycles" message
// 7. --format=dot combined with --from=<task>
// 8. --format=mermaid combined with --group=<name>
//

test "25000: graph --format=mermaid outputs Mermaid flowchart" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.a]
        \\cmd = "echo a"
        \\
        \\[tasks.b]
        \\cmd = "echo b"
        \\deps = ["a"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--type=tasks", "--format=mermaid" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Mermaid format should start with "flowchart"
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "flowchart") != null);
    // Should contain both task names
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "a") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "b") != null);
}

test "25001: graph --group=build filters to build namespace tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build.compile]
        \\cmd = "echo compile"
        \\
        \\[tasks.build.link]
        \\cmd = "echo link"
        \\
        \\[tasks.test.run]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--type=tasks", "--group=build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should include build namespace tasks
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build.compile") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build.link") != null);
    // Should NOT include test.run
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test.run") == null);
}

test "25002: graph --from=<task> shows task and downstream dependents" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.a]
        \\cmd = "echo a"
        \\
        \\[tasks.b]
        \\cmd = "echo b"
        \\deps = ["a"]
        \\
        \\[tasks.c]
        \\cmd = "echo c"
        \\deps = ["b"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--type=tasks", "--from=a" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain all tasks in the downstream chain from a
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "a") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "b") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "c") != null);
}

test "25003: graph --to=<task> shows task and upstream dependencies" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.a]
        \\cmd = "echo a"
        \\
        \\[tasks.b]
        \\cmd = "echo b"
        \\deps = ["a"]
        \\
        \\[tasks.c]
        \\cmd = "echo c"
        \\deps = ["b"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--type=tasks", "--to=c" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain all tasks in the upstream chain to c
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "a") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "b") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "c") != null);
}

test "25004: graph --depth=1 limits dependency traversal depth" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.a]
        \\cmd = "echo a"
        \\
        \\[tasks.b]
        \\cmd = "echo b"
        \\deps = ["a"]
        \\
        \\[tasks.c]
        \\cmd = "echo c"
        \\deps = ["b"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--type=tasks", "--from=a", "--depth=1" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain a and b (direct dependency)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "a") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "b") != null);
    // Should NOT contain c (beyond depth 1)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "c") == null);
}

test "25005: graph --cycles-only with no cycles shows no cycles message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.a]
        \\cmd = "echo a"
        \\
        \\[tasks.b]
        \\cmd = "echo b"
        \\deps = ["a"]
        \\
        \\[tasks.c]
        \\cmd = "echo c"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--type=tasks", "--cycles-only" }, tmp_path);
    defer result.deinit();

    // Should succeed (no cycles is valid state)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // graph.zig emits "No cycles detected.\n" when --cycles-only finds no cycles.
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "No cycles detected") != null);
}

test "25006: graph --format=dot with --from=<task> shows subgraph" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.a]
        \\cmd = "echo a"
        \\
        \\[tasks.b]
        \\cmd = "echo b"
        \\deps = ["a"]
        \\
        \\[tasks.c]
        \\cmd = "echo c"
        \\
        \\[tasks.d]
        \\cmd = "echo d"
        \\deps = ["b"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--type=tasks", "--format=dot", "--from=b" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain b and d (d depends on b)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"b\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"d\"") != null);
    // Should NOT contain a or c (not in the subgraph from b)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"a\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "\"c\"") == null);
}

test "25007: graph --format=mermaid with --group=build shows filtered mermaid" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build.compile]
        \\cmd = "echo compile"
        \\
        \\[tasks.build.link]
        \\cmd = "echo link"
        \\deps = ["build.compile"]
        \\
        \\[tasks.test.run]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "graph", "--type=tasks", "--format=mermaid", "--group=build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain mermaid flowchart keyword
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "flowchart") != null);
    // Should contain build namespace tasks
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build.compile") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build.link") != null);
    // Should NOT contain test.run
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test.run") == null);
}
