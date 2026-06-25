const std = @import("std");
const testing = std.testing;
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;

// ── JUnit XML Output Tests ───────────────────────────────────────────────────
//
// Tests for `--junit <file>` flag (v1.106.0):
//
// 36000: --junit creates XML file on success
// 36001: --junit records failure with exit code
// 36002: --junit with dependency chain records all tasks
// 36003: --junit= form works (equals sign syntax)
// 36004: --junit includes time attribute
// 36005: --junit overwrites existing file
// 36006: --junit requires a file path (error case)
// 36007: --junit multiple tasks via dependency chain all appear
//

// Test 36000: --junit creates XML file on success
test "junit: --junit creates XML file on success" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo compiled"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    const junit_file = try std.fs.path.join(testing.allocator, &.{ tmp_path, "results.xml" });
    defer testing.allocator.free(junit_file);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "build", "--junit", junit_file }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    // Verify XML file exists and is readable
    const xml_content = try tmp.dir.readFileAlloc(testing.allocator, "results.xml", 65536);
    defer testing.allocator.free(xml_content);

    // Verify XML structure
    try testing.expect(std.mem.indexOf(u8, xml_content, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>") != null);
    try testing.expect(std.mem.indexOf(u8, xml_content, "<testsuites") != null);
    try testing.expect(std.mem.indexOf(u8, xml_content, "name=\"build\"") != null);
    try testing.expect(std.mem.indexOf(u8, xml_content, "failures=\"0\"") != null);
    try testing.expect(std.mem.indexOf(u8, xml_content, "<testcase") != null);
}

// Test 36001: --junit records failure with exit code
test "junit: --junit records failure with exit code" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.fail-task]
        \\cmd = "sh -c 'exit 1'"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    const junit_file = try std.fs.path.join(testing.allocator, &.{ tmp_path, "results.xml" });
    defer testing.allocator.free(junit_file);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "fail-task", "--junit", junit_file }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 1);

    // Verify XML file exists
    const xml_content = try tmp.dir.readFileAlloc(testing.allocator, "results.xml", 65536);
    defer testing.allocator.free(xml_content);

    // Verify failure element
    try testing.expect(std.mem.indexOf(u8, xml_content, "<failure") != null);
    try testing.expect(std.mem.indexOf(u8, xml_content, "exit code 1") != null);
    try testing.expect(std.mem.indexOf(u8, xml_content, "failures=\"1\"") != null);
}

// Test 36002: --junit with dependency chain records all tasks
test "junit: --junit with dependency chain records all tasks" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.compile]
        \\cmd = "echo compile"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\deps = ["compile"]
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    const junit_file = try std.fs.path.join(testing.allocator, &.{ tmp_path, "results.xml" });
    defer testing.allocator.free(junit_file);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "test", "--junit", junit_file }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const xml_content = try tmp.dir.readFileAlloc(testing.allocator, "results.xml", 65536);
    defer testing.allocator.free(xml_content);

    // Verify both tasks appear in the report
    try testing.expect(std.mem.indexOf(u8, xml_content, "tests=\"2\"") != null);
    try testing.expect(std.mem.indexOf(u8, xml_content, "name=\"compile\"") != null);
    try testing.expect(std.mem.indexOf(u8, xml_content, "name=\"test\"") != null);
}

// Test 36003: --junit= form works (equals sign syntax)
test "junit: --junit= form works (equals sign syntax)" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo ok"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    const junit_arg = try std.fmt.allocPrint(testing.allocator, "--junit={s}/report.xml", .{tmp_path});
    defer testing.allocator.free(junit_arg);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "build", junit_arg }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    // Verify XML file exists
    const xml_content = try tmp.dir.readFileAlloc(testing.allocator, "report.xml", 65536);
    defer testing.allocator.free(xml_content);

    try testing.expect(std.mem.indexOf(u8, xml_content, "<testsuites") != null);
}

// Test 36004: --junit includes time attribute
test "junit: --junit includes time attribute" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo ok"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    const junit_file = try std.fs.path.join(testing.allocator, &.{ tmp_path, "results.xml" });
    defer testing.allocator.free(junit_file);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "build", "--junit", junit_file }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const xml_content = try tmp.dir.readFileAlloc(testing.allocator, "results.xml", 65536);
    defer testing.allocator.free(xml_content);

    // Verify time attributes exist in testcase element
    try testing.expect(std.mem.indexOf(u8, xml_content, "time=\"") != null);
}

// Test 36005: --junit overwrites existing file
test "junit: --junit overwrites existing file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo ok"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    // Create initial junk file
    try tmp.dir.writeFile(.{ .sub_path = "results.xml", .data = "JUNK_CONTENT_SHOULD_BE_OVERWRITTEN" });

    const junit_file = try std.fs.path.join(testing.allocator, &.{ tmp_path, "results.xml" });
    defer testing.allocator.free(junit_file);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "build", "--junit", junit_file }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const xml_content = try tmp.dir.readFileAlloc(testing.allocator, "results.xml", 65536);
    defer testing.allocator.free(xml_content);

    // Verify file was overwritten with valid XML
    try testing.expect(std.mem.indexOf(u8, xml_content, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>") != null);
    try testing.expect(std.mem.indexOf(u8, xml_content, "JUNK_CONTENT") == null);
}

// Test 36006: --junit requires a file path (error case)
test "junit: --junit requires a file path (error case)" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.build]
        \\cmd = "echo ok"
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    // Run without providing a file path after --junit
    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "build", "--junit" }, tmp_path);
    defer result.deinit();

    // Should fail
    try testing.expect(result.exit_code != 0);
}

// Test 36007: --junit with multiple tasks via dependency chain
test "junit: --junit multiple tasks via dependency chain all appear" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const toml =
        \\[tasks.step1]
        \\cmd = "echo step1"
        \\
        \\[tasks.step2]
        \\cmd = "echo step2"
        \\deps = ["step1"]
        \\
        \\[tasks.step3]
        \\cmd = "echo step3"
        \\deps = ["step2"]
    ;

    const config = try writeTmpConfig(testing.allocator, tmp.dir, toml);
    defer testing.allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    const junit_file = try std.fs.path.join(testing.allocator, &.{ tmp_path, "results.xml" });
    defer testing.allocator.free(junit_file);

    var result = try runZr(testing.allocator, &.{ "--config", config, "run", "step3", "--junit", junit_file }, tmp_path);
    defer result.deinit();

    try testing.expect(result.exit_code == 0);

    const xml_content = try tmp.dir.readFileAlloc(testing.allocator, "results.xml", 65536);
    defer testing.allocator.free(xml_content);

    // Verify all 3 tasks appear in the report
    try testing.expect(std.mem.indexOf(u8, xml_content, "tests=\"3\"") != null);
    try testing.expect(std.mem.indexOf(u8, xml_content, "name=\"step1\"") != null);
    try testing.expect(std.mem.indexOf(u8, xml_content, "name=\"step2\"") != null);
    try testing.expect(std.mem.indexOf(u8, xml_content, "name=\"step3\"") != null);
}
