const std = @import("std");
const helpers = @import("helpers.zig");

const runZr = helpers.runZr;
const runZrWithStdin = helpers.runZrWithStdin;
const writeTmpConfig = helpers.writeTmpConfig;

test "921: template with no subcommand shows usage error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const result = try runZr(allocator, &[_][]const u8{"template"}, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Usage: zr template") != null);
}

test "922: template with invalid subcommand shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create minimal config
    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{ "template", "invalid" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Unknown template subcommand") != null);
}

test "923: template list with no templates shows message" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create config with no templates
    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{ "template", "list" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "No templates defined") != null);
}

test "924: template list shows available templates" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create config with templates (using section format)
    const config =
        \\[templates.test-watch]
        \\description = "Run tests in watch mode"
        \\params = ["port"]
        \\cmd = "npm test -- --watch --port={{port}}"
        \\
        \\[templates.build-deploy]
        \\description = "Build and deploy application"
        \\params = ["env", "version"]
        \\cmd = "npm run deploy -- --env={{env}} --version={{version}}"
        \\
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{ "template", "list" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Available Templates") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "test-watch") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build-deploy") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Run tests in watch mode") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Parameters: port") != null);
}

test "925: template show without name shows usage error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create minimal config
    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{ "template", "show" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "template name required") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Usage: zr template show") != null);
}

test "926: template show with non-existent template shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create config with no templates
    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{ "template", "show", "nonexistent" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "template 'nonexistent' not found") != null);
}

test "927: template show displays detailed template information" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create config with a comprehensive template (using section format)
    const config =
        \\[templates.test-watch]
        \\description = "Run tests in watch mode"
        \\params = ["port", "host"]
        \\cmd = "npm test -- --watch --port={{port}} --host={{host}}"
        \\cwd = "./tests"
        \\timeout = "60s"
        \\allow_failure = true
        \\deps = ["build"]
        \\env = { NODE_ENV = "test" }
        \\
        \\[tasks.build]
        \\cmd = "echo building"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{ "template", "show", "test-watch" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Template: test-watch") != null or
        std.mem.indexOf(u8, result.stdout, "Template:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Run tests in watch mode") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Parameters:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "port") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "host") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Command:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "npm test") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Working Directory: ./tests") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Timeout: 60000ms") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Allow Failure: true") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Dependencies:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Environment Variables:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "NODE_ENV = test") != null);
}

test "928: template apply without template name shows usage error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create minimal config
    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{ "template", "apply" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "template name required") != null);
}

test "929: template apply without task name shows usage error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create config with a template (using section format)
    const config =
        \\[templates.test-watch]
        \\cmd = "npm test -- --watch"
        \\
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{ "template", "apply", "test-watch" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "task name required") != null);
}

test "930: template apply with non-existent template shows error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create minimal config
    const config =
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    const result = try runZr(allocator, &[_][]const u8{ "template", "apply", "nonexistent", "my-task" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "template 'nonexistent' not found") != null);
}

test "931: template apply with cancelled input returns gracefully" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create config with a template that has parameters (using section format)
    const config =
        \\[templates.test-watch]
        \\params = ["port"]
        \\cmd = "npm test -- --watch --port={{port}}"
        \\
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    // Simulate empty stdin (cancelled input)
    const result = try runZrWithStdin(allocator, tmp.dir, &[_][]const u8{ "template", "apply", "test-watch", "my-task" }, "");
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    // Should show error about unexpected end of input
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unexpected end of input") != null or
        std.mem.indexOf(u8, result.stderr, "EOF") != null or
        std.mem.indexOf(u8, result.stderr, "stdin") != null);
}

test "932: template apply creates task with parameter substitution" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create config with a template (using section format)
    const config =
        \\[templates.server]
        \\params = ["port"]
        \\cmd = "npm start -- --port={{port}}"
        \\
        \\[tasks.example]
        \\cmd = "echo test"
    ;
    const config_path = try writeTmpConfig(allocator, tmp.dir, config);
    defer allocator.free(config_path);

    // Provide parameter values and confirmation via stdin
    const stdin_input = "3000\ny\n";
    const result = try runZrWithStdin(allocator, tmp.dir, &[_][]const u8{ "template", "apply", "server", "dev-server" }, stdin_input);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Task") != null and
        std.mem.indexOf(u8, result.stdout, "dev-server") != null and
        std.mem.indexOf(u8, result.stdout, "added successfully") != null);

    // Verify the generated TOML includes template reference and params
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "template = \"server\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "params = { port = \"3000\" }") != null);

    // Verify the task was appended to zr.toml
    const content = try tmp.dir.readFileAlloc(allocator, "zr.toml", 10000);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "name = \"dev-server\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "template = \"server\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "params = { port = \"3000\" }") != null);
}
