const std = @import("std");
const Config = @import("../../config.zig").Config;
const Repository = @import("../../repository.zig").Repository;

pub fn execute(config: *Config) !void {
    if (config.repos.items.len == 0) {
        std.debug.print("No repositories added yet\n", .{});
        std.debug.print("\nUse 'zr add <name> <path>' to add a repository\n", .{});
        return;
    }

    std.debug.print("Repositories:\n", .{});
    for (config.repos.items) |repo| {
        std.debug.print("  {s: <15} {s}\n", .{ repo.name, repo.path });
    }
}

test "list repositories" {
    const testing = std.testing;
    var config = Config.init(testing.allocator);
    defer config.deinit();

    // Test empty list
    try execute(&config);

    // Add test repository
    const repo = try Repository.create(testing.allocator, "test-repo", "test-path");
    try config.repos.append(repo);

    // Test non-empty list
    try execute(&config);
}
