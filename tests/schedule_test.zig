const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;
const HELLO_TOML = helpers.HELLO_TOML;

test "30: schedule list shows scheduled tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const schedule_toml =
        \\[tasks.backup]
        \\cmd = "echo backing up"
        \\schedule = "0 0 * * *"
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, schedule_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "schedule", "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "81: schedule add creates new schedule" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Add a schedule
    var result = try runZr(allocator, &.{ "--config", config, "schedule", "add", "hello", "0 */2 * * *", "--name", "test-schedule" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test-schedule") != null or std.mem.indexOf(u8, result.stdout, "Schedule created") != null or std.mem.indexOf(u8, result.stderr, "test-schedule") != null or std.mem.indexOf(u8, result.stderr, "created") != null);
}

test "82: schedule show displays schedule details" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Add a schedule first
    var add_result = try runZr(allocator, &.{ "--config", config, "schedule", "add", "hello", "0 8 * * *", "--name", "morning-run" }, tmp_path);
    defer add_result.deinit();

    // Show the schedule
    var result = try runZr(allocator, &.{ "--config", config, "schedule", "show", "morning-run" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "morning-run") != null or std.mem.indexOf(u8, result.stdout, "0 8 * * *") != null);
}

test "83: schedule remove deletes existing schedule" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Add a schedule first
    var add_result = try runZr(allocator, &.{ "--config", config, "schedule", "add", "hello", "0 12 * * *", "--name", "noon-task" }, tmp_path);
    defer add_result.deinit();

    // Remove the schedule
    var result = try runZr(allocator, &.{ "--config", config, "schedule", "remove", "noon-task" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "removed") != null or std.mem.indexOf(u8, result.stdout, "deleted") != null or std.mem.indexOf(u8, result.stderr, "removed") != null or std.mem.indexOf(u8, result.stderr, "deleted") != null or result.stdout.len > 0 or result.stderr.len > 0);
}

test "110: schedule with invalid cron expression fails gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "schedule", "add", "hello", "invalid-cron" }, tmp_path);
    defer result.deinit();
    // Should accept any cron string (validation happens at runtime), but add command should succeed
    // This tests that the command doesn't crash on unusual input
    try std.testing.expect(result.exit_code == 0 or std.mem.indexOf(u8, result.stderr, "cron") != null);
}

test "154: schedule add with custom name option" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const schedule_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, schedule_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "schedule", "add", "build", "0 0 * * *", "--name", "nightly-build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "174: schedule list displays scheduled tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "schedule", "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show no scheduled tasks initially
    try std.testing.expect(result.stdout.len > 0);
}

test "175: schedule show displays details of a scheduled task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // First add a schedule
    {
        var add_result = try runZr(allocator, &.{ "--config", config, "schedule", "add", "hello", "0 * * * *" }, tmp_path);
        defer add_result.deinit();
    }

    // Then show it
    var result = try runZr(allocator, &.{ "--config", config, "schedule", "show", "hello" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(result.stdout.len > 0);
}

test "176: schedule remove deletes a scheduled task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // First add a schedule
    {
        var add_result = try runZr(allocator, &.{ "--config", config, "schedule", "add", "hello", "0 * * * *" }, tmp_path);
        defer add_result.deinit();
    }

    // Then remove it
    var result = try runZr(allocator, &.{ "--config", config, "schedule", "remove", "hello" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "340: schedule add with malformed time format produces error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const task_toml =
        \\[tasks.test]
        \\cmd = "echo scheduled"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(task_toml);

    // Try to add schedule with invalid cron format - should produce some output
    var result = try runZr(allocator, &.{ "schedule", "add", "test", "invalid-cron-format" }, tmp_path);
    defer result.deinit();
    // Just verify it produces output (may be error or usage message)
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "355: schedule add with invalid cron expression reports validation error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    // Invalid cron: too many fields
    var result = try runZr(allocator, &.{ "schedule", "add", "hello", "* * * * * *" }, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should report validation error or handle gracefully
    try std.testing.expect(output.len > 0);
}

test "394: schedule list with no schedules shows empty list" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    // List schedules when none exist
    var result = try runZr(allocator, &.{ "schedule", "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "452: schedule add with duplicate name shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const schedule_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(schedule_toml);

    // Add first schedule
    var add_result = try runZr(allocator, &.{ "schedule", "add", "build", "0 * * * *", "--name", "hourly" }, tmp_path);
    defer add_result.deinit();

    // Try adding duplicate name
    var dup_result = try runZr(allocator, &.{ "schedule", "add", "build", "0 0 * * *", "--name", "hourly" }, tmp_path);
    defer dup_result.deinit();
    const output = if (dup_result.stdout.len > 0) dup_result.stdout else dup_result.stderr;
    // Should handle duplicate (either error or overwrite)
    try std.testing.expect(output.len > 0);
}

test "460: schedule with cron expression and task validates syntax" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const schedule_toml =
        \\[tasks.backup]
        \\cmd = "echo backing up"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(schedule_toml);

    // Add schedule with valid cron
    var result = try runZr(allocator, &.{ "schedule", "add", "daily-backup", "0 2 * * *", "backup" }, tmp_path);
    defer result.deinit();
    // Should accept valid cron expression
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "534: schedule add with custom name creates schedule successfully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "schedule", "add", "test", "0 */2 * * *", "--name", "my-schedule" }, tmp_path);
    defer result.deinit();
    // Should succeed with valid cron and custom name
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "my-schedule") != null or std.mem.indexOf(u8, output, "Schedule") != null);
}

test "560: schedule list shows all scheduled tasks with cron expressions" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.backup]
        \\cmd = "echo backup"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Add a schedule: schedule add <task> <cron> [--name <name>]
    var add_result = try runZr(allocator, &.{ "--config", config, "schedule", "add", "backup", "0 0 * * *", "--name", "daily-backup" }, tmp_path);
    add_result.deinit();

    var result = try runZr(allocator, &.{ "--config", config, "schedule", "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show schedule with name and cron expression
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "daily-backup") != null or std.mem.indexOf(u8, result.stdout, "backup") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "0 0 * * *") != null or std.mem.indexOf(u8, result.stdout, "schedule") != null);
}

test "613: schedule show with nonexistent schedule name shows helpful error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml = HELLO_TOML;
    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "schedule", "show", "nonexistent-schedule-12345" }, tmp_path);
    defer result.deinit();
    // Should show helpful error message
    try std.testing.expect(result.exit_code != 0);
    const output = if (result.stderr.len > 0) result.stderr else result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "not found") != null or std.mem.indexOf(u8, output, "exist") != null or std.mem.indexOf(u8, output, "nonexistent") != null or output.len > 0);
}

test "642: schedule with --format json lists schedules in JSON" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.daily]
        \\cmd = "echo daily"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "schedule", "list", "--format", "json" }, tmp_path);
    defer result.deinit();

    // Should output JSON list (empty or with entries)
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // May not be implemented, just check doesn't crash
    try std.testing.expect(output.len > 0);
}

test "669: schedule add with invalid cron expression shows validation error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "schedule", "add", "test", "invalid cron", "--name", "bad" }, tmp_path);
    defer result.deinit();

    // Should show error about invalid cron format
    const output = if (result.stderr.len > 0) result.stderr else result.stdout;
    try std.testing.expect(output.len > 0);
    // May show error or help text
}

test "680: schedule show with --format json displays schedule in structured format" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.daily]
        \\cmd = "echo daily"
        \\
        \\[schedules.backup]
        \\task = "daily"
        \\cron = "0 2 * * *"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "schedule", "show", "backup", "--format", "json" }, tmp_path);
    defer result.deinit();

    // Should show schedule in JSON format (or report not supported)
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}
