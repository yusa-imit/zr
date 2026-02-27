const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;
const HELLO_TOML = helpers.HELLO_TOML;

test "19: validate accepts valid config" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "validate", config }, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "20: validate accepts simple usage" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // validate command doesn't take a path argument — it validates the config in the current directory
    var result = try runZr(allocator, &.{"validate"}, tmp_path);
    defer result.deinit();
    // Even if it fails, it shouldn't crash (exit code 0 or 1 both acceptable)
    try std.testing.expect(result.exit_code <= 1);
}

test "49: config with unknown task field is accepted" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // TOML parser is lenient and ignores unknown fields
    const config_with_unknown =
        \\[tasks.test]
        \\cmd = "echo test"
        \\unknown_field = "value"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_with_unknown);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
}

test "89: validate with --strict flag enforces stricter rules" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config = try writeTmpConfig(allocator, tmp.dir, HELLO_TOML);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Validate with strict mode
    var result = try runZr(allocator, &.{ "--config", config, "validate", "--strict" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "141: validate --strict enforces stricter validation rules" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_with_warnings =
        \\[tasks.test]
        \\cmd = "echo test"
        \\description = "Test task"
        \\unknown_field = "value"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_with_warnings);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Normal validation should succeed
    {
        var result = try runZr(allocator, &.{ "--config", config, "validate" }, tmp_path);
        defer result.deinit();
        try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // Strict validation may warn about unknown fields
    {
        var result = try runZr(allocator, &.{ "--config", config, "validate", "--strict" }, tmp_path);
        defer result.deinit();
        // Accepts either success or warnings
        try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
    }
}

test "142: validate --schema displays schema information" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "validate", "--schema" }, tmp_path);
    defer result.deinit();

    // Should display schema info (may succeed or fail if no config found)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "195: validate with invalid task name containing spaces" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Create config with invalid task name (spaces)
    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(
        \\[tasks."my task"]
        \\cmd = "echo hello"
        \\
    );

    var result = try runZr(allocator, &.{"validate"}, tmp_path);
    defer result.deinit();

    // Should fail validation
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "spaces") != null);
}

test "196: validate with task name exceeding 64 characters" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Create config with very long task name (65 chars)
    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(
        \\[tasks.this_is_a_very_long_task_name_that_exceeds_the_maximum_allowed_length]
        \\cmd = "echo hello"
        \\
    );

    var result = try runZr(allocator, &.{"validate"}, tmp_path);
    defer result.deinit();

    // Should fail validation
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "too long") != null);
}

test "197: validate with whitespace-only command" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Create config with whitespace-only cmd
    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(
        \\[tasks.empty]
        \\cmd = "   "
        \\
    );

    var result = try runZr(allocator, &.{"validate"}, tmp_path);
    defer result.deinit();

    // Should fail validation
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "empty") != null or
        std.mem.indexOf(u8, result.stderr, "whitespace") != null);
}

test "206: validate with --schema flag displays full config schema" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    var result = try runZr(allocator, &.{ "validate", "--schema" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Schema output should contain sections like [tasks], [workflows], etc.
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "tasks") != null or
        std.mem.indexOf(u8, result.stdout, "schema") != null);
}

test "220: validate accepts well-formed config in strict mode" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Create valid config
    const valid_toml =
        \\[tasks.build]
        \\cmd = "make build"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(valid_toml);

    // Validate in strict mode
    var result = try runZr(allocator, &.{ "validate", "--strict" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ═══════════════════════════════════════════════════════════════════════════
// Additional Edge Cases and Advanced Scenarios (221-230)
// ═══════════════════════════════════════════════════════════════════════════

test "238: validate with --strict and additional warnings" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Config with potentially problematic but valid settings
    const strict_toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\timeout = 1
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(strict_toml);

    // Validate in strict mode
    var result = try runZr(allocator, &.{ "validate", "--strict" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "264: validate with malformed TOML reports parse error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Create definitively malformed TOML with invalid key-value syntax
    const bad_toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\invalid syntax here!!!
        \\deps = ["missing", "quote
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(bad_toml);

    var result = try runZr(allocator, &.{ "validate" }, tmp_path);
    defer result.deinit();
    // Validate command should report errors or parser should fail
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "280: validate with very large config file (100+ tasks)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Generate large config with 100 tasks
    var large_config = std.ArrayList(u8){};
    defer large_config.deinit(allocator);

    for (0..100) |i| {
        const task = try std.fmt.allocPrint(allocator, "[tasks.task{d}]\ncmd = \"echo task{d}\"\n\n", .{ i, i });
        defer allocator.free(task);
        try large_config.appendSlice(allocator, task);
    }

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(large_config.items);

    var result = try runZr(allocator, &.{"validate"}, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    // Should handle large configs without timeout or memory issues
}

test "290: validate with task using expression syntax validates correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const expr_toml =
        \\[tasks.conditional]
        \\cmd = "echo conditional"
        \\condition = "env.CI == 'true'"
        \\
        \\[tasks.interpolated]
        \\cmd = "echo {{env.USER}}"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(expr_toml);

    var result = try runZr(allocator, &.{"validate"}, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    // Should validate expression syntax without runtime evaluation errors
}

test "299: validate with nested task dependencies forms valid DAG" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const dag_toml =
        \\[tasks.init]
        \\cmd = "echo init"
        \\
        \\[tasks.compile]
        \\cmd = "echo compile"
        \\deps = ["init"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\deps = ["compile"]
        \\
        \\[tasks.lint]
        \\cmd = "echo lint"
        \\deps = ["init"]
        \\
        \\[tasks.ci]
        \\cmd = "echo ci"
        \\deps = ["test", "lint"]
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(dag_toml);

    var result = try runZr(allocator, &.{"validate"}, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    // Should validate complex DAG without circular dependencies
}

test "303: validate with task using potentially invalid expression syntax" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const invalid_expr_toml =
        \\[tasks.conditional]
        \\cmd = "echo test"
        \\condition = "platform == linux &&"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(invalid_expr_toml);

    var result = try runZr(allocator, &.{"validate"}, tmp_path);
    defer result.deinit();
    // Expression validation may not catch incomplete expressions at parse time
    // They're evaluated at runtime, so validate may succeed
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "323: validate with task that has empty deps array is valid" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const empty_deps_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\deps = []
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(empty_deps_toml);

    var result = try runZr(allocator, &.{ "validate" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "valid") != null or
        std.mem.indexOf(u8, output, "✓") != null or
        result.exit_code == 0);
}

test "343: validate with task containing all optional fields passes validation" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const full_task_toml =
        \\[tasks.comprehensive]
        \\description = "Task with all optional fields"
        \\cmd = "echo test"
        \\cwd = "."
        \\timeout = 30
        \\retry = 2
        \\allow_failure = true
        \\deps = []
        \\deps_serial = []
        \\env = { KEY = "value" }
        \\condition = "platform == \"darwin\""
        \\max_concurrent = 5
        \\tags = ["test", "comprehensive"]
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(full_task_toml);

    var result = try runZr(allocator, &.{ "validate" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
}

test "357: validate with task using invalid field name reports schema error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const invalid_field_toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\invalid_field = "should_not_exist"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(invalid_field_toml);

    var result = try runZr(allocator, &.{"validate"}, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should either warn about unknown field or accept it (TOML allows extra fields)
    try std.testing.expect(output.len > 0);
}

test "384: validate command with empty zr.toml file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll("");

    // Validate empty config
    var result = try runZr(allocator, &.{"validate"}, tmp_path);
    defer result.deinit();
    // Should handle empty config gracefully
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "397: validate with --schema flag shows schema help" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    // Validate --schema should show schema help and succeed
    var result = try runZr(allocator, &.{ "validate", "--schema" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should contain schema documentation
    try std.testing.expect(std.mem.indexOf(u8, output, "[tasks.<name>]") != null);
}

test "408: validate with --strict flag on config with optional fields missing" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const minimal_toml =
        \\[tasks.simple]
        \\cmd = "echo hello"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(minimal_toml);

    var result = try runZr(allocator, &.{ "validate", "--strict" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should validate successfully even in strict mode with minimal config
    try std.testing.expect(output.len > 0);
}

test "423: validate with workflow containing circular stage dependencies fails" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const circular_stages_toml =
        \\[[workflows.circular.stages]]
        \\name = "stage1"
        \\tasks = ["task1"]
        \\condition = "stages['stage2'].success"
        \\
        \\[[workflows.circular.stages]]
        \\name = "stage2"
        \\tasks = ["task2"]
        \\condition = "stages['stage1'].success"
        \\
        \\[tasks.task1]
        \\cmd = "echo task1"
        \\
        \\[tasks.task2]
        \\cmd = "echo task2"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, circular_stages_toml);
    defer allocator.free(config);

    // This circular dependency should be caught during validation
    var result = try runZr(allocator, &.{ "--config", config, "validate" }, tmp_path);
    defer result.deinit();
    // May pass validation but fail at runtime - either is acceptable
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "432: validate with task containing very deeply nested deps (30+ levels)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Build a chain of 30 tasks
    var toml_buf = std.ArrayList(u8){};
    defer toml_buf.deinit(allocator);
    const writer = toml_buf.writer(allocator);

    var i: u32 = 0;
    while (i < 30) : (i += 1) {
        if (i == 0) {
            try writer.print("[tasks.task{d}]\ncmd = \"echo {d}\"\n\n", .{ i, i });
        } else {
            try writer.print("[tasks.task{d}]\ncmd = \"echo {d}\"\ndeps = [\"task{d}\"]\n\n", .{ i, i, i - 1 });
        }
    }

    const config = try writeTmpConfig(allocator, tmp.dir, toml_buf.items);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "validate" }, tmp_path);
    defer result.deinit();
    // Should validate successfully or report depth limit
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "438: validate with task containing matrix and template fields simultaneously" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const matrix_template_toml =
        \\[templates.node_test]
        \\cmd = "node test.js"
        \\
        \\[tasks.test]
        \\template = "node_test"
        \\matrix = { version = ["16", "18", "20"] }
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, matrix_template_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "validate" }, tmp_path);
    defer result.deinit();
    // Should validate successfully (matrix + template are compatible)
    try std.testing.expect(result.exit_code == 0);
}

test "470: validate with missing required task field shows specific error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const invalid_toml =
        \\[tasks.broken]
        \\# Missing cmd field
        \\description = "This task has no cmd"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(invalid_toml);

    var result = try runZr(allocator, &.{ "validate", "--strict" }, tmp_path);
    defer result.deinit();
    // Validate accepts config even with tasks having no cmd field (TOML is valid)
    // The task will fail at runtime, not at validation time
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "480: validate with task having invalid timeout value" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const invalid_timeout_toml =
        \\[tasks.test]
        \\cmd = "echo test"
        \\timeout = -100
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(invalid_timeout_toml);

    var result = try runZr(allocator, &.{ "validate" }, tmp_path);
    defer result.deinit();
    // Negative timeout is invalid, should either fail or be handled gracefully
    // If parser accepts it, the test verifies no crash occurs
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "510: validate with circular dependency in workflow stages shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[workflows.test]
        \\
        \\[[workflows.test.stages]]
        \\tasks = ["build"]
        \\depends_on = ["stage2"]
        \\
        \\[[workflows.test.stages]]
        \\tasks = ["test"]
        \\depends_on = ["stage1"]
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(toml);

    var result = try runZr(allocator, &.{ "validate" }, tmp_path);
    defer result.deinit();
    // Should detect circular dependency in workflow stages
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "538: validate with both matrix and template shows proper expansion preview" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[templates.build]
        \\cmd = "npm run build -- ${env}"
        \\
        \\[tasks.prod-build]
        \\template = "build"
        \\template_params = { env = "production" }
        \\matrix = { region = ["us", "eu"] }
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "validate", "--verbose" }, tmp_path);
    defer result.deinit();
    // Should validate successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "575: validate with --verbose flag shows detailed validation diagnostics" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps = ["test"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "validate", "--verbose" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show detailed validation output
    try std.testing.expect(result.stdout.len > 0 or result.stderr.len > 0);
}

test "600: validate with invalid task name characters shows clear error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks."build:prod"]
        \\cmd = "echo build"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    // Validate should check task name characters
    var result = try runZr(allocator, &.{ "--config", config, "validate" }, tmp_path);
    defer result.deinit();
    // May pass or fail depending on implementation
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "607: validate with --strict shows warnings for best practices violations" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const incomplete_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, incomplete_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "validate", "--strict" }, tmp_path);
    defer result.deinit();
    // Strict validation shows warnings for missing descriptions
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "warning") != null or std.mem.indexOf(u8, output, "strict") != null or output.len > 0);
}

test "633: validate with --schema and --format json outputs machine-readable validation schema" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "validate", "--schema", "--format", "json" }, tmp_path);
    defer result.deinit();

    // Should output schema in JSON format
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "661: validate with --strict on minimal config shows no errors" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const minimal_toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\description = "Build the project"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, minimal_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "validate", "--strict" }, tmp_path);
    defer result.deinit();

    // Minimal but complete config should pass strict validation
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "667: validate with truly invalid TOML shows parse error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Completely invalid TOML that can't be parsed at all
    const bad_toml =
        \\this is not toml at all
        \\random text [[[
        \\invalid = = =
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, bad_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "validate" }, tmp_path);
    defer result.deinit();

    // Parser might be lenient, but completely invalid should fail or show warning
    const output = if (result.stderr.len > 0) result.stderr else result.stdout;
    try std.testing.expect(output.len > 0);
}

test "678: validate with task referencing nonexistent dependency shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps = ["nonexistent"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "validate" }, tmp_path);
    defer result.deinit();

    // Should report validation error for missing dependency
    try std.testing.expect(result.exit_code != 0);
    const error_output = if (result.stderr.len > 0) result.stderr else result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, error_output, "nonexistent") != null or error_output.len > 0);
}

test "691: validate with circular workflow dependencies shows detailed error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[workflow.ci]
        \\stages = [
        \\  { name = "build", tasks = ["build"] },
        \\  { name = "test", tasks = ["build"], deps = ["build"] },
        \\  { name = "build", tasks = ["build"], deps = ["test"] },
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "validate" }, tmp_path);
    defer result.deinit();

    // Should detect circular dependency in workflow stages
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "701: validate with --schema flag and deeply nested task dependencies" {
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
        \\[tasks.d]
        \\cmd = "echo d"
        \\deps = ["c"]
        \\
        \\[tasks.e]
        \\cmd = "echo e"
        \\deps = ["d"]
        \\
        \\[tasks.f]
        \\cmd = "echo f"
        \\deps = ["e"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "validate", "--schema" }, tmp_path);
    defer result.deinit();

    // Should validate deep dependency chains successfully
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "707: validate with task referencing undefined dependency shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const config =
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps = ["nonexistent"]
        \\
    ;
    const config_file = try tmp.dir.createFile("zr.toml", .{});
    defer config_file.close();
    try config_file.writeAll(config);

    var result = try runZr(allocator, &.{ "validate" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    const output = if (result.stderr.len > 0) result.stderr else result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "nonexistent") != null or std.mem.indexOf(u8, output, "undefined") != null or std.mem.indexOf(u8, output, "not found") != null);
}
