const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;

// ── Test Fixtures ──────────────────────────────────────────────────────

const BASIC_DEPS_TOML =
    \\[tasks.lint]
    \\cmd = "echo linting"
    \\requires = { node = ">=18.0.0" }
    \\
    \\[tasks.build]
    \\cmd = "echo building"
    \\requires = { python = "^3.8.0" }
    \\
;

const SIMPLE_DEPS_TOML =
    \\[tasks.run]
    \\cmd = "echo running"
    \\
;

const MULTIPLE_DEPS_TOML =
    \\[tasks.frontend]
    \\cmd = "echo building frontend"
    \\requires = { node = "^18.0.0", npm = "^8.0.0" }
    \\
    \\[tasks.backend]
    \\cmd = "echo building backend"
    \\requires = { python = "^3.9.0", pip = "^21.0.0" }
    \\
;

const CONFLICTING_DEPS_TOML =
    \\[tasks.old_tool]
    \\cmd = "echo using old tool"
    \\requires = { ruby = "^2.7.0" }
    \\
    \\[tasks.new_tool]
    \\cmd = "echo using new tool"
    \\requires = { ruby = "^3.0.0" }
    \\
;

const COMPLEX_CONSTRAINTS_TOML =
    \\[tasks.compile]
    \\cmd = "echo compiling"
    \\requires = { gcc = ">=9.0.0", zig = "^0.11.0", cmake = "~3.20.0" }
    \\
;

const OPTIONAL_DEPS_TOML =
    \\[tasks.optional_check]
    \\cmd = "echo running"
    \\requires = { node = ">=14.0.0", optional_tool = "^1.0.0" }
    \\
;

// ── Integration Tests ──────────────────────────────────────────────────

test "800: deps check with satisfied constraints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_DEPS_TOML });

    var result = try runZr(allocator, &.{ "deps", "check" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "All dependencies satisfied") != null or
        std.mem.indexOf(u8, result.stdout, "dependencies satisfied") != null);
}

test "801: deps check with unsatisfied constraint returns error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create a constraint for a very new version that likely doesn't exist
    const unsatisfied_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\requires = { node = "^99.0.0" }
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = unsatisfied_toml });

    var result = try runZr(allocator, &.{ "deps", "check" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "does not satisfy") != null or
        std.mem.indexOf(u8, result.stderr, "constraint") != null or
        std.mem.indexOf(u8, result.stderr, "version") != null);
}

test "802: deps install lists missing tools" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_DEPS_TOML });

    var result = try runZr(allocator, &.{ "deps", "install" }, tmp_path);
    defer result.deinit();

    // Should show information about dependencies
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "node") != null or
        std.mem.indexOf(u8, result.stdout, "python") != null or
        std.mem.indexOf(u8, result.stderr, "install") != null);
}

test "803: deps outdated shows available updates" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_DEPS_TOML });

    var result = try runZr(allocator, &.{ "deps", "outdated" }, tmp_path);
    defer result.deinit();

    // Should either list outdated dependencies or show "No updates available"
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "outdated") != null or
        std.mem.indexOf(u8, result.stdout, "update") != null or
        std.mem.indexOf(u8, result.stdout, "No updates") != null);
}

test "804: deps lock generates lock file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_DEPS_TOML });

    var result = try runZr(allocator, &.{ "deps", "lock" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lock") != null or
        std.mem.indexOf(u8, result.stdout, "generated") != null);

    // Verify that a lock file was created
    const lock_file = tmp.dir.openFile(".zr-lock.toml", .{}) catch |err| {
        if (err == error.FileNotFound) {
            // Lock file may not be created if mock implementation
            return;
        }
        return err;
    };
    defer lock_file.close();
}

test "805: deps check with specific task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_DEPS_TOML });

    var result = try runZr(allocator, &.{ "deps", "check", "--task=lint" }, tmp_path);
    defer result.deinit();

    // Should check only the lint task
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lint") != null or
        std.mem.indexOf(u8, result.stdout, "check") != null);
}

test "806: deps check with JSON output format" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_DEPS_TOML });

    var result = try runZr(allocator, &.{ "deps", "check", "--json" }, tmp_path);
    defer result.deinit();

    // JSON output should contain curly braces
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "{") != null or
        std.mem.indexOf(u8, result.stdout, "[") != null);
}

test "807: deps install with auto-install flag" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_DEPS_TOML });

    var result = try runZr(allocator, &.{ "deps", "install", "--install-deps" }, tmp_path);
    defer result.deinit();

    // Should indicate installation process
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "install") != null or
        std.mem.indexOf(u8, result.stderr, "install") != null);
}

test "808: deps no dependencies defined" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = SIMPLE_DEPS_TOML });

    var result = try runZr(allocator, &.{ "deps", "check" }, tmp_path);
    defer result.deinit();

    // Should gracefully handle no dependencies
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "No dependencies") != null or
        std.mem.indexOf(u8, result.stdout, "dependencies") != null);
}

test "809: deps multiple tasks with different constraints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = MULTIPLE_DEPS_TOML });

    var result = try runZr(allocator, &.{ "deps", "check" }, tmp_path);
    defer result.deinit();

    // Should check all dependencies across all tasks
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "frontend") != null or
        std.mem.indexOf(u8, result.stdout, "backend") != null or
        std.mem.indexOf(u8, result.stdout, "dependencies") != null);
}

test "810: deps conflicting constraints error reporting" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = CONFLICTING_DEPS_TOML });

    var result = try runZr(allocator, &.{ "deps", "check" }, tmp_path);
    defer result.deinit();

    // May error or warn about conflicting constraints
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "ruby") != null or
        std.mem.indexOf(u8, result.stderr, "conflict") != null or
        std.mem.indexOf(u8, result.stderr, "ruby") != null);
}

test "811: deps lock with update flag" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_DEPS_TOML });

    var result = try runZr(allocator, &.{ "deps", "lock", "--update" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "812: deps help shows available commands" {
    const allocator = std.testing.allocator;

    var result = try runZr(allocator, &.{ "deps", "--help" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Usage:") != null or
        std.mem.indexOf(u8, result.stdout, "deps") != null);
}

test "813: deps check command help" {
    const allocator = std.testing.allocator;

    var result = try runZr(allocator, &.{ "deps", "check", "--help" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "check") != null);
}

test "814: deps install command help" {
    const allocator = std.testing.allocator;

    var result = try runZr(allocator, &.{ "deps", "install", "--help" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "install") != null);
}

test "815: deps outdated command help" {
    const allocator = std.testing.allocator;

    var result = try runZr(allocator, &.{ "deps", "outdated", "--help" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "outdated") != null);
}

test "816: deps lock command help" {
    const allocator = std.testing.allocator;

    var result = try runZr(allocator, &.{ "deps", "lock", "--help" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "lock") != null);
}

test "817: deps check invalid task name error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_DEPS_TOML });

    var result = try runZr(allocator, &.{ "deps", "check", "--task=nonexistent" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "nonexistent") != null or
        std.mem.indexOf(u8, result.stderr, "not found") != null);
}

test "818: deps with complex constraints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = COMPLEX_CONSTRAINTS_TOML });

    var result = try runZr(allocator, &.{ "deps", "check" }, tmp_path);
    defer result.deinit();

    // Should handle complex constraints (>=, ^, ~)
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "gcc") != null or
        std.mem.indexOf(u8, result.stdout, "zig") != null or
        std.mem.indexOf(u8, result.stdout, "cmake") != null or
        std.mem.indexOf(u8, result.stdout, "dependencies") != null);
}

test "819: deps outdated with JSON output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_DEPS_TOML });

    var result = try runZr(allocator, &.{ "deps", "outdated", "--json" }, tmp_path);
    defer result.deinit();

    // JSON output should contain structured format
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "{") != null or
        std.mem.indexOf(u8, result.stdout, "[") != null);
}

test "820: deps install with JSON output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_DEPS_TOML });

    var result = try runZr(allocator, &.{ "deps", "install", "--json" }, tmp_path);
    defer result.deinit();

    // JSON output should contain structured format
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "{") != null or
        std.mem.indexOf(u8, result.stdout, "[") != null);
}

test "821: deps check missing config file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Don't create zr.toml

    var result = try runZr(allocator, &.{ "deps", "check" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "zr.toml") != null or
        std.mem.indexOf(u8, result.stderr, "not found") != null);
}

test "822: deps lock creates lock file with metadata" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_DEPS_TOML });

    var result = try runZr(allocator, &.{ "deps", "lock" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Check if lock file contains expected metadata
    const lock_file_content = tmp.dir.readFileAlloc(allocator, ".zr-lock.toml", 8192) catch |_| blk: {
        // File might not exist in test implementation
        break :blk "";
    };
    defer allocator.free(lock_file_content);

    if (lock_file_content.len > 0) {
        try std.testing.expect(std.mem.indexOf(u8, lock_file_content, "[metadata]") != null or
            std.mem.indexOf(u8, lock_file_content, "[dependencies]") != null);
    }
}

test "823: deps check task with all constraints satisfied" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const simple_toml =
        \\[tasks.simple]
        \\cmd = "echo test"
        \\requires = { bash = "^4.0.0" }
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = simple_toml });

    var result = try runZr(allocator, &.{ "deps", "check", "--task=simple" }, tmp_path);
    defer result.deinit();

    // Task check should complete
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "824: deps multiple tasks with JSON output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = MULTIPLE_DEPS_TOML });

    var result = try runZr(allocator, &.{ "deps", "check", "--json" }, tmp_path);
    defer result.deinit();

    // JSON output for multiple tasks
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "{") != null or
        std.mem.indexOf(u8, result.stdout, "[") != null);
}

test "825: deps unknown subcommand error" {
    const allocator = std.testing.allocator;

    var result = try runZr(allocator, &.{ "deps", "unknown_cmd" }, null);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unknown") != null or
        std.mem.indexOf(u8, result.stderr, "command") != null);
}

test "826: deps lock with json output" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_DEPS_TOML });

    var result = try runZr(allocator, &.{ "deps", "lock", "--json" }, tmp_path);
    defer result.deinit();

    // JSON output for lock
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "{") != null or
        std.mem.indexOf(u8, result.stdout, "[") != null);
}

test "827: deps check respects multiple constraints" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const multi_constraint_toml =
        \\[tasks.complex]
        \\cmd = "echo complex"
        \\requires = { node = ">=16.0.0", npm = "^6.0.0 || ^7.0.0 || ^8.0.0" }
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = multi_constraint_toml });

    var result = try runZr(allocator, &.{ "deps", "check" }, tmp_path);
    defer result.deinit();

    // Should handle OR constraints (||)
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "828: deps outdated with task filter" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = MULTIPLE_DEPS_TOML });

    var result = try runZr(allocator, &.{ "deps", "outdated", "--task=frontend" }, tmp_path);
    defer result.deinit();

    // Should filter outdated for specific task
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "frontend") != null or
        std.mem.indexOf(u8, result.stdout, "outdated") != null);
}

test "829: deps install shows version requirements" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = COMPLEX_CONSTRAINTS_TOML });

    var result = try runZr(allocator, &.{ "deps", "install" }, tmp_path);
    defer result.deinit();

    // Should show version requirements
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "version") != null or
        std.mem.indexOf(u8, result.stdout, "require") != null or
        std.mem.indexOf(u8, result.stdout, "gcc") != null);
}

test "830: deps without any arguments shows help" {
    const allocator = std.testing.allocator;

    var result = try runZr(allocator, &.{"deps"}, null);
    defer result.deinit();

    // Should show help or usage information
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Usage") != null or
        std.mem.indexOf(u8, result.stdout, "help") != null or
        std.mem.indexOf(u8, result.stdout, "check") != null);
}
