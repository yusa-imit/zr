const std = @import("std");
const Repository = @import("repository.zig").Repository;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const fs = std.fs;

pub const ConfigError = error{
    ConfigNotInitialized,
} || std.fs.File.OpenError || std.fs.File.ReadError || std.mem.Allocator.Error;

pub const CONFIG_FILENAME = ".zr.config.yaml";

pub const Config = struct {
    repos: ArrayList(Repository),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Config {
        return .{
            .repos = ArrayList(Repository).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Config) void {
        for (self.repos.items) |repo| {
            repo.deinit(self.allocator);
        }
        self.repos.deinit();
    }

    pub fn load(allocator: Allocator) !Config {
        var config = Config.init(allocator);
        errdefer config.deinit();

        const content = readFile(allocator, CONFIG_FILENAME) catch |err| {
            if (err == error.FileNotFound) {
                return error.ConfigNotInitialized;
            }
            return err;
        };
        defer allocator.free(content);

        try parseConfig(&config, content);

        return config;
    }

    pub fn save(self: *const Config) !void {
        var buffer = ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        try self.writeConfig(&buffer);

        const file = try fs.cwd().createFile(CONFIG_FILENAME, .{});
        defer file.close();
        try file.writeAll(buffer.items);
    }

    fn parseConfig(config: *Config, content: []const u8) !void {
        var lines = std.mem.split(u8, content, "\n");
        var in_repositories = false;

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            if (std.mem.eql(u8, trimmed, "repositories:")) {
                in_repositories = true;
                continue;
            }

            if (in_repositories) {
                // Check if this is a new repository entry
                if (std.mem.startsWith(u8, trimmed, "- name:")) {
                    const name = std.mem.trim(u8, trimmed["- name:".len..], " ");

                    // Get the next line for path
                    if (lines.next()) |path_line| {
                        const path_trimmed = std.mem.trim(u8, path_line, " \t\r");
                        if (std.mem.startsWith(u8, path_trimmed, "path:")) {
                            const path = std.mem.trim(u8, path_trimmed["path:".len..], " ");

                            // Create and add the repository
                            try config.repos.append(try Repository.create(config.allocator, name, path));
                        }
                    }
                }
            }
        }
    }

    fn parseLine(config: *Config, lines: *std.mem.SplitIterator(u8, .sequence), line: []const u8, in_repositories: bool) !void {
        if (in_repositories and std.mem.startsWith(u8, line, "  ")) {
            if (std.mem.indexOf(u8, line, "name:")) |_| {
                const name = std.mem.trim(u8, line["name:".len + 2 ..], " ");
                if (lines.next()) |path_line| {
                    const path_trimmed = std.mem.trim(u8, path_line, " \t\r");
                    if (std.mem.indexOf(u8, path_trimmed, "path:")) |_| {
                        const path = std.mem.trim(u8, path_trimmed["path:".len + 2 ..], " ");
                        try config.repos.append(try Repository.create(config.allocator, name, path));
                    }
                }
            }
        }
    }

    fn writeConfig(self: *const Config, buffer: *ArrayList(u8)) !void {
        const writer = buffer.writer();
        try writer.writeAll("# zr configuration file\n");
        try writer.writeAll("repositories:\n");

        for (self.repos.items) |repo| {
            try writer.print("  - name: {s}\n", .{repo.name});
            try writer.print("    path: {s}\n", .{repo.path});
        }
    }
};

fn readFile(allocator: Allocator, path: []const u8) ![]const u8 {
    const file = try fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, std.math.maxInt(usize));
}
