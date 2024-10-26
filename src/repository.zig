const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Repository = struct {
    name: []const u8,
    path: []const u8,

    pub fn create(allocator: Allocator, name: []const u8, path: []const u8) !Repository {
        return Repository{
            .name = try allocator.dupe(u8, name),
            .path = try allocator.dupe(u8, path),
        };
    }

    pub fn deinit(self: Repository, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.path);
    }
};
