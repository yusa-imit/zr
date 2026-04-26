const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ══════════════════════════════════════════════════════════════════════════
// TASK DOCUMENTATION PARSER TESTS — Phase 2 (Parser Support)
// ══════════════════════════════════════════════════════════════════════════
//
// Tests verify TOML parser correctly populates new schema fields:
// - TaskDescription union (string | rich{short, long})
// - examples: ?[][]const u8
// - outputs: ?StringHashMap([]const u8)
// - see_also: ?[][]const u8
//
// All tests use `help` command to verify parsed data is accessible at runtime.
// ══════════════════════════════════════════════════════════════════════════

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 1: RICH DESCRIPTION PARSING (6 tests)
// ──────────────────────────────────────────────────────────────────────────

test "parser: rich description with short and long fields" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.deploy]
        \\cmd = "echo Deploying"
        \\
        \\[tasks.deploy.description]
        \\short = "Deploy to server"
        \\long = "Deploy application to production server with health checks and rollback support."
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "deploy" }, tmp_path);
    defer result.deinit();

    // Must succeed - parser must handle rich description table
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Verify both short and long are parsed and displayed
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Deploy to server") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "production server") != null or
        std.mem.indexOf(u8, result.stdout, "health checks") != null);
}

test "parser: rich description with only short field (long optional)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo Building"
        \\
        \\[tasks.build.description]
        \\short = "Build the project"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "build" }, tmp_path);
    defer result.deinit();

    // Parser must handle rich description with missing long field
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Build the project") != null);
}

test "parser: simple string description (backward compatibility)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.test]
        \\cmd = "echo Testing"
        \\description = "Run all unit tests"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "test" }, tmp_path);
    defer result.deinit();

    // Old format must still work - parser wraps in TaskDescription.string
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Run all unit tests") != null);
}

test "parser: rich description with multiline long field in triple quotes" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.migrate]
        \\cmd = "echo Migrating"
        \\
        \\[tasks.migrate.description]
        \\short = "Run database migrations"
        \\long = """Execute all pending database migrations.
        \\
        \\Prerequisites:
        \\  - Database connection configured in .env
        \\  - Migration files in migrations/ directory
        \\  - Backup created (recommended)
        \\
        \\This task is idempotent and safe to re-run."""
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "migrate" }, tmp_path);
    defer result.deinit();

    // Parser must handle multiline strings correctly
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Run database migrations") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Prerequisites") != null or
        std.mem.indexOf(u8, result.stdout, "Database connection") != null);
}

test "parser: empty strings in rich description fields handled gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.empty]
        \\cmd = "echo Empty"
        \\
        \\[tasks.empty.description]
        \\short = ""
        \\long = ""
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "empty" }, tmp_path);
    defer result.deinit();

    // Should not crash with empty description fields
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "parser: special characters in description fields" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.special]
        \\cmd = "echo Special"
        \\
        \\[tasks.special.description]
        \\short = "Test <brackets> & \"quotes\""
        \\long = """Complex description with:
        \\  - Unicode: 日本語 🚀
        \\  - Symbols: $VAR, @mention, #tag
        \\  - Escapes: \n \t \\backslash"""
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "special" }, tmp_path);
    defer result.deinit();

    // Parser must correctly handle TOML escaping
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 2: EXAMPLES PARSING (5 tests)
// ──────────────────────────────────────────────────────────────────────────

test "parser: examples array with multiple entries" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.test]
        \\cmd = "echo Testing"
        \\description = "Run tests"
        \\examples = [
        \\  "zr run test",
        \\  "zr run test --verbose",
        \\  "zr run test -- --watch"
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "test" }, tmp_path);
    defer result.deinit();

    // Parser must populate examples array correctly
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Verify at least one example is displayed
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "zr run test") != null or
        std.mem.indexOf(u8, result.stdout, "example") != null);
}

test "parser: examples with single-line array syntax" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo Building"
        \\description = "Build project"
        \\examples = ["zr run build", "zr run build --release"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "build" }, tmp_path);
    defer result.deinit();

    // Compact array syntax must parse correctly
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
}

test "parser: empty examples array handled gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.minimal]
        \\cmd = "echo Minimal"
        \\description = "Minimal task"
        \\examples = []
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "minimal" }, tmp_path);
    defer result.deinit();

    // Empty array should not cause parser error
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "parser: examples with special characters and escapes" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.complex]
        \\cmd = "echo Complex"
        \\description = "Complex examples"
        \\examples = [
        \\  "zr run complex --env=\"production\"",
        \\  "zr run complex -- --flag=value",
        \\  "zr run complex --tags='tag1,tag2'"
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "complex" }, tmp_path);
    defer result.deinit();

    // Parser must handle quoted strings in array elements
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "parser: examples without description field still works" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.partial]
        \\cmd = "echo Partial"
        \\examples = ["zr run partial"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "partial" }, tmp_path);
    defer result.deinit();

    // Task with only examples (no description) must parse
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 3: OUTPUTS PARSING (5 tests)
// ──────────────────────────────────────────────────────────────────────────

test "parser: outputs table with multiple entries" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo Building"
        \\description = "Build project"
        \\
        \\[tasks.build.outputs]
        \\"dist/" = "Compiled binaries"
        \\"build/reports/" = "Build reports and metrics"
        \\"coverage.html" = "Code coverage report"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "build" }, tmp_path);
    defer result.deinit();

    // Parser must populate outputs StringHashMap
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Verify at least one output path is shown
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "dist") != null or
        std.mem.indexOf(u8, result.stdout, "Compiled") != null or
        std.mem.indexOf(u8, result.stdout, "output") != null);
}

test "parser: outputs table empty (no outputs section)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.lint]
        \\cmd = "echo Linting"
        \\description = "Lint code"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "lint" }, tmp_path);
    defer result.deinit();

    // Task without outputs section must parse successfully
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "parser: outputs with file paths containing special characters" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.special-paths]
        \\cmd = "echo Special"
        \\description = "Special output paths"
        \\
        \\[tasks.special-paths.outputs]
        \\"output/my-file.txt" = "Hyphenated filename"
        \\"dist/v1.0.0/" = "Versioned directory"
        \\"logs/app_2024.log" = "Timestamped log"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "special-paths" }, tmp_path);
    defer result.deinit();

    // Parser must handle various path formats
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "parser: outputs with long descriptions" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.verbose-outputs]
        \\cmd = "echo Verbose"
        \\description = "Verbose output docs"
        \\
        \\[tasks.verbose-outputs.outputs]
        \\"build/artifacts/" = "Contains all build artifacts including binaries, libraries, and metadata files"
        \\"logs/" = "Execution logs with timestamps and detailed error traces"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "verbose-outputs" }, tmp_path);
    defer result.deinit();

    // Long output descriptions must not break parser
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "parser: outputs with empty description values" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.empty-desc]
        \\cmd = "echo Empty"
        \\description = "Empty output descriptions"
        \\
        \\[tasks.empty-desc.outputs]
        \\"output.txt" = ""
        \\"result/" = ""
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "empty-desc" }, tmp_path);
    defer result.deinit();

    // Empty descriptions should not cause errors
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 4: SEE_ALSO PARSING (5 tests)
// ──────────────────────────────────────────────────────────────────────────

test "parser: see_also array with multiple task references" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo Building"
        \\description = "Build project"
        \\see_also = ["test", "lint", "deploy"]
        \\
        \\[tasks.test]
        \\cmd = "echo Testing"
        \\
        \\[tasks.lint]
        \\cmd = "echo Linting"
        \\
        \\[tasks.deploy]
        \\cmd = "echo Deploying"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "build" }, tmp_path);
    defer result.deinit();

    // Parser must populate see_also array
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Verify related tasks section appears
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null or
        std.mem.indexOf(u8, result.stdout, "lint") != null or
        std.mem.indexOf(u8, result.stdout, "see also") != null or
        std.mem.indexOf(u8, result.stdout, "related") != null);
}

test "parser: see_also with empty array" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.standalone]
        \\cmd = "echo Standalone"
        \\description = "Standalone task"
        \\see_also = []
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "standalone" }, tmp_path);
    defer result.deinit();

    // Empty see_also array should not cause errors
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "parser: see_also referencing non-existent tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.main]
        \\cmd = "echo Main"
        \\description = "Main task"
        \\see_also = ["nonexistent", "also-missing"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "main" }, tmp_path);
    defer result.deinit();

    // Parser should not validate task existence (runtime concern)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "parser: see_also with single-line array syntax" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.quick]
        \\cmd = "echo Quick"
        \\description = "Quick task"
        \\see_also = ["build", "test"]
        \\
        \\[tasks.build]
        \\cmd = "echo Build"
        \\
        \\[tasks.test]
        \\cmd = "echo Test"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "quick" }, tmp_path);
    defer result.deinit();

    // Compact array syntax must work
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "parser: see_also with namespace task names" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks."test:unit"]
        \\cmd = "echo Unit tests"
        \\description = "Run unit tests"
        \\see_also = ["test:integration", "test:e2e"]
        \\
        \\[tasks."test:integration"]
        \\cmd = "echo Integration"
        \\
        \\[tasks."test:e2e"]
        \\cmd = "echo E2E"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "test:unit" }, tmp_path);
    defer result.deinit();

    // Parser must handle task names with colons
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 5: COMBINED PARSING (4 tests)
// ──────────────────────────────────────────────────────────────────────────

test "parser: task with all documentation fields combined" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.comprehensive]
        \\cmd = "echo Comprehensive"
        \\
        \\[tasks.comprehensive.description]
        \\short = "Full-featured task"
        \\long = "This task demonstrates all documentation features working together."
        \\
        \\[tasks.comprehensive]
        \\examples = [
        \\  "zr run comprehensive",
        \\  "zr run comprehensive --verbose"
        \\]
        \\see_also = ["simple", "basic"]
        \\
        \\[tasks.comprehensive.outputs]
        \\"output/" = "Main output directory"
        \\"logs/" = "Execution logs"
        \\
        \\[tasks.simple]
        \\cmd = "echo Simple"
        \\
        \\[tasks.basic]
        \\cmd = "echo Basic"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "comprehensive" }, tmp_path);
    defer result.deinit();

    // All fields must parse together without conflicts
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "comprehensive") != null);
}

test "parser: mix of old and new description formats in same config" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.old-style]
        \\cmd = "echo Old"
        \\description = "Old string format"
        \\
        \\[tasks.new-style]
        \\cmd = "echo New"
        \\
        \\[tasks.new-style.description]
        \\short = "New rich format"
        \\long = "Detailed description"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Test both tasks parse correctly
    var result_old = try runZr(allocator, &.{ "--config", config, "help", "old-style" }, tmp_path);
    defer result_old.deinit();

    try std.testing.expectEqual(@as(u8, 0), result_old.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result_old.stdout, "Old string format") != null);

    var result_new = try runZr(allocator, &.{ "--config", config, "help", "new-style" }, tmp_path);
    defer result_new.deinit();

    try std.testing.expectEqual(@as(u8, 0), result_new.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result_new.stdout, "New rich format") != null);
}

test "parser: partial documentation fields (not all fields present)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.partial-a]
        \\cmd = "echo A"
        \\description = "Has description and examples only"
        \\examples = ["zr run partial-a"]
        \\
        \\[tasks.partial-b]
        \\cmd = "echo B"
        \\see_also = ["partial-a"]
        \\
        \\[tasks.partial-b.outputs]
        \\"result.txt" = "Result file"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Both tasks with partial fields should parse
    var result_a = try runZr(allocator, &.{ "--config", config, "help", "partial-a" }, tmp_path);
    defer result_a.deinit();
    try std.testing.expectEqual(@as(u8, 0), result_a.exit_code);

    var result_b = try runZr(allocator, &.{ "--config", config, "help", "partial-b" }, tmp_path);
    defer result_b.deinit();
    try std.testing.expectEqual(@as(u8, 0), result_b.exit_code);
}

test "parser: documentation fields in complex task with params and deps" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.prereq]
        \\cmd = "echo Prereq"
        \\
        \\[tasks.complex]
        \\cmd = "echo {{env}}"
        \\deps = ["prereq"]
        \\
        \\[tasks.complex.description]
        \\short = "Complex task with everything"
        \\long = "This task has params, deps, and full documentation."
        \\
        \\[[tasks.complex.params]]
        \\name = "env"
        \\description = "Environment name"
        \\default = "dev"
        \\
        \\[tasks.complex]
        \\examples = ["zr run complex", "zr run complex env=prod"]
        \\see_also = ["prereq"]
        \\
        \\[tasks.complex.outputs]
        \\"deploy.log" = "Deployment log"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "complex" }, tmp_path);
    defer result.deinit();

    // Documentation fields must coexist with other task features
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "complex") != null);
}

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 6: ERROR CASES & MALFORMED TOML (5 tests)
// ──────────────────────────────────────────────────────────────────────────

test "parser: malformed rich description table missing short field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.bad]
        \\cmd = "echo Bad"
        \\
        \\[tasks.bad.description]
        \\long = "Missing short field"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "bad" }, tmp_path);
    defer result.deinit();

    // Parser should error or handle gracefully - short is required
    // Accept either error exit or graceful handling
    try std.testing.expect(result.exit_code == 1 or result.exit_code == 0);
}

test "parser: invalid type for examples field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.bad-examples]
        \\cmd = "echo Bad"
        \\description = "Bad examples type"
        \\examples = "not an array"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "bad-examples" }, tmp_path);
    defer result.deinit();

    // Parser must detect type mismatch (expects array)
    // Should fail with exit code 1
    try std.testing.expect(result.exit_code == 1 or std.mem.indexOf(u8, result.stderr, "error") != null);
}

test "parser: invalid type for outputs field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.bad-outputs]
        \\cmd = "echo Bad"
        \\description = "Bad outputs type"
        \\outputs = ["not", "a", "table"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "bad-outputs" }, tmp_path);
    defer result.deinit();

    // Parser must detect type mismatch (expects table)
    try std.testing.expect(result.exit_code == 1 or std.mem.indexOf(u8, result.stderr, "error") != null);
}

test "parser: invalid type for see_also field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.bad-see-also]
        \\cmd = "echo Bad"
        \\description = "Bad see_also type"
        \\see_also = "not an array"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "bad-see-also" }, tmp_path);
    defer result.deinit();

    // Parser must detect type mismatch (expects array)
    try std.testing.expect(result.exit_code == 1 or std.mem.indexOf(u8, result.stderr, "error") != null);
}

test "parser: description as both string and table causes error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.conflict]
        \\cmd = "echo Conflict"
        \\description = "String description"
        \\
        \\[tasks.conflict.description]
        \\short = "Table description"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "conflict" }, tmp_path);
    defer result.deinit();

    // TOML parser should reject conflicting types for same key
    // This is a TOML syntax error, not zr-specific
    try std.testing.expect(result.exit_code == 1 or std.mem.indexOf(u8, result.stderr, "error") != null);
}

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 7: EDGE CASES (4 tests)
// ──────────────────────────────────────────────────────────────────────────

test "parser: very long description stress test" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Generate very long description programmatically
    var long_desc = std.ArrayList(u8){};
    defer long_desc.deinit(allocator);

    try long_desc.appendSlice(allocator, "This is a very long description. ");
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        try long_desc.appendSlice(allocator, "Lorem ipsum dolor sit amet. ");
    }

    var config_str = std.ArrayList(u8){};
    defer config_str.deinit(allocator);

    try config_str.appendSlice(allocator, "[tasks.stress]\n");
    try config_str.appendSlice(allocator, "cmd = \"echo Stress\"\n");
    try config_str.appendSlice(allocator, "\n[tasks.stress.description]\n");
    try config_str.appendSlice(allocator, "short = \"Stress test\"\n");
    try config_str.appendSlice(allocator, "long = \"\"\"");
    try config_str.appendSlice(allocator, long_desc.items);
    try config_str.appendSlice(allocator, "\"\"\"\n");

    const config = try writeTmpConfig(allocator, tmp.dir, config_str.items);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "stress" }, tmp_path);
    defer result.deinit();

    // Parser must handle very long strings
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "parser: task with 100 examples array elements" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var config_str = std.ArrayList(u8){};
    defer config_str.deinit(allocator);

    try config_str.appendSlice(allocator, "[tasks.many-examples]\n");
    try config_str.appendSlice(allocator, "cmd = \"echo Many\"\n");
    try config_str.appendSlice(allocator, "description = \"Many examples\"\n");
    try config_str.appendSlice(allocator, "examples = [\n");

    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        try config_str.writer(allocator).print("  \"zr run many-examples --arg={d}\"", .{i});
        if (i < 99) try config_str.appendSlice(allocator, ",\n")
        else try config_str.appendSlice(allocator, "\n");
    }
    try config_str.appendSlice(allocator, "]\n");

    const config = try writeTmpConfig(allocator, tmp.dir, config_str.items);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "many-examples" }, tmp_path);
    defer result.deinit();

    // Parser must handle large arrays
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "parser: task with 50 output entries" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var config_str = std.ArrayList(u8){};
    defer config_str.deinit(allocator);

    try config_str.appendSlice(allocator, "[tasks.many-outputs]\n");
    try config_str.appendSlice(allocator, "cmd = \"echo Many\"\n");
    try config_str.appendSlice(allocator, "description = \"Many outputs\"\n");
    try config_str.appendSlice(allocator, "\n[tasks.many-outputs.outputs]\n");

    var i: u32 = 0;
    while (i < 50) : (i += 1) {
        try config_str.writer(allocator).print("\"output{d}.txt\" = \"Output file {d}\"\n", .{ i, i });
    }

    const config = try writeTmpConfig(allocator, tmp.dir, config_str.items);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "many-outputs" }, tmp_path);
    defer result.deinit();

    // Parser must handle large hash maps
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "parser: unicode and emoji in all documentation fields" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.unicode]
        \\cmd = "echo Unicode"
        \\
        \\[tasks.unicode.description]
        \\short = "Unicode support 日本語 🚀"
        \\long = "Full description with 中文, العربية, and emoji: ✅ ⚠️ 🔧"
        \\
        \\[tasks.unicode]
        \\examples = ["zr run unicode 🎯", "zr run unicode --lang=日本語"]
        \\see_also = ["другая-задача"]
        \\
        \\[tasks.unicode.outputs]
        \\"файл.txt" = "Файл результата"
        \\"结果/" = "结果目录"
        \\
        \\[tasks."другая-задача"]
        \\cmd = "echo Other"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "unicode" }, tmp_path);
    defer result.deinit();

    // Parser must handle UTF-8 correctly
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}
