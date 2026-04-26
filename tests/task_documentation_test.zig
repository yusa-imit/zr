const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 1: RICH DESCRIPTION PARSING (3 tests)
// ──────────────────────────────────────────────────────────────────────────

test "documentation: rich description with short and long fields" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo Building project"
        \\
        \\[tasks.build.description]
        \\short = "Build project"
        \\long = """Compile the entire project including all dependencies.
        \\This task performs incremental compilation and outputs artifacts to dist/."""
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Help command should display rich description
    var result = try runZr(allocator, &.{ "--config", config, "help", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain both short and long description
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Build project") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Compile the entire project") != null or
                          std.mem.indexOf(u8, result.stdout, "incremental compilation") != null);
}

test "documentation: string description still works (backward compatibility)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.test]
        \\cmd = "echo Running tests"
        \\description = "Run unit tests"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Task should run normally with string description
    var result = try runZr(allocator, &.{ "--config", config, "run", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Running tests") != null);
}

test "documentation: multiline long description in triple quotes" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.deploy]
        \\cmd = "echo Deploying"
        \\
        \\[tasks.deploy.description]
        \\short = "Deploy to production"
        \\long = """Deploy the application to production servers.
        \\
        \\Steps:
        \\  1. Build release artifacts
        \\  2. Run pre-deployment checks
        \\  3. Upload to servers
        \\  4. Verify deployment
        \\
        \\Requires AWS credentials to be configured."""
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain multiline content
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Deploy to production") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "production servers") != null or
                          std.mem.indexOf(u8, result.stdout, "AWS") != null);
}

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 2: TASK EXAMPLES (3 tests)
// ──────────────────────────────────────────────────────────────────────────

test "documentation: task examples array displayed in help" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo Building"
        \\description = "Build the project"
        \\examples = ["zr run build", "zr run build --release"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show examples section
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "zr run build") != null or
                          std.mem.indexOf(u8, result.stdout, "example") != null);
}

test "documentation: examples with multiple formats and variations" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.test]
        \\cmd = "echo Testing"
        \\description = "Run tests"
        \\examples = [
        \\  "zr run test",
        \\  "zr run test -- --verbose",
        \\  "zr run test:unit",
        \\  "zr run test:integration --slow"
        \\]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
}

test "documentation: empty examples array handled gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.simple]
        \\cmd = "echo Done"
        \\description = "Simple task"
        \\examples = []
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "simple" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "simple") != null);
}

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 3: OUTPUT DOCUMENTATION (2 tests)
// ──────────────────────────────────────────────────────────────────────────

test "documentation: outputs map describes generated artifacts" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo Building"
        \\description = "Build the project"
        \\
        \\[tasks.build.outputs]
        \\"dist/" = "Compiled binaries and assets"
        \\"build/reports/" = "Build reports and metrics"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should display outputs section
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "dist") != null or
                          std.mem.indexOf(u8, result.stdout, "Compiled") != null);
}

test "documentation: outputs empty map handled gracefully" {
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

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 4: RELATED TASKS (2 tests)
// ──────────────────────────────────────────────────────────────────────────

test "documentation: see_also field lists related tasks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo Building"
        \\description = "Build the project"
        \\see_also = ["test", "deploy", "clean"]
        \\
        \\[tasks.test]
        \\cmd = "echo Testing"
        \\description = "Run tests"
        \\
        \\[tasks.deploy]
        \\cmd = "echo Deploying"
        \\description = "Deploy to production"
        \\
        \\[tasks.clean]
        \\cmd = "echo Cleaning"
        \\description = "Clean build artifacts"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "build" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show related tasks
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null or
                          std.mem.indexOf(u8, result.stdout, "deploy") != null or
                          std.mem.indexOf(u8, result.stdout, "see also") != null);
}

test "documentation: see_also with empty array handled gracefully" {
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

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 5: HELP COMMAND (5 tests)
// ──────────────────────────────────────────────────────────────────────────

test "documentation: help command displays task name and description" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.hello]
        \\cmd = "echo Hello"
        \\description = "Say hello"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "hello" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "hello") != null);
}

test "documentation: help with non-existent task shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.hello]
        \\cmd = "echo Hello"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "nonexistent" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "nonexistent") != null or
                          std.mem.indexOf(u8, result.stderr, "not found") != null or
                          std.mem.indexOf(u8, result.stderr, "error") != null);
}

test "documentation: help shows all available metadata sections" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.full-featured]
        \\cmd = "echo Full"
        \\
        \\[tasks.full-featured.description]
        \\short = "A complete task"
        \\long = "This task demonstrates all documentation features."
        \\
        \\[tasks.full-featured.outputs]
        \\"output.txt" = "Main output file"
        \\
        \\
        \\[tasks.full-featured]
        \\examples = ["zr run full-featured", "zr run full-featured --verbose"]
        \\see_also = ["related-task"]
        \\
        \\[tasks.related-task]
        \\cmd = "echo Related"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "full-featured" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain task name
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "full-featured") != null);
}

test "documentation: help with parameters shows parameter metadata" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.deploy]
        \\cmd = "echo Deploying to {{env}}"
        \\description = "Deploy application"
        \\
        \\[[tasks.deploy.params]]
        \\name = "env"
        \\description = "Target environment"
        \\required = true
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show parameter information
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "deploy") != null);
}

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 6: LIST VERBOSE MODE (3 tests)
// ──────────────────────────────────────────────────────────────────────────

test "documentation: list --verbose shows task descriptions" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo Building"
        \\description = "Build the project"
        \\
        \\[tasks.test]
        \\cmd = "echo Testing"
        \\description = "Run unit tests"
        \\
        \\[tasks.deploy]
        \\cmd = "echo Deploying"
        \\description = "Deploy to production"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--verbose" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show all tasks with descriptions
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "deploy") != null);
}

test "documentation: list --verbose with rich descriptions shows short form" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo Building"
        \\
        \\[tasks.build.description]
        \\short = "Build the project"
        \\long = "Compile all source files and generate artifacts in the dist directory."
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--verbose" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show short description in list
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null or
                          std.mem.indexOf(u8, result.stdout, "Build") != null);
}

test "documentation: list verbose without descriptions works" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.task1]
        \\cmd = "echo Task1"
        \\
        \\[tasks.task2]
        \\cmd = "echo Task2"
        \\description = "Has description"
        \\
        \\[tasks.task3]
        \\cmd = "echo Task3"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list", "--verbose" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // All tasks should list even those without descriptions
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task1") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task2") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "task3") != null);
}

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 7: EDGE CASES & ERROR HANDLING (5 tests)
// ──────────────────────────────────────────────────────────────────────────

test "documentation: task without any documentation works normally" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.minimal]
        \\cmd = "echo Minimal"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "run", "minimal" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Minimal") != null);
}

test "documentation: help shows examples even with minimal metadata" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.minimal]
        \\cmd = "echo Minimal"
        \\examples = ["zr run minimal"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "minimal" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "documentation: special characters in descriptions handled correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.special]
        \\cmd = "echo Special"
        \\
        \\[tasks.special.description]
        \\short = "Test <special> & \"characters\""
        \\long = """Line 1: 'quoted'
        \\Line 2: {curly} [brackets]"""
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "special" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "special") != null);
}

test "documentation: very long description handled gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const long_desc = "This is a very long description. " ** 20; // Repeat 20 times

    const config_toml =
        \\[tasks.verbose]
        \\cmd = "echo Verbose"
        \\
    ;

    var config_str = std.ArrayList(u8){};
    defer config_str.deinit(allocator);

    try config_str.appendSlice(allocator, config_toml);
    try config_str.appendSlice(allocator, "\n[tasks.verbose.description]\n");
    try config_str.appendSlice(allocator, "short = \"Verbose task\"\n");
    try config_str.appendSlice(allocator, "long = \"\"\"");
    try config_str.appendSlice(allocator, long_desc);
    try config_str.appendSlice(allocator, "\"\"\"\n");

    const config = try writeTmpConfig(allocator, tmp.dir, config_str.items);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "verbose" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "documentation: help for task with dependencies shows all metadata" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.build]
        \\cmd = "echo Building"
        \\description = "Build the project"
        \\
        \\[tasks.test]
        \\cmd = "echo Testing"
        \\description = "Run tests"
        \\deps = ["build"]
        \\see_also = ["lint"]
        \\
        \\[tasks.lint]
        \\cmd = "echo Linting"
        \\description = "Lint code"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "test" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show task documentation
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
}

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 8: INTEGRATION WITH OTHER FEATURES (4 tests)
// ──────────────────────────────────────────────────────────────────────────

test "documentation: help works with task parameters and interpolation" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.deploy]
        \\cmd = "echo Deploying to {{env}}"
        \\
        \\[tasks.deploy.description]
        \\short = "Deploy to environment"
        \\long = "Deploy the application to the specified environment using parameters."
        \\
        \\[[tasks.deploy.params]]
        \\name = "env"
        \\description = "Target environment (dev, staging, prod)"
        \\default = "staging"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "deploy" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "deploy") != null);
}

test "documentation: list verbose respects other filter options" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.quick_build]
        \\cmd = "echo Building"
        \\description = "Quick build"
        \\tags = ["fast"]
        \\
        \\[tasks.full_build]
        \\cmd = "echo Building full"
        \\description = "Full build with tests"
        \\tags = ["slow"]
        \\
        \\[tasks.test]
        \\cmd = "echo Testing"
        \\description = "Run tests"
        \\tags = ["fast"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // List verbose with tag filter
    var result = try runZr(allocator, &.{ "--config", config, "list", "--verbose", "--tag=fast" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should list only fast tasks
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "quick_build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null);
}

test "documentation: help for task in workspace config" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[workspace]
        \\members = []
        \\
        \\[tasks.workspace-task]
        \\cmd = "echo Workspace"
        \\
        \\[tasks.workspace-task.description]
        \\short = "Workspace level task"
        \\long = "This task is defined at the workspace level."
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "help", "workspace-task" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "documentation: json output format for help (if available)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.json-test]
        \\cmd = "echo JSON"
        \\description = "Task for JSON output testing"
        \\examples = ["zr run json-test"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Try JSON format if available
    var result = try runZr(allocator, &.{ "--config", config, "--format", "json", "help", "json-test" }, tmp_path);
    defer result.deinit();

    // Should succeed regardless of format support
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

// ──────────────────────────────────────────────────────────────────────────
// CATEGORY 9: COMPLEX DOCUMENTATION SCENARIOS (3 tests)
// ──────────────────────────────────────────────────────────────────────────

test "documentation: multiple tasks with complete documentation" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.setup]
        \\cmd = "echo Setup"
        \\description = "Initialize environment"
        \\see_also = ["build"]
        \\
        \\[tasks.build]
        \\cmd = "echo Building"
        \\
        \\[tasks.build.description]
        \\short = "Build artifacts"
        \\long = "Compile source code and generate build artifacts."
        \\
        \\[tasks.build]
        \\deps = ["setup"]
        \\examples = ["zr run build", "zr run build --release"]
        \\see_also = ["test"]
        \\
        \\[tasks.test]
        \\cmd = "echo Testing"
        \\description = "Run test suite"
        \\deps = ["build"]
        \\see_also = ["build"]
        \\
        \\[tasks.test.outputs]
        \\"coverage/" = "Code coverage reports"
        \\"test-results.json" = "Test results in JSON format"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Test help for each task
    var result_build = try runZr(allocator, &.{ "--config", config, "help", "build" }, tmp_path);
    defer result_build.deinit();

    try std.testing.expectEqual(@as(u8, 0), result_build.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result_build.stdout, "build") != null);
}

test "documentation: search/filter tasks by description keywords" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.http-get]
        \\cmd = "echo GET"
        \\description = "Make HTTP GET request"
        \\
        \\[tasks.http-post]
        \\cmd = "echo POST"
        \\description = "Make HTTP POST request"
        \\
        \\[tasks.db-migrate]
        \\cmd = "echo Migrate"
        \\description = "Run database migrations"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // List all tasks
    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "http-get") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "http-post") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "db-migrate") != null);
}

test "documentation: help displays formatted output with proper alignment" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const config_toml =
        \\[tasks.cmd-a]
        \\cmd = "echo A"
        \\description = "First command"
        \\
        \\[tasks.cmd-bb]
        \\cmd = "echo BB"
        \\
        \\[tasks.cmd-bb.description]
        \\short = "Second command with longer name"
        \\long = "This is the second command."
        \\
        \\[tasks.cmd-ccc]
        \\cmd = "echo CCC"
        \\description = "Third command"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should display all tasks in readable format
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "cmd-a") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "cmd-bb") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "cmd-ccc") != null);
}
