const std = @import("std");
const Config = @import("../../config.zig").Config;
const Repository = @import("../../repository.zig").Repository;
const Arguments = @import("../args.zig").Arguments;

pub fn execute(config: *Config, args: *Arguments) !void {
    const name = args.requireNext(.MissingRepository) catch {
        std.debug.print("Error: Repository name required\n", .{});
        std.debug.print("Usage: zr remove <name>\n", .{});
        return;
    };

    try removeRepository(config, name);
}

fn removeRepository(config: *Config, name: []const u8) !void {
    for (config.repos.items, 0..) |repo, i| {
        if (std.mem.eql(u8, repo.name, name)) {
            repo.deinit(config.allocator);
            _ = config.repos.orderedRemove(i);
            std.debug.print("Removed repository '{s}'\n", .{name});
            return;
        }
    }
    std.debug.print("Error: Repository '{s}' not found\n", .{name});
}

test "removeRepository removes existing repository" {
    const testing = std.testing;
    var config = Config.init(testing.allocator);
    defer config.deinit();

    const repo = try Repository.create(testing.allocator, "test-repo", "test-path");
    try config.repos.append(repo);

    try removeRepository(&config, "test-repo");
    try testing.expectEqual(@as(usize, 0), config.repos.items.len);
}
