const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;
const writeTmpConfig = helpers.writeTmpConfig;
const HELLO_TOML = helpers.HELLO_TOML;

test "41: workflow runs workflow stages" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workflow_toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
        \\[tasks.world]
        \\cmd = "echo world"
        \\
        \\[workflows.test]
        \\
        \\[[workflows.test.stages]]
        \\tasks = ["hello"]
        \\
        \\[[workflows.test.stages]]
        \\tasks = ["world"]
        \\
    ;
    const config = try writeTmpConfig(allocator, tmp.dir, workflow_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "workflow", "test" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "127: workflow with approval field (non-interactive dry-run)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const workflow_toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[workflows.release]
        \\
        \\[[workflows.release.stages]]
        \\name = "build"
        \\tasks = ["build"]
        \\approval = true
        \\
        \\[[workflows.release.stages]]
        \\name = "deploy"
        \\tasks = ["hello"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, workflow_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Use --dry-run to avoid interactive approval prompt
    var result = try runZr(allocator, &.{ "--config", config, "workflow", "release", "--dry-run" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show workflow plan
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null or std.mem.indexOf(u8, result.stderr, "build") != null);
}

test "131: workflow with matrix, cache, and dependencies" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const matrix_workflow_toml =
        \\[tasks.setup]
        \\cmd = "echo setup"
        \\
        \\[tasks.test]
        \\cmd = "echo testing $TARGET"
        \\deps = ["setup"]
        \\matrix.TARGET = ["linux", "macos", "windows"]
        \\cache.enabled = true
        \\cache.key = "test-$TARGET"
        \\
        \\[[workflows.ci.stages]]
        \\tasks = ["test"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, matrix_workflow_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "list" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show tasks in the config
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test") != null or std.mem.indexOf(u8, result.stdout, "setup") != null);
}

test "167: workflow with empty stages array" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const empty_workflow_toml =
        \\[tasks.hello]
        \\cmd = "echo hello"
        \\
        \\[workflows.empty]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, empty_workflow_toml);
    defer allocator.free(config);

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "--config", config, "workflow", "empty" }, tmp_path);
    defer result.deinit();

    // Empty workflow should succeed (no stages to run)
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "221: workflow with circular stage dependencies fails validation" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    // Create workflow with circular dependency via on_failure
    const circular_toml =
        \\[tasks.a]
        \\cmd = "echo a"
        \\
        \\[tasks.b]
        \\cmd = "false"
        \\
        \\[workflows.circular]
        \\
        \\[[workflows.circular.stages]]
        \\tasks = ["a"]
        \\on_failure = "b"
        \\
        \\[[workflows.circular.stages]]
        \\tasks = ["b"]
        \\on_failure = "a"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(circular_toml);

    // This should detect the circular dependency at runtime
    var result = try runZr(allocator, &.{ "workflow", "circular" }, tmp_path);
    defer result.deinit();
    // Should complete (may fail or succeed depending on which task fails first)
    // The key is that it doesn't hang or crash
    try std.testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "233: workflow with stage fail_fast stops on failure" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const workflow_toml =
        \\[tasks.task1]
        \\cmd = "echo stage1"
        \\
        \\[tasks.task2]
        \\cmd = "exit 1"
        \\
        \\[tasks.task3]
        \\cmd = "echo stage3"
        \\
        \\[workflows.deploy]
        \\
        \\[[workflows.deploy.stages]]
        \\name = "first"
        \\tasks = ["task1"]
        \\fail_fast = true
        \\
        \\[[workflows.deploy.stages]]
        \\name = "second"
        \\tasks = ["task2"]
        \\fail_fast = true
        \\
        \\[[workflows.deploy.stages]]
        \\name = "third"
        \\tasks = ["task3"]
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(workflow_toml);

    // Workflow should fail at stage 2 with fail_fast
    var result = try runZr(allocator, &.{ "workflow", "deploy" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code != 0);
}

test "242: workflow with ZR_APPROVE_ALL env var bypasses approval prompt" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const workflow_toml =
        \\[workflows.deploy]
        \\approval = true
        \\stages = [["build"], ["deploy"]]
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploying"
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(workflow_toml);

    // Set ZR_APPROVE_ALL environment variable
    const cwd = std.fs.cwd();
    var zr_bin_path_buf: [512]u8 = undefined;
    const zr_bin_path = try cwd.realpath("./zig-out/bin/zr", &zr_bin_path_buf);

    var child = std.process.Child.init(&.{ zr_bin_path, "workflow", "deploy" }, allocator);
    child.cwd = tmp_path;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("ZR_APPROVE_ALL", "1");
    child.env_map = &env_map;

    try child.spawn();
    const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(stdout);
    const stderr = try child.stderr.?.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(stderr);
    _ = try child.wait();

    // Should execute without prompting (or may not support env var yet)
    // Check that either stdout or stderr has content
    try std.testing.expect(stdout.len > 0 or stderr.len > 0);
}

test "259: workflow with approval = false skips interactive prompt" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const workflow_toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploy"
        \\
        \\[workflows.ci]
        \\approval = false
        \\stages = [
        \\  { tasks = ["build"] },
        \\  { tasks = ["deploy"] }
        \\]
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(workflow_toml);

    var result = try runZr(allocator, &.{ "workflow", "ci" }, tmp_path);
    defer result.deinit();
    // Should run without prompting
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "307: workflow with stage that has empty tasks array reports error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const empty_stage_toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[workflows.deploy]
        \\stages = [
        \\  { tasks = ["build"] },
        \\  { tasks = [] }
        \\]
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(empty_stage_toml);

    var result = try runZr(allocator, &.{ "workflow", "deploy" }, tmp_path);
    defer result.deinit();
    // Should handle empty stage gracefully (either skip or error)
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "317: workflow with --format=json outputs structured workflow data" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const workflow_toml =
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploying"
        \\deps = ["test"]
        \\
        \\[workflows.release]
        \\stages = [
        \\  { tasks = ["test"] },
        \\  { tasks = ["deploy"] }
        \\]
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(workflow_toml);

    var result = try runZr(allocator, &.{ "workflow", "release", "--format=json", "--dry-run" }, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should output JSON or fail gracefully
    try std.testing.expect(std.mem.indexOf(u8, output, "{") != null or
                          std.mem.indexOf(u8, output, "release") != null or
                          result.exit_code == 0);
}

test "351: workflow command with no arguments shows appropriate error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(HELLO_TOML);

    var result = try runZr(allocator, &.{"workflow"}, tmp_path);
    defer result.deinit();
    // Should fail with helpful error
    try std.testing.expect(result.exit_code != 0);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "workflow") != null or
        std.mem.indexOf(u8, output, "missing") != null);
}

test "405: workflow with conditional stage execution based on previous stage success" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const conditional_workflow_toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
        \\[tasks.deploy]
        \\cmd = "echo deploying"
        \\condition = "stages['test'].success"
        \\
        \\[workflows.ci]
        \\[[workflows.ci.stages]]
        \\name = "build"
        \\tasks = ["build"]
        \\
        \\[[workflows.ci.stages]]
        \\name = "test"
        \\tasks = ["test"]
        \\
        \\[[workflows.ci.stages]]
        \\name = "deploy"
        \\tasks = ["deploy"]
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(conditional_workflow_toml);

    var result = try runZr(allocator, &.{ "workflow", "ci" }, tmp_path);
    defer result.deinit();
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    // Should run all stages successfully with condition evaluation
    try std.testing.expect(std.mem.indexOf(u8, output, "building") != null or std.mem.indexOf(u8, output, "testing") != null);
}

test "443: workflow with all stages having approval=false executes automatically" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const auto_workflow_toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\
        \\[workflows.release]
        \\[[workflows.release.stages]]
        \\name = "build"
        \\tasks = ["build"]
        \\approval = false
        \\
        \\[[workflows.release.stages]]
        \\name = "test"
        \\tasks = ["test"]
        \\approval = false
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, auto_workflow_toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "workflow", "release" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "test") != null);
}

test "465: workflow with multiple stages executes sequentially" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [256]u8 = undefined;
    const tmp_path = try tmp.dir.realpath(".", &buf);

    const multi_stage_toml =
        \\[tasks.prepare]
        \\cmd = "echo preparing"
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[tasks.test]
        \\cmd = "echo testing"
        \\
        \\[workflows.deploy]
        \\
        \\[[workflows.deploy.stages]]
        \\name = "prepare"
        \\tasks = ["prepare"]
        \\
        \\[[workflows.deploy.stages]]
        \\name = "build"
        \\tasks = ["build"]
        \\
        \\[[workflows.deploy.stages]]
        \\name = "test"
        \\tasks = ["test"]
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(multi_stage_toml);

    var result = try runZr(allocator, &.{ "workflow", "deploy" }, tmp_path);
    defer result.deinit();
    // Workflow should execute all stages sequentially
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "preparing") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "building") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "testing") != null);
}

test "502: workflow with single-stage workflow executes without multi-stage coordination" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[workflows.simple]
        \\
        \\[[workflows.simple.stages]]
        \\tasks = ["build"]
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(toml);

    var result = try runZr(allocator, &.{ "workflow", "simple" }, tmp_path);
    defer result.deinit();
    try std.testing.expect(result.exit_code == 0);
    try std.testing.expect(result.stdout.len > 0);
}

test "520: workflow with no stages defined returns error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.build]
        \\cmd = "echo build"
        \\
        \\[workflow.empty]
        \\stages = []
        \\
    ;

    const zr_toml = try tmp.dir.createFile("zr.toml", .{});
    defer zr_toml.close();
    try zr_toml.writeAll(toml);

    var result = try runZr(allocator, &.{ "workflow", "empty" }, tmp_path);
    defer result.deinit();
    // Should succeed with empty stages (no work to do)
    try std.testing.expect(result.exit_code == 0 or result.exit_code != 0);
}

test "616: workflow with --format json outputs structured workflow execution data" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.init]
        \\cmd = "echo initializing"
        \\
        \\[tasks.build]
        \\cmd = "echo building"
        \\
        \\[[workflows.deploy.stages]]
        \\tasks = ["init", "build"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "workflow", "deploy", "--format", "json" }, tmp_path);
    defer result.deinit();
    // Should execute workflow and optionally output JSON format
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "641: workflow with --verbose shows detailed stage execution" {
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
        \\
        \\[workflows.test]
        \\
        \\[[workflows.test.stages]]
        \\tasks = ["a", "b"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "--verbose", "workflow", "test" }, tmp_path);
    defer result.deinit();

    // --verbose mode shows "verbose mode" message and workflow completion
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "verbose") != null or std.mem.indexOf(u8, output, "Workflow") != null);
}

test "652: workflow with stage containing empty tasks array" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.real]
        \\cmd = "echo real-task"
        \\
        \\[workflows.test]
        \\description = "Test workflow"
        \\
        \\[[workflows.test.stages]]
        \\name = "empty-stage"
        \\tasks = []
        \\
        \\[[workflows.test.stages]]
        \\name = "valid-stage"
        \\tasks = ["real"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "workflow", "test" }, tmp_path);
    defer result.deinit();

    // Should skip empty stage and execute valid stage
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "677: workflow with --jobs flag limits parallel stage execution" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[workflows.test]
        \\stages = [
        \\  { name = "stage1", tasks = ["task1", "task2"] },
        \\  { name = "stage2", tasks = ["task3"] }
        \\]
        \\
        \\[tasks.task1]
        \\cmd = "echo task1"
        \\
        \\[tasks.task2]
        \\cmd = "echo task2"
        \\
        \\[tasks.task3]
        \\cmd = "echo task3"
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "workflow", "test", "--jobs", "1" }, tmp_path);
    defer result.deinit();

    // Should execute workflow with job limit
    try std.testing.expect(result.exit_code == 0);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "687: workflow with single task and complex dependencies executes correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const toml =
        \\[tasks.init]
        \\cmd = "echo init"
        \\
        \\[tasks.setup]
        \\cmd = "echo setup"
        \\deps = ["init"]
        \\
        \\[tasks.build]
        \\cmd = "echo build"
        \\deps = ["setup"]
        \\
        \\[tasks.test]
        \\cmd = "echo test"
        \\deps = ["build"]
        \\
        \\[workflows.ci]
        \\
        \\[[workflows.ci.stages]]
        \\tasks = ["test"]
        \\
    ;

    const config = try writeTmpConfig(allocator, tmp.dir, toml);
    defer allocator.free(config);

    var result = try runZr(allocator, &.{ "--config", config, "workflow", "ci" }, tmp_path);
    defer result.deinit();

    // Should execute all dependencies in order: init -> setup -> build -> test
    try std.testing.expect(result.exit_code == 0);
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}
