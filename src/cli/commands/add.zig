const std = @import("std");
const Config = @import("../../config.zig").Config;
const Repository = @import("../../repository.zig").Repository;
const Allocator = std.mem.Allocator;
const fs = std.fs;
const Arguments = @import("../args.zig").Arguments;

pub fn execute(config: *Config, args: *Arguments, allocator: Allocator) !void {
    const name = args.requireNext(.MissingRepository) catch {
        std.debug.print("Error: Repository name required\n", .{});
        std.debug.print("Usage: zr add <name> <path>\n", .{});
        return;
    };
    const path = args.requireNext(.MissingPath) catch {
        std.debug.print("Error: Repository path required\n", .{});
        std.debug.print("Usage: zr add <name> <path>\n", .{});
        return;
    };

    try addRepository(config, name, path, allocator);
}

fn addRepository(config: *Config, name: []const u8, path: []const u8, allocator: Allocator) !void {
    // Check if repository name already exists
    for (config.repos.items) |repo| {
        if (std.mem.eql(u8, repo.name, name)) {
            std.debug.print("Error: Repository '{s}' already exists\n", .{name});
            return;
        }
    }

    // Check if path exists
    var dir = fs.cwd().openDir(path, .{}) catch {
        std.debug.print("Error: Directory does not exist: {s}\n", .{path});
        return;
    };
    dir.close();

    const repo = try Repository.create(allocator, name, path);
    try config.repos.append(repo);

    std.debug.print("Added repository '{s}' at {s}\n", .{ name, path });
}

test "addRepository adds new repository" {
    const testing = std.testing;
    var config = Config.init(testing.allocator);
    defer config.deinit();

    // Create test directory
    try fs.cwd().makeDir("test-dir");
    defer fs.cwd().deleteDir("test-dir") catch {};

    try addRepository(&config, "test-repo", "test-dir", testing.allocator);

    try testing.expectEqual(@as(usize, 1), config.repos.items.len);
    try testing.expectEqualStrings("test-repo", config.repos.items[0].name);
    try testing.expectEqualStrings("test-dir", config.repos.items[0].path);
}
