const std = @import("std");
const Repository = @import("../../repository.zig").Repository;
const Config = @import("../../config.zig").Config;
const ArrayList = std.ArrayList;
const ChildProcess = std.process.Child;
const Allocator = std.mem.Allocator;

pub fn execute(config: *Config, args: *std.process.ArgIterator, allocator: Allocator) !void {
    const repo_name = args.next() orelse {
        std.debug.print("Error: Repository name required\n", .{});
        std.debug.print("Usage: zr run <repo> <command>\n", .{});
        return;
    };

    const repo = findRepository(config, repo_name) orelse {
        std.debug.print("Error: Repository not found: {s}\n", .{repo_name});
        return;
    };

    try runCommand(repo, args, allocator);
}

fn findRepository(config: *Config, name: []const u8) ?Repository {
    for (config.repos.items) |repo| {
        if (std.mem.eql(u8, repo.name, name)) {
            return repo;
        }
    }
    return null;
}

fn runCommand(repo: Repository, args: *std.process.ArgIterator, allocator: Allocator) !void {
    var cmd_args = ArrayList([]const u8).init(allocator);
    defer cmd_args.deinit();

    while (args.next()) |arg| {
        try cmd_args.append(arg);
    }

    if (cmd_args.items.len == 0) {
        std.debug.print("Error: Command required\n", .{});
        std.debug.print("Usage: zr run <repo> <command>\n", .{});
        return;
    }

    try executeChildProcess(repo, &cmd_args, allocator);
}

fn executeChildProcess(repo: Repository, cmd_args: *ArrayList([]const u8), allocator: Allocator) !void {
    std.debug.print("Running '{s}' in {s}...\n", .{
        std.mem.join(allocator, " ", cmd_args.items) catch "",
        repo.name,
    });

    var child = ChildProcess.init(cmd_args.items, allocator);
    child.cwd = repo.path;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();
    try handleChildOutput(&child);

    const term = try child.wait();
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("\nCommand exited with code: {d}\n", .{code});
            }
        },
        else => std.debug.print("\nCommand terminated abnormally\n", .{}),
    }
}

fn handleChildOutput(child: *ChildProcess) !void {
    var buffer: [1024]u8 = undefined;

    while (true) {
        const bytes_read = try child.stdout.?.reader().read(&buffer);
        if (bytes_read == 0) break;
        try std.io.getStdOut().writer().writeAll(buffer[0..bytes_read]);
    }

    while (true) {
        const bytes_read = try child.stderr.?.reader().read(&buffer);
        if (bytes_read == 0) break;
        try std.io.getStdErr().writer().writeAll(buffer[0..bytes_read]);
    }
}
