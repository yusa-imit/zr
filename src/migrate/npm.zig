const std = @import("std");

/// Parse a package.json and extract scripts section
/// Handles common npm patterns:
/// - Simple scripts: "build": "tsc"
/// - Parallel patterns: "dev": "npm-run-all --parallel watch:*"
/// - Sequential patterns: "test": "eslint . && jest"
/// - Pre/post hooks: "prebuild", "postbuild"
pub fn parseToZrToml(allocator: std.mem.Allocator, package_json_path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(package_json_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // Max 10MB
    defer allocator.free(content);

    // Parse JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return error.InvalidPackageJson;

    const scripts_obj = root.object.get("scripts") orelse {
        // No scripts section - return minimal template
        return try allocator.dupe(u8,
            \\# zr.toml — migrated from package.json by `zr init --from-npm`
            \\# Docs: https://github.com/yusa-imit/zr
            \\
            \\[global]
            \\shell = "bash"
            \\
            \\# No scripts found in package.json
            \\
        );
    };

    if (scripts_obj != .object) return error.InvalidScripts;

    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writer.writeAll(
        \\# zr.toml — migrated from package.json by `zr init --from-npm`
        \\# Docs: https://github.com/yusa-imit/zr
        \\
        \\[global]
        \\shell = "bash"
        \\
        \\
    );

    // Collect scripts and analyze dependencies
    var scripts = std.StringArrayHashMap(Script).init(allocator);
    defer {
        var it = scripts.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.*.command);
            for (entry.value_ptr.*.deps.items) |dep| {
                allocator.free(dep);
            }
            entry.value_ptr.*.deps.deinit(allocator);
        }
        scripts.deinit();
    }

    var scripts_it = scripts_obj.object.iterator();
    while (scripts_it.next()) |entry| {
        const name = entry.key_ptr.*;
        const cmd_value = entry.value_ptr.*;

        if (cmd_value != .string) continue;
        const command = cmd_value.string;

        // Skip pre/post hooks - they'll be handled as dependencies
        if (std.mem.startsWith(u8, name, "pre") or std.mem.startsWith(u8, name, "post")) {
            continue;
        }

        var script = Script{
            .command = try allocator.dupe(u8, command),
            .deps = std.ArrayList([]const u8){},
        };

        // Detect dependencies from command patterns
        try analyzeCommandDeps(allocator, &script, command);

        try scripts.put(name, script);
    }

    // Add pre/post hooks as dependencies
    scripts_it = scripts_obj.object.iterator();
    while (scripts_it.next()) |entry| {
        const hook_name = entry.key_ptr.*;

        if (std.mem.startsWith(u8, hook_name, "pre")) {
            const main_name = hook_name[3..]; // Skip "pre"
            if (scripts.getPtr(main_name)) |main_script| {
                // Insert at beginning (pre hooks run before)
                try main_script.deps.insert(allocator, 0, try allocator.dupe(u8, hook_name));
            }

            // Add the hook as a task too
            if (scripts.get(hook_name) == null) {
                const cmd_value = entry.value_ptr.*;
                if (cmd_value == .string) {
                    const hook_script = Script{
                        .command = try allocator.dupe(u8, cmd_value.string),
                        .deps = std.ArrayList([]const u8){},
                    };
                    try scripts.put(hook_name, hook_script);
                }
            }
        } else if (std.mem.startsWith(u8, hook_name, "post")) {
            const main_name = hook_name[4..]; // Skip "post"
            if (scripts.getPtr(main_name)) |_| {
                // Postscripts should be separate tasks that depend on main
                // We'll handle them by creating a wrapper task
                // For now, skip adding as direct dependency
            }

            // Add the hook as a task
            if (scripts.get(hook_name) == null) {
                const cmd_value = entry.value_ptr.*;
                if (cmd_value == .string) {
                    var post_hook_script = Script{
                        .command = try allocator.dupe(u8, cmd_value.string),
                        .deps = std.ArrayList([]const u8){},
                    };
                    // Post hooks depend on the main task
                    try post_hook_script.deps.append(allocator, try allocator.dupe(u8, main_name));
                    try scripts.put(hook_name, post_hook_script);
                }
            }
        }
    }

    // Write tasks
    var task_it = scripts.iterator();
    while (task_it.next()) |entry| {
        try writeTask(allocator, writer, entry.key_ptr.*, entry.value_ptr.*);
    }

    return try buf.toOwnedSlice(allocator);
}

const Script = struct {
    command: []const u8,
    deps: std.ArrayList([]const u8),
};

fn analyzeCommandDeps(allocator: std.mem.Allocator, script: *Script, command: []const u8) !void {
    // Detect npm run commands as dependencies
    // Pattern: "npm run <task>" or "npm-run <task>"
    var idx: usize = 0;
    while (std.mem.indexOfPos(u8, command, idx, "npm run ")) |pos| {
        idx = pos + 8; // Skip "npm run "

        // Extract task name (until space, &&, ||, ;, |, newline)
        var end = idx;
        while (end < command.len) : (end += 1) {
            const c = command[end];
            if (c == ' ' or c == '&' or c == '|' or c == ';' or c == '\n' or c == '\r') break;
        }

        if (end > idx) {
            const dep_name = command[idx..end];
            // Don't add self-dependencies
            if (!std.mem.eql(u8, dep_name, script.command)) {
                try script.deps.append(allocator, try allocator.dupe(u8, dep_name));
            }
        }
    }

    // Detect run-s/run-p patterns (npm-run-all sequential/parallel)
    if (std.mem.indexOf(u8, command, "run-s ") != null or
        std.mem.indexOf(u8, command, "npm-run-all -s ") != null or
        std.mem.indexOf(u8, command, "npm-run-all --serial ") != null) {
        // Sequential execution - extract task names as dependencies
        try extractRunAllDeps(allocator, script, command, "run-s ");
        try extractRunAllDeps(allocator, script, command, "npm-run-all -s ");
        try extractRunAllDeps(allocator, script, command, "npm-run-all --serial ");
    }

    // run-p means parallel - in zr this is default, so we don't add deps
    // but we could add a note in the command or use tags
}

fn extractRunAllDeps(allocator: std.mem.Allocator, script: *Script, command: []const u8, pattern: []const u8) !void {
    if (std.mem.indexOf(u8, command, pattern)) |pos| {
        var idx = pos + pattern.len;

        // Extract all task names until &&, ||, ;, |, newline
        while (idx < command.len) {
            // Skip whitespace
            while (idx < command.len and (command[idx] == ' ' or command[idx] == '\t')) : (idx += 1) {}
            if (idx >= command.len) break;

            // Check for command separator
            if (command[idx] == '&' or command[idx] == '|' or command[idx] == ';') break;

            // Extract task name
            var end = idx;
            while (end < command.len) : (end += 1) {
                const c = command[end];
                if (c == ' ' or c == '\t' or c == '&' or c == '|' or c == ';' or c == '\n' or c == '\r') break;
            }

            if (end > idx) {
                const dep_name = command[idx..end];
                // Skip flags (starting with -)
                if (dep_name[0] != '-') {
                    try script.deps.append(allocator, try allocator.dupe(u8, dep_name));
                }
            }

            idx = end;
        }
    }
}

fn writeTask(
    allocator: std.mem.Allocator,
    writer: anytype,
    name: []const u8,
    script: Script,
) !void {
    try writer.print("[tasks.{s}]\n", .{name});

    // Add dependencies if any
    if (script.deps.items.len > 0) {
        try writer.writeAll("deps = [");
        for (script.deps.items, 0..) |dep, idx| {
            if (idx > 0) try writer.writeAll(", ");
            try writer.print("\"{s}\"", .{dep});
        }
        try writer.writeAll("]\n");
    }

    // Escape and write command
    const escaped = try escapeString(allocator, script.command);
    defer allocator.free(escaped);
    try writer.print("cmd = \"{s}\"\n", .{escaped});

    try writer.writeAll("\n");
}

fn escapeString(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);
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

test "parseToZrToml handles simple package.json" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const package_json_content =
        \\{
        \\  "name": "my-app",
        \\  "scripts": {
        \\    "build": "tsc",
        \\    "test": "jest",
        \\    "dev": "vite"
        \\  }
        \\}
    ;

    try tmp.dir.writeFile(.{
        .sub_path = "package.json",
        .data = package_json_content,
    });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const package_path = try tmp.dir.realpath("package.json", &path_buf);

    const result = try parseToZrToml(std.testing.allocator, package_path);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.build]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.test]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.dev]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "cmd = \"tsc\"") != null);
}

test "parseToZrToml handles pre/post hooks" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const package_json_content =
        \\{
        \\  "scripts": {
        \\    "prebuild": "npm run clean",
        \\    "build": "tsc",
        \\    "postbuild": "npm run copy-assets"
        \\  }
        \\}
    ;

    try tmp.dir.writeFile(.{
        .sub_path = "package.json",
        .data = package_json_content,
    });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const package_path = try tmp.dir.realpath("package.json", &path_buf);

    const result = try parseToZrToml(std.testing.allocator, package_path);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.build]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.prebuild]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.postbuild]") != null);

    // Check that build depends on prebuild
    try std.testing.expect(std.mem.indexOf(u8, result, "deps = [\"prebuild\"]") != null);
}

test "parseToZrToml detects npm run dependencies" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const package_json_content =
        \\{
        \\  "scripts": {
        \\    "clean": "rm -rf dist",
        \\    "compile": "tsc",
        \\    "build": "npm run clean && npm run compile"
        \\  }
        \\}
    ;

    try tmp.dir.writeFile(.{
        .sub_path = "package.json",
        .data = package_json_content,
    });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const package_path = try tmp.dir.realpath("package.json", &path_buf);

    const result = try parseToZrToml(std.testing.allocator, package_path);
    defer std.testing.allocator.free(result);

    // Should have detected clean and compile as dependencies
    try std.testing.expect(std.mem.indexOf(u8, result, "deps = [\"clean\", \"compile\"]") != null);
}

test "parseToZrToml handles empty package.json" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const package_json_content =
        \\{
        \\  "name": "my-app"
        \\}
    ;

    try tmp.dir.writeFile(.{
        .sub_path = "package.json",
        .data = package_json_content,
    });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const package_path = try tmp.dir.realpath("package.json", &path_buf);

    const result = try parseToZrToml(std.testing.allocator, package_path);
    defer std.testing.allocator.free(result);

    // Should return minimal template with header
    try std.testing.expect(std.mem.indexOf(u8, result, "# zr.toml") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "No scripts found") != null);
}
