const std = @import("std");
const fs = std.fs;
const testing = std.testing;
const process = std.process;
const print = std.debug.print;
const ArrayList = std.ArrayList;
const ChildProcess = std.process.Child;
const Allocator = std.mem.Allocator;

const Command = enum {
    run, // Run command in repository: zr run <repo> <command>
    list, // List repositories: zr list
    add, // Add repository: zr add <name> <path>
    remove, // Remove repository: zr remove <name>
    init, // Initialize config file: zr init
    help, // Show help: zr help
};

const Repository = struct {
    name: []const u8,
    path: []const u8,
};

const CONFIG_FILENAME = ".zr.config.yaml";

fn readFile(allocator: Allocator, path: []const u8) ![]const u8 {
    const file = try fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

fn writeFile(path: []const u8, content: []const u8) !void {
    const file = try fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(content);
}

fn loadConfig(allocator: Allocator) !ArrayList(Repository) {
    var repos = ArrayList(Repository).init(allocator);

    const content = readFile(allocator, CONFIG_FILENAME) catch |err| switch (err) {
        error.FileNotFound => {
            print("No config file found. Use 'zr init' to create one.\n", .{});
            return repos;
        },
        else => return err,
    };
    defer allocator.free(content);

    var lines = std.mem.split(u8, content, "\n");
    var in_repositories = false;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        if (std.mem.eql(u8, trimmed, "repositories:")) {
            in_repositories = true;
            continue;
        }

        if (in_repositories and std.mem.startsWith(u8, trimmed, "  ")) {
            if (std.mem.indexOf(u8, trimmed, "name:")) |_| {
                const name = std.mem.trim(u8, trimmed["name:".len + 2 ..], " ");
                if (lines.next()) |path_line| {
                    const path_trimmed = std.mem.trim(u8, path_line, " \t\r");
                    if (std.mem.indexOf(u8, path_trimmed, "path:")) |_| {
                        const path = std.mem.trim(u8, path_trimmed["path:".len + 2 ..], " ");
                        try repos.append(Repository{
                            .name = try allocator.dupe(u8, name),
                            .path = try allocator.dupe(u8, path),
                        });
                    }
                }
            }
        }
    }

    return repos;
}

fn saveConfig(repos: ArrayList(Repository)) !void {
    var buffer = ArrayList(u8).init(repos.allocator);
    defer buffer.deinit();

    const writer = buffer.writer();
    try writer.writeAll("# zr configuration file\n");
    try writer.writeAll("repositories:\n");

    for (repos.items) |repo| {
        try writer.print("  - name: {s}\n", .{repo.name});
        try writer.print("    path: {s}\n", .{repo.path});
    }

    try writeFile(CONFIG_FILENAME, buffer.items);
}

fn initConfig() !void {
    const default_config =
        \\# zr configuration file
        \\repositories:
        \\  # Add your repositories here:
        \\  # - name: frontend
        \\  #   path: ./packages/frontend
        \\  # - name: backend
        \\  #   path: ./packages/backend
        \\
    ;

    if (fs.cwd().access(CONFIG_FILENAME, .{})) |_| {
        print("Config file already exists at ./{s}\n", .{CONFIG_FILENAME});
        return;
    } else |_| {
        try writeFile(CONFIG_FILENAME, default_config);
        print("Created config file at ./{s}\n", .{CONFIG_FILENAME});
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Get command line arguments
    var args = try process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip executable name
    _ = args.skip();

    // Parse command
    const cmd_str = args.next() orelse {
        try showHelp();
        return;
    };

    const cmd = parseCommand(cmd_str) orelse {
        print("Unknown command: {s}\n", .{cmd_str});
        try showHelp();
        return;
    };

    // Handle init command separately as it doesn't need config
    if (cmd == .init) {
        try initConfig();
        return;
    }

    // Load repositories from config
    var repos = try loadConfig(allocator);
    defer {
        for (repos.items) |repo| {
            allocator.free(repo.name);
            allocator.free(repo.path);
        }
        repos.deinit();
    }

    try executeCommand(cmd, &repos, &args, allocator);

    // Save config if needed
    if (cmd == .add or cmd == .remove) {
        try saveConfig(repos);
    }
}

fn parseCommand(cmd: []const u8) ?Command {
    inline for (@typeInfo(Command).Enum.fields) |field| {
        if (std.mem.eql(u8, cmd, field.name)) {
            return @enumFromInt(field.value);
        }
    }
    return null;
}

fn executeCommand(cmd: Command, repos: *ArrayList(Repository), args: *process.ArgIterator, allocator: Allocator) !void {
    switch (cmd) {
        .run => try runCommand(repos, args, allocator),
        .list => try listRepos(repos),
        .add => try addRepo(repos, args, allocator),
        .remove => try removeRepo(repos, args),
        .init => unreachable, // Handled in main
        .help => try showHelp(),
    }
}

fn runCommand(repos: *ArrayList(Repository), args: *process.ArgIterator, allocator: std.mem.Allocator) !void {
    const repo_name = args.next() orelse {
        print("Error: Repository name required\n", .{});
        print("Usage: zr run <repo> <command>\n", .{});
        return;
    };

    // Find the repository
    const repo = for (repos.items) |r| {
        if (std.mem.eql(u8, r.name, repo_name)) break r;
    } else {
        print("Error: Repository not found: {s}\n", .{repo_name});
        return;
    };

    // Collect the command and its arguments
    var cmd_args = ArrayList([]const u8).init(allocator);
    defer cmd_args.deinit();

    while (args.next()) |arg| {
        try cmd_args.append(arg);
    }

    if (cmd_args.items.len == 0) {
        print("Error: Command required\n", .{});
        print("Usage: zr run <repo> <command>\n", .{});
        return;
    }

    print("Running '{s}' in {s}...\n", .{ std.mem.join(allocator, " ", cmd_args.items) catch "", repo.name });

    // Create child process
    var child = ChildProcess.init(cmd_args.items, allocator);
    child.cwd = repo.path;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Read and print output in real-time
    const stdout = child.stdout.?.reader();
    const stderr = child.stderr.?.reader();

    var buffer: [1024]u8 = undefined;
    while (true) {
        const bytes_read = try stdout.read(&buffer);
        if (bytes_read == 0) break;
        try std.io.getStdOut().writer().writeAll(buffer[0..bytes_read]);
    }

    while (true) {
        const bytes_read = try stderr.read(&buffer);
        if (bytes_read == 0) break;
        try std.io.getStdErr().writer().writeAll(buffer[0..bytes_read]);
    }

    const term = try child.wait();
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                print("\nCommand exited with code: {d}\n", .{code});
            }
        },
        else => print("\nCommand terminated abnormally\n", .{}),
    }
}

fn listRepos(repos: *ArrayList(Repository)) !void {
    if (repos.items.len == 0) {
        print("No repositories added yet\n", .{});
        print("\nUse 'zr add <name> <path>' to add a repository\n", .{});
        return;
    }

    print("Repositories:\n", .{});
    for (repos.items) |repo| {
        print("  {s: <15} {s}\n", .{ repo.name, repo.path });
    }
}

fn addRepo(repos: *ArrayList(Repository), args: *process.ArgIterator, allocator: std.mem.Allocator) !void {
    const name = args.next() orelse {
        print("Error: Repository name required\n", .{});
        print("Usage: zr add <name> <path>\n", .{});
        return;
    };
    const path = args.next() orelse {
        print("Error: Repository path required\n", .{});
        print("Usage: zr add <name> <path>\n", .{});
        return;
    };

    // Check if repository name already exists
    for (repos.items) |repo| {
        if (std.mem.eql(u8, repo.name, name)) {
            print("Error: Repository '{s}' already exists\n", .{name});
            return;
        }
    }

    // Check if path exists
    var dir = fs.cwd().openDir(path, .{}) catch {
        print("Error: Directory does not exist: {s}\n", .{path});
        return;
    };
    dir.close();

    const name_owned = try allocator.dupe(u8, name);
    const path_owned = try allocator.dupe(u8, path);

    try repos.append(Repository{
        .name = name_owned,
        .path = path_owned,
    });
    print("Added repository '{s}' at {s}\n", .{ name, path });
}

fn removeRepo(repos: *ArrayList(Repository), args: *process.ArgIterator) !void {
    const name = args.next() orelse {
        print("Error: Repository name required\n", .{});
        print("Usage: zr remove <name>\n", .{});
        return;
    };

    for (repos.items, 0..) |repo, i| {
        if (std.mem.eql(u8, repo.name, name)) {
            _ = repos.orderedRemove(i);
            print("Removed repository '{s}'\n", .{name});
            return;
        }
    }
    print("Error: Repository '{s}' not found\n", .{name});
}

fn showHelp() !void {
    print(
        \\zr - Zig-based Repository Runner
        \\
        \\Usage:
        \\  zr <command> [arguments]
        \\
        \\Commands:
        \\  init                  Create initial config file
        \\  run <repo> <command>  Run command in specified repository
        \\  list                  List all repositories
        \\  add <name> <path>     Add a new repository
        \\  remove <name>         Remove a repository
        \\  help                  Show this help message
        \\
        \\Config:
        \\  Repositories can be managed through ./{s}
        \\
        \\Examples:
        \\  zr init
        \\  zr add frontend ./packages/frontend
        \\  zr run frontend npm start
        \\
    , .{CONFIG_FILENAME});
}

fn setupTestConfig(allocator: std.mem.Allocator) !void {
    _ = allocator; // autofix
    const test_config =
        \\# zr configuration file
        \\repositories:
        \\  - name: test-repo
        \\    path: ./test-path
        \\
    ;
    try fs.cwd().writeFile(".zr.config.yaml", test_config);
}

fn cleanupTestConfig() void {
    fs.cwd().deleteFile(".zr.config.yaml") catch {};
}

test "parseCommand returns correct commands" {
    try testing.expectEqual(Command.run, parseCommand("run").?);
    try testing.expectEqual(Command.list, parseCommand("list").?);
    try testing.expectEqual(Command.add, parseCommand("add").?);
    try testing.expectEqual(Command.remove, parseCommand("remove").?);
    try testing.expectEqual(Command.init, parseCommand("init").?);
    try testing.expectEqual(Command.help, parseCommand("help").?);
    try testing.expect(parseCommand("invalid") == null);
}

test "loadConfig loads repositories correctly" {
    var allocator = testing.allocator;

    // Setup
    try setupTestConfig(allocator);
    defer cleanupTestConfig();

    // Test
    var repos = try loadConfig(allocator);
    defer {
        for (repos.items) |repo| {
            allocator.free(repo.name);
            allocator.free(repo.path);
        }
        repos.deinit();
    }

    try testing.expectEqual(@as(usize, 1), repos.items.len);
    try testing.expectEqualStrings("test-repo", repos.items[0].name);
    try testing.expectEqualStrings("./test-path", repos.items[0].path);
}

test "addRepo adds repository correctly" {
    var allocator = testing.allocator;

    // Setup
    try fs.cwd().makePath("./test-dir");
    defer fs.cwd().deleteTree("./test-dir") catch {};

    var repos = ArrayList(Repository).init(allocator);
    defer {
        for (repos.items) |repo| {
            allocator.free(repo.name);
            allocator.free(repo.path);
        }
        repos.deinit();
    }

    // Create mock args
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();
    try args.append("test-repo");
    try args.append("./test-dir");

    var arg_iter = std.process.ArgIterator{
        .args = args.items,
        .index = 0,
    };

    // Test
    try addRepo(&repos, &arg_iter, allocator);

    try testing.expectEqual(@as(usize, 1), repos.items.len);
    try testing.expectEqualStrings("test-repo", repos.items[0].name);
    try testing.expectEqualStrings("./test-dir", repos.items[0].path);
}

test "removeRepo removes repository correctly" {
    var allocator = testing.allocator;

    var repos = ArrayList(Repository).init(allocator);
    defer {
        for (repos.items) |repo| {
            allocator.free(repo.name);
            allocator.free(repo.path);
        }
        repos.deinit();
    }

    // Add test repository
    const name = try allocator.dupe(u8, "test-repo");
    const path = try allocator.dupe(u8, "./test-path");
    try repos.append(Repository{ .name = name, .path = path });

    // Create mock args
    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();
    try args.append("test-repo");

    var arg_iter = std.process.ArgIterator{
        .args = args.items,
        .index = 0,
    };

    // Test
    try removeRepo(&repos, &arg_iter);
    try testing.expectEqual(@as(usize, 0), repos.items.len);
}

test "saveConfig saves repositories correctly" {
    var allocator = testing.allocator;

    var repos = ArrayList(Repository).init(allocator);
    defer {
        for (repos.items) |repo| {
            allocator.free(repo.name);
            allocator.free(repo.path);
        }
        repos.deinit();
    }

    // Add test repository
    const name = try allocator.dupe(u8, "test-repo");
    const path = try allocator.dupe(u8, "./test-path");
    try repos.append(Repository{ .name = name, .path = path });

    // Test
    try saveConfig(repos);
    defer cleanupTestConfig();

    // Verify saved content
    const content = try fs.cwd().readFileAlloc(allocator, ".zr.config.yaml", std.math.maxInt(usize));
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "test-repo") != null);
    try testing.expect(std.mem.indexOf(u8, content, "./test-path") != null);
}

test "initConfig creates config file correctly" {
    // Clean up any existing config
    cleanupTestConfig();

    // Test
    try initConfig();
    defer cleanupTestConfig();

    // Verify file exists
    const file = try fs.cwd().openFile(".zr.config.yaml", .{});
    defer file.close();

    // Verify content
    var buffer: [1024]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);
    const content = buffer[0..bytes_read];

    try testing.expect(std.mem.indexOf(u8, content, "# zr configuration file") != null);
    try testing.expect(std.mem.indexOf(u8, content, "repositories:") != null);
}
