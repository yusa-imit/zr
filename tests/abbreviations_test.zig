const std = @import("std");
const helpers = @import("helpers.zig");

test "abbreviation: simple expansion (zr b -> zr run build)" {
    const allocator = std.testing.allocator;

    // Create a temporary directory for test workspace
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create zr.toml with a build task
    const zr_config =
        \\[tasks.build]
        \\cmd = "echo 'Building...'"
    ;
    const zr_file = try tmp_dir.dir.createFile("zr.toml", .{});
    defer zr_file.close();
    try zr_file.writeAll(zr_config);

    // Create ~/.zrconfig with abbreviations
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ home, ".zrconfig" });
    defer allocator.free(config_path);

    // Backup existing config if it exists
    const backup_path = try std.mem.concat(allocator, u8, &[_][]const u8{ config_path, ".backup" });
    defer allocator.free(backup_path);

    var backed_up = false;
    std.fs.renameAbsolute(config_path, backup_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };
    if (std.fs.openFileAbsolute(backup_path, .{})) |_| {
        backed_up = true;
    } else |_| {}

    defer {
        if (backed_up) {
            std.fs.renameAbsolute(backup_path, config_path) catch {};
        } else {
            std.fs.deleteFileAbsolute(config_path) catch {};
        }
    }

    // Write test config
    const config_content =
        \\[alias]
        \\b = "run build"
        \\t = "run test"
    ;
    const config_file = try std.fs.createFileAbsolute(config_path, .{});
    defer config_file.close();
    try config_file.writeAll(config_content);

    // Get absolute path to temp directory
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run `zr b` and verify it expands to `zr run build`
    const result = try helpers.runZr(allocator, &[_][]const u8{"b"}, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Should succeed and output the build message
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Building...") != null);
}

test "abbreviation: flag pass-through (zr b --verbose)" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const zr_config =
        \\[tasks.build]
        \\cmd = "echo 'Building with verbose'"
    ;
    const zr_file = try tmp_dir.dir.createFile("zr.toml", .{});
    defer zr_file.close();
    try zr_file.writeAll(zr_config);

    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ home, ".zrconfig" });
    defer allocator.free(config_path);

    const backup_path = try std.mem.concat(allocator, u8, &[_][]const u8{ config_path, ".backup" });
    defer allocator.free(backup_path);

    var backed_up = false;
    std.fs.renameAbsolute(config_path, backup_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };
    if (std.fs.openFileAbsolute(backup_path, .{})) |_| {
        backed_up = true;
    } else |_| {}

    defer {
        if (backed_up) {
            std.fs.renameAbsolute(backup_path, config_path) catch {};
        } else {
            std.fs.deleteFileAbsolute(config_path) catch {};
        }
    }

    const config_content =
        \\[alias]
        \\b = "run build"
    ;
    const config_file = try std.fs.createFileAbsolute(config_path, .{});
    defer config_file.close();
    try config_file.writeAll(config_content);

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run `zr b --verbose` and verify --verbose flag is parsed correctly
    const result = try helpers.runZr(allocator, &[_][]const u8{ "b", "--verbose" }, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "[verbose mode]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Building with verbose") != null);
}

test "abbreviation: unknown abbreviation error" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const zr_config =
        \\[tasks.build]
        \\cmd = "echo 'Building...'"
    ;
    const zr_file = try tmp_dir.dir.createFile("zr.toml", .{});
    defer zr_file.close();
    try zr_file.writeAll(zr_config);

    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ home, ".zrconfig" });
    defer allocator.free(config_path);

    const backup_path = try std.mem.concat(allocator, u8, &[_][]const u8{ config_path, ".backup" });
    defer allocator.free(backup_path);

    var backed_up = false;
    std.fs.renameAbsolute(config_path, backup_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };
    if (std.fs.openFileAbsolute(backup_path, .{})) |_| {
        backed_up = true;
    } else |_| {}

    defer {
        if (backed_up) {
            std.fs.renameAbsolute(backup_path, config_path) catch {};
        } else {
            std.fs.deleteFileAbsolute(config_path) catch {};
        }
    }

    const config_content =
        \\[alias]
        \\b = "run build"
    ;
    const config_file = try std.fs.createFileAbsolute(config_path, .{});
    defer config_file.close();
    try config_file.writeAll(config_content);

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run `zr xyz` (unknown abbreviation)
    const result = try helpers.runZr(allocator, &[_][]const u8{"xyz"}, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Should fail with error
    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Unknown command") != null or
        std.mem.indexOf(u8, result.stderr, "unknown") != null);
}

test "abbreviation: builtin command takes precedence" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const zr_config =
        \\[tasks.build]
        \\cmd = "echo 'Building...'"
    ;
    const zr_file = try tmp_dir.dir.createFile("zr.toml", .{});
    defer zr_file.close();
    try zr_file.writeAll(zr_config);

    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ home, ".zrconfig" });
    defer allocator.free(config_path);

    const backup_path = try std.mem.concat(allocator, u8, &[_][]const u8{ config_path, ".backup" });
    defer allocator.free(backup_path);

    var backed_up = false;
    std.fs.renameAbsolute(config_path, backup_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };
    if (std.fs.openFileAbsolute(backup_path, .{})) |_| {
        backed_up = true;
    } else |_| {}

    defer {
        if (backed_up) {
            std.fs.renameAbsolute(backup_path, config_path) catch {};
        } else {
            std.fs.deleteFileAbsolute(config_path) catch {};
        }
    }

    // Create abbreviation that conflicts with builtin command 'list'
    const config_content =
        \\[alias]
        \\list = "run build"
    ;
    const config_file = try std.fs.createFileAbsolute(config_path, .{});
    defer config_file.close();
    try config_file.writeAll(config_content);

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run `zr list` - should invoke builtin list command, not abbreviation
    const result = try helpers.runZr(allocator, &[_][]const u8{"list"}, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Should succeed and show task list (builtin behavior), not run build
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should NOT see "Building..." from the build task
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Building...") == null);
    // Should see task list output
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "build") != null or
        std.mem.indexOf(u8, result.stdout, "Tasks") != null);
}

test "abbreviation: no config file" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const zr_config =
        \\[tasks.build]
        \\cmd = "echo 'Building...'"
    ;
    const zr_file = try tmp_dir.dir.createFile("zr.toml", .{});
    defer zr_file.close();
    try zr_file.writeAll(zr_config);

    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ home, ".zrconfig" });
    defer allocator.free(config_path);

    // Ensure config does NOT exist
    std.fs.deleteFileAbsolute(config_path) catch {};

    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // Run `zr b` - should fail because no abbreviations defined
    const result = try helpers.runZr(allocator, &[_][]const u8{"b"}, tmp_path);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Should fail with unknown command error
    try std.testing.expect(result.exit_code != 0);
}
