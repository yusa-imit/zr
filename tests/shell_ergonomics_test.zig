const std = @import("std");
const helpers = @import("helpers.zig");

// ============================================================================
// Smart 'zr' (no args) behavior tests
// ============================================================================

test "smart no-args: runs default task if it exists" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[task.default]
        \\script = "echo running default"
        \\
        \\[task.build]
        \\script = "echo building"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{}, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "running default") != null);
}

test "smart no-args: runs single task if only one exists" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[task.build]
        \\script = "echo building only task"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{}, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "building only task") != null);
}

test "smart no-args: shows help if no config" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{}, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Usage") != null or
        std.mem.indexOf(u8, result.stdout, "COMMANDS") != null);
}

test "smart no-args: shows help if no tasks" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workspace]
        \\members = ["*"]
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{}, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Usage") != null or
        std.mem.indexOf(u8, result.stdout, "COMMANDS") != null);
}

// ============================================================================
// History shortcuts tests (!! and !-N)
// ============================================================================

// Note: !! with actual history is tested manually - integration test would require
// real .zr_history file which is global state

test "history shortcut: !-N validates index format" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[task.test]
        \\script = "echo test"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    // Invalid: !-0
    var result1 = try helpers.runZr(std.testing.allocator, &.{"!-0"}, tmp_path);
    defer result1.deinit();
    try std.testing.expect(result1.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result1.stderr, "Invalid") != null);

    // Invalid: !-abc
    var result2 = try helpers.runZr(std.testing.allocator, &.{"!-abc"}, tmp_path);
    defer result2.deinit();
    try std.testing.expect(result2.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result2.stderr, "Invalid") != null);
}

test "history shortcut: unknown ! syntax fails gracefully" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[task.test]
        \\script = "echo test"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{"!unknown"}, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Unknown history syntax") != null);
}

// ============================================================================
// Workflow shorthand tests (w/<workflow>)
// ============================================================================

test "workflow shorthand: w/<name> runs workflow" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[task.build]
        \\script = "echo building"
        \\
        \\[task.test]
        \\script = "echo testing"
        \\
        \\[workflow.ci]
        \\tasks = ["build", "test"]
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{"w/ci"}, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "building") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "testing") != null);
}

test "workflow shorthand: w/ without name fails" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workflow.ci]
        \\tasks = ["build"]
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{"w/"}, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "missing workflow name") != null);
}

test "workflow shorthand: w/<nonexistent> fails gracefully" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[workflow.ci]
        \\tasks = ["build"]
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{"w/nonexistent"}, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "workflow") != null or
        std.mem.indexOf(u8, result.stderr, "nonexistent") != null);
}

// ============================================================================
// Combined features tests
// ============================================================================

test "combined: smart no-args respects --dry-run flag" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[task.default]
        \\script = "echo running default"
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{"--dry-run"}, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // In dry-run mode, should show what would run but not execute
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "default") != null);
}

test "combined: workflow shorthand respects --profile flag" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data =
        \\[task.build]
        \\script = "echo building"
        \\
        \\[workflow.ci]
        \\tasks = ["build"]
        \\
        \\[profiles.prod]
        \\env = { NODE_ENV = "production" }
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    var result = try helpers.runZr(std.testing.allocator, &.{ "--profile", "prod", "w/ci" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "building") != null);
}
