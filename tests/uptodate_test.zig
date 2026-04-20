const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ────────────────────────────────────────────────────────────────────────────
// Test 1: Basic mtime comparison — newer source triggers rebuild
// ────────────────────────────────────────────────────────────────────────────

test "uptodate: newer source file triggers task execution" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const uptodate_toml =
        \\[tasks.build]
        \\cmd = "echo 'Building' > dist/output.txt"
        \\sources = ["src/input.txt"]
        \\generates = ["dist/output.txt"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, uptodate_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create initial source and output
    try tmp.dir.makeDir("src");
    try tmp.dir.makeDir("dist");
    try tmp.dir.writeFile(.{ .sub_path = "src/input.txt", .data = "v1" });
    try tmp.dir.writeFile(.{ .sub_path = "dist/output.txt", .data = "old" });

    // First run: output older than source → task should run
    var result1 = try runZr(allocator, &.{ "--config", config, "run", "build" }, tmp_path);
    defer result1.deinit();

    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);
    const combined1 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result1.stdout, result1.stderr });
    defer allocator.free(combined1);
    try std.testing.expect(std.mem.indexOf(u8, combined1, "Building") != null);

    // Wait to ensure mtime difference
    std.Thread.sleep(10_000_000); // 10ms

    // Second run: output up-to-date → task should skip
    var result2 = try runZr(allocator, &.{ "--config", config, "run", "build" }, tmp_path);
    defer result2.deinit();

    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
    const combined2 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result2.stdout, result2.stderr });
    defer allocator.free(combined2);
    // Task should be skipped (output should indicate no execution)
    try std.testing.expect(std.mem.indexOf(u8, combined2, "up-to-date") != null or
        std.mem.indexOf(u8, combined2, "skipped") != null or
        std.mem.indexOf(u8, combined2, "Building") == null);

    // Modify source → task should run again
    std.Thread.sleep(10_000_000); // 10ms
    try tmp.dir.writeFile(.{ .sub_path = "src/input.txt", .data = "v2" });

    var result3 = try runZr(allocator, &.{ "--config", config, "run", "build" }, tmp_path);
    defer result3.deinit();

    try std.testing.expectEqual(@as(u8, 0), result3.exit_code);
    const combined3 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result3.stdout, result3.stderr });
    defer allocator.free(combined3);
    try std.testing.expect(std.mem.indexOf(u8, combined3, "Building") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 2: Multiple sources — any newer source triggers rebuild
// ────────────────────────────────────────────────────────────────────────────

test "uptodate: any modified source triggers rebuild" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const uptodate_toml =
        \\[tasks.compile]
        \\cmd = "echo 'Compiling' > build/app"
        \\sources = ["src/main.zig", "src/lib.zig", "build.zig"]
        \\generates = ["build/app"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, uptodate_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create sources and output
    try tmp.dir.makeDir("src");
    try tmp.dir.makeDir("build");
    try tmp.dir.writeFile(.{ .sub_path = "src/main.zig", .data = "pub fn main() void {}" });
    try tmp.dir.writeFile(.{ .sub_path = "src/lib.zig", .data = "pub fn lib() void {}" });
    try tmp.dir.writeFile(.{ .sub_path = "build.zig", .data = "const std = @import(\"std\");" });

    // First run
    var result1 = try runZr(allocator, &.{ "--config", config, "run", "compile" }, tmp_path);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);

    std.Thread.sleep(10_000_000); // 10ms

    // Second run: up-to-date
    var result2 = try runZr(allocator, &.{ "--config", config, "run", "compile" }, tmp_path);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
    const combined2 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result2.stdout, result2.stderr });
    defer allocator.free(combined2);
    try std.testing.expect(std.mem.indexOf(u8, combined2, "Compiling") == null);

    // Modify ONE source (lib.zig) → should trigger rebuild
    std.Thread.sleep(10_000_000); // 10ms
    try tmp.dir.writeFile(.{ .sub_path = "src/lib.zig", .data = "pub fn lib() void { return; }" });

    var result3 = try runZr(allocator, &.{ "--config", config, "run", "compile" }, tmp_path);
    defer result3.deinit();
    try std.testing.expectEqual(@as(u8, 0), result3.exit_code);
    const combined3 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result3.stdout, result3.stderr });
    defer allocator.free(combined3);
    try std.testing.expect(std.mem.indexOf(u8, combined3, "Compiling") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 3: Multiple generates — all must exist and be newer
// ────────────────────────────────────────────────────────────────────────────

test "uptodate: all generates must exist and be up-to-date" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const uptodate_toml =
        \\[tasks.bundle]
        \\cmd = "echo 'Bundling' && touch dist/app.js dist/app.css"
        \\sources = ["src/index.js"]
        \\generates = ["dist/app.js", "dist/app.css"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, uptodate_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create source and partial output
    try tmp.dir.makeDir("src");
    try tmp.dir.makeDir("dist");
    try tmp.dir.writeFile(.{ .sub_path = "src/index.js", .data = "console.log('hi')" });
    try tmp.dir.writeFile(.{ .sub_path = "dist/app.js", .data = "// output" });
    // app.css is MISSING

    // First run: missing generate → task should run
    var result1 = try runZr(allocator, &.{ "--config", config, "run", "bundle" }, tmp_path);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);
    const combined1 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result1.stdout, result1.stderr });
    defer allocator.free(combined1);
    try std.testing.expect(std.mem.indexOf(u8, combined1, "Bundling") != null);

    std.Thread.sleep(10_000_000); // 10ms

    // Second run: both generates exist and up-to-date → task should skip
    var result2 = try runZr(allocator, &.{ "--config", config, "run", "bundle" }, tmp_path);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
    const combined2 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result2.stdout, result2.stderr });
    defer allocator.free(combined2);
    try std.testing.expect(std.mem.indexOf(u8, combined2, "Bundling") == null);

    // Delete one generate → task should run again
    std.Thread.sleep(10_000_000); // 10ms
    try tmp.dir.deleteFile("dist/app.css");

    var result3 = try runZr(allocator, &.{ "--config", config, "run", "bundle" }, tmp_path);
    defer result3.deinit();
    try std.testing.expectEqual(@as(u8, 0), result3.exit_code);
    const combined3 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result3.stdout, result3.stderr });
    defer allocator.free(combined3);
    try std.testing.expect(std.mem.indexOf(u8, combined3, "Bundling") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 4: Missing generates — task always runs
// ────────────────────────────────────────────────────────────────────────────

test "uptodate: missing generate file forces task execution" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const uptodate_toml =
        \\[tasks.gen]
        \\cmd = "echo 'Generating' > output/result.txt"
        \\sources = ["input.txt"]
        \\generates = ["output/result.txt"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, uptodate_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create source but NO output
    try tmp.dir.writeFile(.{ .sub_path = "input.txt", .data = "data" });
    try tmp.dir.makeDir("output");

    // First run: no output exists → task should run
    var result1 = try runZr(allocator, &.{ "--config", config, "run", "gen" }, tmp_path);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);
    const combined1 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result1.stdout, result1.stderr });
    defer allocator.free(combined1);
    try std.testing.expect(std.mem.indexOf(u8, combined1, "Generating") != null);

    // Verify output was created
    const output = try tmp.dir.readFileAlloc(allocator, "output/result.txt", 1024);
    defer allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "Generating") != null);

    std.Thread.sleep(10_000_000); // 10ms

    // Second run: output exists and up-to-date → task should skip
    var result2 = try runZr(allocator, &.{ "--config", config, "run", "gen" }, tmp_path);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
    const combined2 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result2.stdout, result2.stderr });
    defer allocator.free(combined2);
    try std.testing.expect(std.mem.indexOf(u8, combined2, "Generating") == null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 5: Glob patterns for sources and generates
// ────────────────────────────────────────────────────────────────────────────

test "uptodate: glob patterns expand correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const uptodate_toml =
        \\[tasks.compile_ts]
        \\cmd = "echo 'Compiling TypeScript' && touch dist/bundle.js"
        \\sources = ["src/**/*.ts", "tsconfig.json"]
        \\generates = ["dist/bundle.js"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, uptodate_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create nested source structure
    try tmp.dir.makeDir("src");
    try tmp.dir.makeDir("src/components");
    try tmp.dir.makeDir("dist");
    try tmp.dir.writeFile(.{ .sub_path = "src/main.ts", .data = "import {App} from './app'" });
    try tmp.dir.writeFile(.{ .sub_path = "src/components/App.ts", .data = "export class App {}" });
    try tmp.dir.writeFile(.{ .sub_path = "tsconfig.json", .data = "{\"compilerOptions\":{}}" });

    // First run: no output → task should run
    var result1 = try runZr(allocator, &.{ "--config", config, "run", "compile_ts" }, tmp_path);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);
    const combined1 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result1.stdout, result1.stderr });
    defer allocator.free(combined1);
    try std.testing.expect(std.mem.indexOf(u8, combined1, "Compiling TypeScript") != null);

    std.Thread.sleep(10_000_000); // 10ms

    // Second run: up-to-date → task should skip
    var result2 = try runZr(allocator, &.{ "--config", config, "run", "compile_ts" }, tmp_path);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
    const combined2 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result2.stdout, result2.stderr });
    defer allocator.free(combined2);
    try std.testing.expect(std.mem.indexOf(u8, combined2, "Compiling TypeScript") == null);

    // Modify nested file matched by glob → task should run
    std.Thread.sleep(10_000_000); // 10ms
    try tmp.dir.writeFile(.{ .sub_path = "src/components/App.ts", .data = "export class App { render() {} }" });

    var result3 = try runZr(allocator, &.{ "--config", config, "run", "compile_ts" }, tmp_path);
    defer result3.deinit();
    try std.testing.expectEqual(@as(u8, 0), result3.exit_code);
    const combined3 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result3.stdout, result3.stderr });
    defer allocator.free(combined3);
    try std.testing.expect(std.mem.indexOf(u8, combined3, "Compiling TypeScript") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 6: --force flag ignores up-to-date check
// ────────────────────────────────────────────────────────────────────────────

test "uptodate: --force flag always runs task" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const uptodate_toml =
        \\[tasks.build]
        \\cmd = "echo 'Building with force'"
        \\sources = ["src.txt"]
        \\generates = ["out.txt"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, uptodate_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create source and output
    try tmp.dir.writeFile(.{ .sub_path = "src.txt", .data = "input" });
    try tmp.dir.writeFile(.{ .sub_path = "out.txt", .data = "output" });

    std.Thread.sleep(10_000_000); // 10ms

    // First run without force: up-to-date → should skip
    var result1 = try runZr(allocator, &.{ "--config", config, "run", "build" }, tmp_path);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);
    const combined1 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result1.stdout, result1.stderr });
    defer allocator.free(combined1);
    try std.testing.expect(std.mem.indexOf(u8, combined1, "Building with force") == null);

    // Second run WITH --force: should run even if up-to-date
    var result2 = try runZr(allocator, &.{ "--config", config, "run", "--force", "build" }, tmp_path);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
    const combined2 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result2.stdout, result2.stderr });
    defer allocator.free(combined2);
    try std.testing.expect(std.mem.indexOf(u8, combined2, "Building with force") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 7: --dry-run shows correct skip/run decisions
// ────────────────────────────────────────────────────────────────────────────

test "uptodate: --dry-run shows skip/run preview" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const uptodate_toml =
        \\[tasks.fresh]
        \\cmd = "echo 'Fresh task'"
        \\sources = ["fresh.in"]
        \\generates = ["fresh.out"]
        \\
        \\[tasks.stale]
        \\cmd = "echo 'Stale task'"
        \\sources = ["stale.in"]
        \\generates = ["stale.out"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, uptodate_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create sources
    try tmp.dir.writeFile(.{ .sub_path = "fresh.in", .data = "data" });
    try tmp.dir.writeFile(.{ .sub_path = "stale.in", .data = "data" });

    // Run both tasks to create outputs
    var result_init = try runZr(allocator, &.{ "--config", config, "run", "fresh", "stale" }, tmp_path);
    defer result_init.deinit();
    try std.testing.expectEqual(@as(u8, 0), result_init.exit_code);

    std.Thread.sleep(10_000_000); // 10ms

    // Modify stale.in → only stale should be marked for execution
    try tmp.dir.writeFile(.{ .sub_path = "stale.in", .data = "new data" });

    std.Thread.sleep(10_000_000); // 10ms

    // Dry-run: should show fresh as skip, stale as run
    var result = try runZr(allocator, &.{ "--config", config, "run", "--dry-run", "fresh", "stale" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(combined);

    // Verify dry-run output shows correct decisions
    try std.testing.expect(std.mem.indexOf(u8, combined, "fresh") != null);
    try std.testing.expect(std.mem.indexOf(u8, combined, "stale") != null);
    try std.testing.expect(std.mem.indexOf(u8, combined, "skip") != null or
        std.mem.indexOf(u8, combined, "up-to-date") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 8: Dependencies — both up-to-date skips both
// ────────────────────────────────────────────────────────────────────────────

test "uptodate: up-to-date dependency and task both skip" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const uptodate_toml =
        \\[tasks.compile]
        \\cmd = "echo 'Compiling' > lib.o"
        \\sources = ["lib.c"]
        \\generates = ["lib.o"]
        \\
        \\[tasks.link]
        \\cmd = "echo 'Linking' > app"
        \\sources = ["main.c", "lib.o"]
        \\generates = ["app"]
        \\deps = ["compile"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, uptodate_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create all sources
    try tmp.dir.writeFile(.{ .sub_path = "lib.c", .data = "void lib() {}" });
    try tmp.dir.writeFile(.{ .sub_path = "main.c", .data = "int main() {}" });

    // First run: creates lib.o and app
    var result1 = try runZr(allocator, &.{ "--config", config, "run", "link" }, tmp_path);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);
    const combined1 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result1.stdout, result1.stderr });
    defer allocator.free(combined1);
    try std.testing.expect(std.mem.indexOf(u8, combined1, "Compiling") != null);
    try std.testing.expect(std.mem.indexOf(u8, combined1, "Linking") != null);

    std.Thread.sleep(10_000_000); // 10ms

    // Second run: both up-to-date → both should skip
    var result2 = try runZr(allocator, &.{ "--config", config, "run", "link" }, tmp_path);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
    const combined2 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result2.stdout, result2.stderr });
    defer allocator.free(combined2);
    try std.testing.expect(std.mem.indexOf(u8, combined2, "Compiling") == null);
    try std.testing.expect(std.mem.indexOf(u8, combined2, "Linking") == null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 9: Dependencies — stale dependency forces dependent to run
// ────────────────────────────────────────────────────────────────────────────

test "uptodate: stale dependency forces dependent task to run" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const uptodate_toml =
        \\[tasks.preprocess]
        \\cmd = "echo 'Preprocessing' > data.processed"
        \\sources = ["data.raw"]
        \\generates = ["data.processed"]
        \\
        \\[tasks.analyze]
        \\cmd = "echo 'Analyzing' > report.txt"
        \\sources = ["data.processed"]
        \\generates = ["report.txt"]
        \\deps = ["preprocess"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, uptodate_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create initial data
    try tmp.dir.writeFile(.{ .sub_path = "data.raw", .data = "raw data" });

    // First run: both tasks execute
    var result1 = try runZr(allocator, &.{ "--config", config, "run", "analyze" }, tmp_path);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);

    std.Thread.sleep(10_000_000); // 10ms

    // Modify data.raw → preprocess stale → analyze must run even if report.txt is newer
    try tmp.dir.writeFile(.{ .sub_path = "data.raw", .data = "new raw data" });

    std.Thread.sleep(10_000_000); // 10ms

    var result2 = try runZr(allocator, &.{ "--config", config, "run", "analyze" }, tmp_path);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
    const combined2 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result2.stdout, result2.stderr });
    defer allocator.free(combined2);

    // Both tasks should run
    try std.testing.expect(std.mem.indexOf(u8, combined2, "Preprocessing") != null);
    try std.testing.expect(std.mem.indexOf(u8, combined2, "Analyzing") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 10: No sources/generates — backward compatibility (always run)
// ────────────────────────────────────────────────────────────────────────────

test "uptodate: tasks without sources/generates always run" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const uptodate_toml =
        \\[tasks.always_run]
        \\cmd = "echo 'Always running'"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, uptodate_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // First run
    var result1 = try runZr(allocator, &.{ "--config", config, "run", "always_run" }, tmp_path);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);
    const combined1 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result1.stdout, result1.stderr });
    defer allocator.free(combined1);
    try std.testing.expect(std.mem.indexOf(u8, combined1, "Always running") != null);

    // Second run: should STILL run (no up-to-date check)
    var result2 = try runZr(allocator, &.{ "--config", config, "run", "always_run" }, tmp_path);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
    const combined2 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result2.stdout, result2.stderr });
    defer allocator.free(combined2);
    try std.testing.expect(std.mem.indexOf(u8, combined2, "Always running") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 11: Empty generates — task always runs
// ────────────────────────────────────────────────────────────────────────────

test "uptodate: task with sources but no generates always runs" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const uptodate_toml =
        \\[tasks.validate]
        \\cmd = "echo 'Validating input'"
        \\sources = ["config.json"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, uptodate_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "config.json", .data = "{}" });

    // First run
    var result1 = try runZr(allocator, &.{ "--config", config, "run", "validate" }, tmp_path);
    defer result1.deinit();
    try std.testing.expectEqual(@as(u8, 0), result1.exit_code);
    const combined1 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result1.stdout, result1.stderr });
    defer allocator.free(combined1);
    try std.testing.expect(std.mem.indexOf(u8, combined1, "Validating input") != null);

    std.Thread.sleep(10_000_000); // 10ms

    // Second run: no generates to check → should STILL run
    var result2 = try runZr(allocator, &.{ "--config", config, "run", "validate" }, tmp_path);
    defer result2.deinit();
    try std.testing.expectEqual(@as(u8, 0), result2.exit_code);
    const combined2 = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result2.stdout, result2.stderr });
    defer allocator.free(combined2);
    try std.testing.expect(std.mem.indexOf(u8, combined2, "Validating input") != null);
}

// ────────────────────────────────────────────────────────────────────────────
// Test 12: list --status shows task states
// ────────────────────────────────────────────────────────────────────────────

test "uptodate: list --status shows up-to-date, stale, never-run" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const uptodate_toml =
        \\[tasks.fresh]
        \\cmd = "echo 'Fresh' > fresh.out"
        \\sources = ["fresh.in"]
        \\generates = ["fresh.out"]
        \\
        \\[tasks.stale]
        \\cmd = "echo 'Stale' > stale.out"
        \\sources = ["stale.in"]
        \\generates = ["stale.out"]
        \\
        \\[tasks.never]
        \\cmd = "echo 'Never' > never.out"
        \\sources = ["never.in"]
        \\generates = ["never.out"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, uptodate_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create sources
    try tmp.dir.writeFile(.{ .sub_path = "fresh.in", .data = "data" });
    try tmp.dir.writeFile(.{ .sub_path = "stale.in", .data = "data" });
    try tmp.dir.writeFile(.{ .sub_path = "never.in", .data = "data" });

    // Run fresh and stale (not never)
    var result_run = try runZr(allocator, &.{ "--config", config, "run", "fresh", "stale" }, tmp_path);
    defer result_run.deinit();
    try std.testing.expectEqual(@as(u8, 0), result_run.exit_code);

    std.Thread.sleep(10_000_000); // 10ms

    // Modify stale.in → make stale task stale
    try tmp.dir.writeFile(.{ .sub_path = "stale.in", .data = "modified data" });

    std.Thread.sleep(10_000_000); // 10ms

    // List with --status
    var result = try runZr(allocator, &.{ "--config", config, "list", "--status" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    const output = try std.fmt.allocPrint(allocator, "{s}{s}", .{ result.stdout, result.stderr });
    defer allocator.free(output);

    // Verify status indicators
    try std.testing.expect(std.mem.indexOf(u8, output, "fresh") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "stale") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "never") != null);

    // Should show different states (exact format TBD by implementation)
    try std.testing.expect(std.mem.indexOf(u8, output, "up-to-date") != null or
        std.mem.indexOf(u8, output, "✓") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "stale") != null or
        std.mem.indexOf(u8, output, "✗") != null or
        std.mem.indexOf(u8, output, "outdated") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "never-run") != null or
        std.mem.indexOf(u8, output, "–") != null);
}
