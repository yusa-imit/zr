const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── Task Priority Tests ───────────────────────────────────────────────────────
//
// Tests for `priority` task field (v1.105.0):
//
// 34000: priority badge appears in zr list for non-zero priority tasks
// 34001: higher priority tasks run first with --jobs 1
// 34002: default priority (no field) works normally
// 34003: negative priority tasks run after default-priority tasks
// 34004: zr list --sort=priority shows highest priority first
// 34005: dry-run shows tasks regardless of priority
//

// Test 34000: priority badges appear in list for non-zero priority tasks
test "priority: list shows badge for non-zero priority" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.slow]
        \\cmd = "echo slow"
        \\priority = -5
        \\
        \\[tasks.fast]
        \\cmd = "echo fast"
        \\priority = 10
        \\
        \\[tasks.normal]
        \\cmd = "echo normal"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    const result = try runZr(testing.allocator, &.{ "--config", config, "list" }, tmp_path);
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    try testing.expect(result.exit_code == 0);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "[p:10]") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "[p:-5]") != null);
    // default priority (0) shows no badge
    try testing.expect(std.mem.indexOf(u8, result.stdout, "[p:0]") == null);
}

// Test 34001: tasks with higher priority run first within a topo level (--jobs 1)
test "priority: higher priority runs first with --jobs 1" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    const order_file = try std.fs.path.join(testing.allocator, &.{ tmp_path, "order.txt" });
    defer testing.allocator.free(order_file);

    const toml = try std.fmt.allocPrint(testing.allocator,
        \\[tasks.low]
        \\cmd = "echo low >> {s}"
        \\priority = 1
        \\
        \\[tasks.high]
        \\cmd = "echo high >> {s}"
        \\priority = 100
        \\
        \\[tasks.mid]
        \\cmd = "echo mid >> {s}"
        \\priority = 50
        \\
        \\[tasks.all]
        \\cmd = "echo done"
        \\deps = ["low", "high", "mid"]
    , .{ order_file, order_file, order_file });
    defer testing.allocator.free(toml);

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const result = try runZr(testing.allocator, &.{ "--config", config, "run", "--jobs", "1", "all" }, tmp_path);
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expect(result.exit_code == 0);

    const order_content = try tmp.dir.readFileAlloc(testing.allocator, "order.txt", 1024);
    defer testing.allocator.free(order_content);

    // high(100) → mid(50) → low(1)
    const high_pos = std.mem.indexOf(u8, order_content, "high") orelse return error.NotFound;
    const mid_pos = std.mem.indexOf(u8, order_content, "mid") orelse return error.NotFound;
    const low_pos = std.mem.indexOf(u8, order_content, "low") orelse return error.NotFound;
    try testing.expect(high_pos < mid_pos);
    try testing.expect(mid_pos < low_pos);
}

// Test 34002: default priority (0) — tasks run without error
test "priority: default priority (no field) works normally" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.a]
        \\cmd = "echo a"
        \\
        \\[tasks.b]
        \\cmd = "echo b"
        \\deps = ["a"]
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    const result = try runZr(testing.allocator, &.{ "--config", config, "run", "b" }, tmp_path);
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expect(result.exit_code == 0);
}

// Test 34003: negative priority runs after zero-priority tasks
test "priority: negative priority runs after default priority tasks" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    const order_file = try std.fs.path.join(testing.allocator, &.{ tmp_path, "order.txt" });
    defer testing.allocator.free(order_file);

    const toml = try std.fmt.allocPrint(testing.allocator,
        \\[tasks.normal]
        \\cmd = "echo normal >> {s}"
        \\
        \\[tasks.last]
        \\cmd = "echo last >> {s}"
        \\priority = -10
        \\
        \\[tasks.all]
        \\cmd = "echo done"
        \\deps = ["normal", "last"]
    , .{ order_file, order_file });
    defer testing.allocator.free(toml);

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const result = try runZr(testing.allocator, &.{ "--config", config, "run", "--jobs", "1", "all" }, tmp_path);
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expect(result.exit_code == 0);

    const order_content = try tmp.dir.readFileAlloc(testing.allocator, "order.txt", 1024);
    defer testing.allocator.free(order_content);

    const normal_pos = std.mem.indexOf(u8, order_content, "normal") orelse return error.NotFound;
    const last_pos = std.mem.indexOf(u8, order_content, "last") orelse return error.NotFound;
    try testing.expect(normal_pos < last_pos);
}

// Test 34004: zr list --sort=priority orders by priority descending
test "priority: list --sort=priority shows highest priority first" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.z_low]
        \\cmd = "echo z"
        \\priority = 1
        \\
        \\[tasks.a_high]
        \\cmd = "echo a"
        \\priority = 100
        \\
        \\[tasks.m_mid]
        \\cmd = "echo m"
        \\priority = 50
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    const result = try runZr(testing.allocator, &.{ "--config", config, "list", "--sort=priority" }, tmp_path);
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expect(result.exit_code == 0);

    const high_pos = std.mem.indexOf(u8, result.stdout, "a_high") orelse return error.NotFound;
    const mid_pos = std.mem.indexOf(u8, result.stdout, "m_mid") orelse return error.NotFound;
    const low_pos = std.mem.indexOf(u8, result.stdout, "z_low") orelse return error.NotFound;
    try testing.expect(high_pos < mid_pos);
    try testing.expect(mid_pos < low_pos);
}

// Test 34005: priority works with dry-run
test "priority: dry-run shows tasks regardless of priority" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.critical]
        \\cmd = "echo critical"
        \\priority = 999
        \\
        \\[tasks.normal]
        \\cmd = "echo normal"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    const result = try runZr(testing.allocator, &.{ "--config", config, "run", "--dry-run", "critical" }, tmp_path);
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expect(result.exit_code == 0);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "critical") != null);
}
