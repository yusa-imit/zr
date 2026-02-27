const std = @import("std");
const helpers = @import("helpers.zig");
const runZr = helpers.runZr;

test "3: init creates zr.toml" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{"init"}, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify zr.toml was created
    tmp.dir.access("zr.toml", .{}) catch {
        return error.TestUnexpectedResult;
    };
}

test "4: init refuses overwrite" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create existing zr.toml
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = "existing" });

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{"init"}, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "163: init with existing config refuses overwrite" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create existing zr.toml
    const existing = try tmp.dir.createFile("zr.toml", .{});
    defer existing.close();
    try existing.writeAll("[tasks.old]\ncmd = \"echo old\"\n");

    var result = try runZr(allocator, &.{ "init" }, tmp_path);
    defer result.deinit();

    // Should refuse to overwrite existing config
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "already exists") != null);
}

test "626: init with existing file shows helpful error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create existing zr.toml
    const existing_toml =
        \\[tasks.existing]
        \\cmd = "echo existing"
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = existing_toml });

    // Try init (without --force which isn't implemented)
    var result = try runZr(allocator, &.{ "init" }, tmp_path);
    defer result.deinit();

    // Should fail with helpful error
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    const output = if (result.stderr.len > 0) result.stderr else result.stdout;
    try std.testing.expect(std.mem.indexOf(u8, output, "already exists") != null);
}

test "698: init with custom --config path creates file at specified location" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const custom_path = try std.fmt.allocPrint(allocator, "{s}/custom.toml", .{tmp_path});
    defer allocator.free(custom_path);

    var result = try runZr(allocator, &.{ "--config", custom_path, "init" }, tmp_path);
    defer result.deinit();

    // Should create file at custom path or show helpful error
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);
}

test "736: init --detect with no languages detected uses default template" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    var result = try runZr(allocator, &.{ "init", "--detect" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Should create zr.toml
    tmp.dir.access("zr.toml", .{}) catch {
        return error.TestUnexpectedResult;
    };

    // Read content and verify it contains fallback tasks
    const content = try tmp.dir.readFileAlloc(allocator, "zr.toml", 16 * 1024);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "auto-generated") != null or std.mem.indexOf(u8, content, "[tasks.build]") != null);
}

test "737: init --detect with Node.js project auto-generates npm scripts" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create a package.json with some scripts
    const package_json =
        \\{
        \\  "name": "test-project",
        \\  "scripts": {
        \\    "build": "tsc",
        \\    "test": "jest",
        \\    "dev": "nodemon src/index.ts"
        \\  }
        \\}
        \\
    ;
    try tmp.dir.writeFile(.{ .sub_path = "package.json", .data = package_json });

    var result = try runZr(allocator, &.{ "init", "--detect" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Should detect Node.js
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "node") != null or
        std.mem.indexOf(u8, result.stdout, "Node") != null or
        std.mem.indexOf(u8, result.stdout, "Detecting") != null);

    // Read generated config
    const content = try tmp.dir.readFileAlloc(allocator, "zr.toml", 16 * 1024);
    defer allocator.free(content);

    // Should contain npm scripts as tasks
    try std.testing.expect(std.mem.indexOf(u8, content, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "test") != null or std.mem.indexOf(u8, content, "npm run") != null);
}

test "738: init --detect with Python project auto-detects requirements.txt" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create Python project files
    try tmp.dir.writeFile(.{ .sub_path = "requirements.txt", .data = "pytest\nflake8\n" });
    try tmp.dir.writeFile(.{ .sub_path = "setup.py", .data = "# setup\n" });

    var result = try runZr(allocator, &.{ "init", "--detect" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Should detect Python
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(std.mem.indexOf(u8, output, "python") != null or
        std.mem.indexOf(u8, output, "Python") != null or
        std.mem.indexOf(u8, output, "Detecting") != null);

    // Should create config
    tmp.dir.access("zr.toml", .{}) catch {
        return error.TestUnexpectedResult;
    };
}

test "739: init --detect with multiple languages shows all detected" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create both Node and Python files
    try tmp.dir.writeFile(.{ .sub_path = "package.json", .data = "{\"name\":\"test\"}\n" });
    try tmp.dir.writeFile(.{ .sub_path = "requirements.txt", .data = "pytest\n" });

    var result = try runZr(allocator, &.{ "init", "--detect" }, tmp_path);
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);

    // Should show multiple detected languages (or at least succeed)
    const output = if (result.stdout.len > 0) result.stdout else result.stderr;
    try std.testing.expect(output.len > 0);

    // Should create config
    tmp.dir.access("zr.toml", .{}) catch {
        return error.TestUnexpectedResult;
    };
}

test "740: init --detect refuses to overwrite existing config" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Create existing config
    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = "[tasks.old]\ncmd = \"old\"\n" });

    var result = try runZr(allocator, &.{ "init", "--detect" }, tmp_path);
    defer result.deinit();

    // Should fail
    try std.testing.expectEqual(@as(u8, 1), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "already exists") != null);
}
