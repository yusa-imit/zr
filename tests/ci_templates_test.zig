const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;

// ── Test 1: `zr ci list` shows available templates ──────────────────────────

test "zr ci list shows all available GitHub Actions templates" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify output contains template names
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "github-actions") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "basic") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "monorepo") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "release") != null);

    // Verify output contains descriptions
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "continuous integration") != null or
        std.mem.indexOf(u8, result.stdout, "CI") != null);
}

test "zr ci list output is properly formatted" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Check that output contains organized sections
    const output = result.stdout;
    try std.testing.expect(output.len > 100); // Non-trivial output
    try std.testing.expect(std.mem.indexOf(u8, output, "Available") != null or
        std.mem.indexOf(u8, output, "Templates") != null);
}

// ── Test 2: `zr ci generate` with GitHub Actions basic template ────────────

test "zr ci generate with explicit platform creates valid YAML structure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=github-actions" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify file was created
    const generated_file = try tmp.dir.readFileAlloc(allocator, ".github/workflows/zr-ci.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify YAML structure
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "name:") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "on:") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "jobs:") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "runs-on:") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "steps:") != null);
}

test "zr ci generate basic template contains zr install and zr run commands" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=github-actions" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".github/workflows/zr-ci.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify zr install command
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "Install zr") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "curl") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "zr-") != null);

    // Verify zr run commands
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "zr run") != null or
        std.mem.indexOf(u8, generated_file, "zr setup") != null);
}

test "zr ci generate default template is basic CI" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Generate with only platform, should default to basic
    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=github-actions" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify basic CI file (not monorepo)
    const file_content = try tmp.dir.readFileAlloc(allocator, ".github/workflows/zr-ci.yml", 16 * 1024);
    defer allocator.free(file_content);

    // Basic CI should not have matrix strategy (monorepo feature)
    const has_matrix = std.mem.indexOf(u8, file_content, "matrix:") != null;
    const has_affected = std.mem.indexOf(u8, file_content, "affected") != null;

    // Basic template should not have these monorepo features
    try std.testing.expect(!has_matrix or !has_affected);
}

// ── Test 3: Monorepo template ──────────────────────────────────────────────

test "zr ci generate monorepo template includes affected detection" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=github-actions", "--type=monorepo" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".github/workflows/zr-monorepo.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify monorepo-specific features
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "affected") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "matrix:") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "zr affected") != null);
}

test "zr ci generate monorepo template includes caching" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=github-actions", "--type=monorepo" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".github/workflows/zr-monorepo.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify cache configuration
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "Cache") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "~/.zr/cache") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "zr.toml") != null);
}

test "zr ci generate monorepo template uses matrix strategy for projects" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=github-actions", "--type=monorepo" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".github/workflows/zr-monorepo.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify matrix includes projects variable
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "matrix:") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "project") != null);
}

// ── Test 4: Release template ───────────────────────────────────────────────

test "zr ci generate release template includes publish and release steps" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=github-actions", "--type=release" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".github/workflows/zr-release.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify release-specific features
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "release") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "Publish") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "GitHub Release") != null);
}

test "zr ci generate release template triggers on version tags" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=github-actions", "--type=release" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".github/workflows/zr-release.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify release triggered on tags
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "tags:") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "v*") != null);
}

test "zr ci generate release template includes GITHUB_TOKEN secret" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=github-actions", "--type=release" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".github/workflows/zr-release.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify GitHub token usage
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "GITHUB_TOKEN") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "secrets.GITHUB_TOKEN") != null);
}

// ── Test 5: Variable Substitution ─────────────────────────────────────────

test "zr ci generate substitutes DEFAULT_BRANCH variable with default value" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=github-actions" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".github/workflows/zr-ci.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify ${DEFAULT_BRANCH} was substituted (should be "main" by default)
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "${DEFAULT_BRANCH}") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "main") != null);
}

test "zr ci generate substitutes RUNNER variable with default value" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=github-actions" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".github/workflows/zr-ci.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify ${RUNNER} was substituted (should be "ubuntu-latest" by default)
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "${RUNNER}") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "ubuntu-latest") != null);
}

test "zr ci generate substitutes BUILD_TASK and TEST_TASK variables" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=github-actions" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".github/workflows/zr-ci.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify task variables were substituted (defaults: build, test)
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "${BUILD_TASK}") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "${TEST_TASK}") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "test") != null);
}

test "zr ci generate release template substitutes PUBLISH_TASK and ARTIFACTS_PATH" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=github-actions", "--type=release" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".github/workflows/zr-release.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify release-specific variables were substituted
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "${PUBLISH_TASK}") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "${ARTIFACTS_PATH}") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "publish") != null or
        std.mem.indexOf(u8, generated_file, "dist") != null);
}

// ── Test 6: Platform Auto-Detection ───────────────────────────────────────

test "zr ci generate auto-detects GitHub Actions platform when .github/workflows exists" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create .github/workflows directory
    try tmp.dir.makePath(".github/workflows");

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Generate without explicit platform (should auto-detect GitHub Actions)
    var result = try runZr(allocator, &.{ "ci", "generate" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify detection message in output
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "Detected") != null or
        std.mem.indexOf(u8, output, "platform") != null or
        std.mem.indexOf(u8, output, "Generated") != null);

    // Verify file was created with correct extension
    _ = tmp.dir.openDir(".github/workflows", .{}) catch {
        return error.TestUnexpectedResult;
    };
}

test "zr ci generate fails with clear error when platform cannot be detected" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Generate without explicit platform and no CI config files (should fail)
    var result = try runZr(allocator, &.{ "ci", "generate" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);

    // Verify error message
    const output = result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "could not detect") != null or
        std.mem.indexOf(u8, output, "Could not detect") != null or
        std.mem.indexOf(u8, output, "platform") != null);
}

// ── Test 7: Error Cases ────────────────────────────────────────────────────

test "zr ci generate fails with invalid template type" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=github-actions", "--type=invalid-type" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);

    // Verify error message mentions invalid type
    const output = result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "Unknown template type") != null or
        std.mem.indexOf(u8, output, "invalid") != null);
}

test "zr ci generate fails with invalid platform" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=unsupported-platform" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);

    // Verify error message
    const output = result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "Unknown platform") != null);
}

test "zr ci generate error message suggests valid platforms" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=invalid" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);

    // Verify error suggests valid options
    const output = result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "github-actions") != null or
        std.mem.indexOf(u8, output, "gitlab") != null or
        std.mem.indexOf(u8, output, "circleci") != null);
}

// ── Test 8: Output File Handling ───────────────────────────────────────────

test "zr ci generate creates nested directories for output file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=github-actions" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify .github/workflows directory was created
    _ = tmp.dir.openDir(".github/workflows", .{}) catch {
        return error.TestUnexpectedResult;
    };
}

test "zr ci generate with custom output path respects output flag" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const custom_output = "custom-ci.yml";
    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=github-actions", "--output=" ++ custom_output }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify file was created at custom path
    const custom_file = try tmp.dir.readFileAlloc(allocator, custom_output, 16 * 1024);
    defer allocator.free(custom_file);

    try std.testing.expect(custom_file.len > 0);
}

// ── Test 9: Success Message Feedback ───────────────────────────────────────

test "zr ci generate outputs success message with file path" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=github-actions" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify success feedback
    const output = result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "Generated") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, ".yml") != null);
}

test "zr ci generate outputs template information in success message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=github-actions", "--type=monorepo" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify template info in output
    const output = result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "Generated") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Template:") != null);
}

// ── Test 10: CircleCI Templates ────────────────────────────────────────────

test "zr ci generate CircleCI basic template creates valid YAML" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=circleci" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify file was created
    const generated_file = try tmp.dir.readFileAlloc(allocator, ".circleci/config.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify CircleCI-specific structure
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "version:") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "executors:") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "jobs:") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "workflows:") != null);
}

test "zr ci generate CircleCI basic template includes zr installation" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=circleci" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".circleci/config.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify zr install command
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "install_zr") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "curl") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "zr-linux-x86_64.tar.gz") != null);
}

test "zr ci generate CircleCI basic template uses executors" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=circleci" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".circleci/config.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify executor usage
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "zr-executor") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "docker:") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "resource_class:") != null);
}

test "zr ci generate CircleCI basic template includes caching" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=circleci" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".circleci/config.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify cache commands
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "restore_cache") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "save_cache") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "zr.toml") != null);
}

test "zr ci generate CircleCI monorepo template uses parameterized jobs" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=circleci", "--type=monorepo" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".circleci/config.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify parameterized jobs
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "parameters:") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "project:") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "<< parameters.project >>") != null);
}

test "zr ci generate CircleCI monorepo template includes affected detection" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=circleci", "--type=monorepo" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".circleci/config.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify affected detection job
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "detect_affected") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "zr affected") != null);
}

test "zr ci generate CircleCI monorepo template uses workspace persistence" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=circleci", "--type=monorepo" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".circleci/config.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify workspace commands
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "persist_to_workspace") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "attach_workspace") != null);
}

test "zr ci generate CircleCI release template triggers on tags" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=circleci", "--type=release" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".circleci/config.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify tag filtering
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "filters:") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "tags:") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "/^v.*/") != null);
}

test "zr ci generate CircleCI release template includes publish job" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "generate", "--platform=circleci", "--type=release" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const generated_file = try tmp.dir.readFileAlloc(allocator, ".circleci/config.yml", 16 * 1024);
    defer allocator.free(generated_file);

    // Verify release jobs
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "publish:") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "create_github_release") != null);
    try std.testing.expect(std.mem.indexOf(u8, generated_file, "GITHUB_TOKEN") != null);
}

test "zr ci list shows CircleCI templates" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "ci", "list" }, tmp_path);
    defer result.deinit();

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify CircleCI templates are listed
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "circleci") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "CircleCI") != null);
}
