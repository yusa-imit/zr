const std = @import("std");

/// Parse a Taskfile.yml and extract task definitions
/// Simple YAML parser for task definitions
pub fn parseToZrToml(allocator: std.mem.Allocator, taskfile_path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(taskfile_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // Max 10MB
    defer allocator.free(content);

    var buf = std.ArrayList(u8){};
    const writer = buf.writer(allocator);

    try writer.writeAll(
        \\# zr.toml — migrated from Taskfile.yml by `zr init --from-task`
        \\# Docs: https://github.com/yusa-imit/zr
        \\
        \\[global]
        \\shell = "bash"
        \\
        \\
    );

    var lines = std.mem.splitScalar(u8, content, '\n');
    var in_tasks_section = false;
    var current_task: ?[]const u8 = null;
    var current_deps = std.ArrayList([]const u8){};
    defer current_deps.deinit(allocator);
    var current_cmds = std.ArrayList([]const u8){};
    defer current_cmds.deinit(allocator);
    var current_desc: ?[]const u8 = null;
    var current_indent: usize = 0;

    while (lines.next()) |line_raw| {
        const line = std.mem.trimRight(u8, line_raw, " \t\r");

        // Skip empty lines and comments
        if (line.len == 0 or std.mem.startsWith(u8, std.mem.trim(u8, line, " \t"), "#")) continue;

        // Detect tasks: section
        if (std.mem.startsWith(u8, line, "tasks:")) {
            in_tasks_section = true;
            continue;
        }

        if (!in_tasks_section) continue;

        // Count leading spaces to determine indent level
        const indent = countLeadingSpaces(line);
        const trimmed = std.mem.trim(u8, line, " \t");

        // Task name (2 spaces indent)
        if (indent == 2 and std.mem.endsWith(u8, trimmed, ":")) {
            // Save previous task
            if (current_task) |task| {
                try writeTask(allocator, &writer, task, current_deps.items, current_cmds.items, current_desc);
                allocator.free(task);
                for (current_deps.items) |dep| allocator.free(dep);
                current_deps.clearRetainingCapacity();
                for (current_cmds.items) |cmd| allocator.free(cmd);
                current_cmds.clearRetainingCapacity();
                if (current_desc) |desc| allocator.free(desc);
                current_desc = null;
            }

            const task_name = std.mem.trim(u8, trimmed[0 .. trimmed.len - 1], " \t");
            current_task = try allocator.dupe(u8, task_name);
            current_indent = indent;
            continue;
        }

        if (current_task == null) continue;

        // Task properties (4+ spaces indent)
        if (indent > current_indent) {
            if (std.mem.startsWith(u8, trimmed, "desc:")) {
                const desc = std.mem.trim(u8, trimmed[5..], " \t\"'");
                current_desc = try allocator.dupe(u8, desc);
            } else if (std.mem.startsWith(u8, trimmed, "cmds:")) {
                // cmds array follows
                continue;
            } else if (std.mem.startsWith(u8, trimmed, "deps:")) {
                // deps array follows
                continue;
            } else if (std.mem.startsWith(u8, trimmed, "- ")) {
                // Array item (cmd or dep)
                const item = std.mem.trim(u8, trimmed[2..], " \t\"'");
                // Heuristic: if it contains spaces or shell operators, it's a command
                if (std.mem.indexOf(u8, item, " ") != null or
                    std.mem.indexOf(u8, item, "&&") != null or
                    std.mem.indexOf(u8, item, "|") != null)
                {
                    try current_cmds.append(allocator, try allocator.dupe(u8, item));
                } else {
                    // Otherwise it's a dependency
                    try current_deps.append(allocator, try allocator.dupe(u8, item));
                }
            } else if (std.mem.startsWith(u8, trimmed, "cmd:")) {
                // Single command
                const cmd = std.mem.trim(u8, trimmed[4..], " \t\"'");
                try current_cmds.append(allocator, try allocator.dupe(u8, cmd));
            }
        }
    }

    // Write last task
    if (current_task) |task| {
        try writeTask(allocator, &writer, task, current_deps.items, current_cmds.items, current_desc);
        allocator.free(task);
        for (current_deps.items) |dep| allocator.free(dep);
        for (current_cmds.items) |cmd| allocator.free(cmd);
        if (current_desc) |desc| allocator.free(desc);
    }

    return try buf.toOwnedSlice(allocator);
}

fn countLeadingSpaces(s: []const u8) usize {
    var count: usize = 0;
    for (s) |c| {
        if (c == ' ') {
            count += 1;
        } else {
            break;
        }
    }
    return count;
}

fn writeTask(
    allocator: std.mem.Allocator,
    writer: anytype,
    task: []const u8,
    deps: []const []const u8,
    cmds: []const []const u8,
    desc: ?[]const u8,
) !void {
    try writer.print("[tasks.{s}]\n", .{task});

    if (desc) |d| {
        const escaped = try escapeString(allocator, d);
        defer allocator.free(escaped);
        try writer.print("description = \"{s}\"\n", .{escaped});
    }

    if (deps.len > 0) {
        try writer.writeAll("deps = [");
        for (deps, 0..) |dep, idx| {
            if (idx > 0) try writer.writeAll(", ");
            try writer.print("\"{s}\"", .{dep});
        }
        try writer.writeAll("]\n");
    }

    if (cmds.len > 0) {
        if (cmds.len == 1) {
            const escaped = try escapeString(allocator, cmds[0]);
            defer allocator.free(escaped);
            try writer.print("cmd = \"{s}\"\n", .{escaped});
        } else {
            // Multiple commands: join with &&
            var joined = std.ArrayList(u8){};
            defer joined.deinit(allocator);
            const j_writer = joined.writer(allocator);
            for (cmds, 0..) |cmd, idx| {
                if (idx > 0) try j_writer.writeAll(" && ");
                try j_writer.writeAll(cmd);
            }
            const escaped = try escapeString(allocator, joined.items);
            defer allocator.free(escaped);
            try writer.print("cmd = \"{s}\"\n", .{escaped});
        }
    } else {
        try writer.writeAll("cmd = \"true\"\n");
    }

    try writer.writeAll("\n");
}

fn escapeString(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8){};
    const writer = buf.writer(allocator);
    for (s) |c| {
        if (c == '"') {
            try writer.writeAll("\\\"");
        } else if (c == '\\') {
            try writer.writeAll("\\\\");
        } else {
            try writer.writeByte(c);
        }
    }
    return try buf.toOwnedSlice(allocator);
}

test "parseToZrToml handles simple Taskfile.yml" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const taskfile_content =
        \\version: '3'
        \\
        \\tasks:
        \\  build:
        \\    desc: Build the project
        \\    deps:
        \\      - install
        \\    cmds:
        \\      - npm run build
        \\
        \\  test:
        \\    desc: Run tests
        \\    deps:
        \\      - build
        \\    cmds:
        \\      - npm test
        \\
        \\  clean:
        \\    desc: Clean build artifacts
        \\    cmd: rm -rf dist/
        \\
    ;

    try tmp.dir.writeFile(.{
        .sub_path = "Taskfile.yml",
        .data = taskfile_content,
    });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const taskfile_path = try tmp.dir.realpath("Taskfile.yml", &path_buf);

    const result = try parseToZrToml(std.testing.allocator, taskfile_path);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.build]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.test]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.clean]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Build the project") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "deps = [\"install\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "npm run build") != null);
}
