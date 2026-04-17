const std = @import("std");

const TaskMetadata = struct {
    tags: std.ArrayList([]const u8),
    env: std.StringHashMap([]const u8),
    parallel: bool,

    fn init(allocator: std.mem.Allocator) TaskMetadata {
        return .{
            .tags = std.ArrayList([]const u8){},
            .env = std.StringHashMap([]const u8).init(allocator),
            .parallel = false,
        };
    }

    fn deinit(self: *TaskMetadata, allocator: std.mem.Allocator) void {
        for (self.tags.items) |tag| allocator.free(tag);
        self.tags.deinit(allocator);
        var env_iter = self.env.iterator();
        while (env_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.env.deinit();
    }
};

/// Parse a Makefile and extract task definitions
/// Simple parser that handles common patterns:
/// - target: dependencies
///   command
/// - .PHONY: targets
/// Enhanced with semantic analysis:
/// - Tag inference from target names (test, build, deploy, etc.)
/// - Environment variable extraction from variable assignments
/// - Parallel/sequential pattern detection
pub fn parseToZrToml(allocator: std.mem.Allocator, makefile_path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(makefile_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // Max 10MB
    defer allocator.free(content);

    var buf = std.ArrayList(u8){};
    const writer = buf.writer(allocator);

    try writer.writeAll(
        \\# zr.toml — migrated from Makefile by `zr init --from-make`
        \\# Docs: https://github.com/yusa-imit/zr
        \\
        \\[global]
        \\shell = "bash"
        \\
        \\
    );

    var lines = std.mem.splitScalar(u8, content, '\n');
    var current_target: ?[]const u8 = null;
    var current_deps = std.ArrayList([]const u8){};
    defer current_deps.deinit(allocator);
    var current_commands = std.ArrayList([]const u8){};
    defer current_commands.deinit(allocator);
    var current_metadata = TaskMetadata.init(allocator);
    defer current_metadata.deinit(allocator);
    var phony_targets = std.StringHashMap(void).init(allocator);
    defer phony_targets.deinit();
    var global_vars = std.StringHashMap([]const u8).init(allocator);
    defer {
        var var_iter = global_vars.iterator();
        while (var_iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        global_vars.deinit();
    }

    while (lines.next()) |line_raw| {
        const line = std.mem.trimRight(u8, line_raw, " \t\r\n");

        // Skip empty lines and comments
        if (line.len == 0) continue;
        const trimmed = std.mem.trimLeft(u8, line, " \t");
        if (trimmed.len > 0 and trimmed[0] == '#') continue;

        // Parse variable assignments (VAR = value or VAR := value)
        if (std.mem.indexOf(u8, line, "=") != null and line[0] != '\t' and line[0] != ' ') {
            const eq_idx = std.mem.indexOf(u8, line, "=").?;
            if (eq_idx > 0 and (line[eq_idx - 1] == ' ' or line[eq_idx - 1] == ':' or eq_idx == line.len - 1 or line[eq_idx + 1] == ' ')) {
                var var_name_end = eq_idx;
                if (var_name_end > 0 and line[var_name_end - 1] == ' ') var_name_end -= 1;
                if (var_name_end > 0 and line[var_name_end - 1] == ':') var_name_end -= 1;
                const var_name = std.mem.trim(u8, line[0..var_name_end], " \t");
                var var_value_start = eq_idx + 1;
                if (var_value_start < line.len and line[var_value_start] == ' ') var_value_start += 1;
                const var_value = std.mem.trim(u8, line[var_value_start..], " \t");
                if (var_name.len > 0 and var_value.len > 0) {
                    try global_vars.put(try allocator.dupe(u8, var_name), try allocator.dupe(u8, var_value));
                }
            }
            continue;
        }

        // Parse .PHONY declarations
        if (std.mem.startsWith(u8, trimmed, ".PHONY:")) {
            const targets_str = std.mem.trim(u8, trimmed[7..], " \t");
            var target_iter = std.mem.splitScalar(u8, targets_str, ' ');
            while (target_iter.next()) |target| {
                const target_trimmed = std.mem.trim(u8, target, " \t");
                if (target_trimmed.len > 0) {
                    try phony_targets.put(try allocator.dupe(u8, target_trimmed), {});
                }
            }
            continue;
        }

        // Detect target: dependencies pattern (target lines don't start with whitespace)
        if (std.mem.indexOf(u8, line, ":") != null and line[0] != '\t' and line[0] != ' ') {
            // Save previous target if exists
            if (current_target) |target| {
                try writeTaskWithMetadata(allocator, &writer, target, current_deps.items, current_commands.items, &current_metadata);
                allocator.free(target);
                for (current_deps.items) |dep| allocator.free(dep);
                current_deps.clearRetainingCapacity();
                for (current_commands.items) |cmd| allocator.free(cmd);
                current_commands.clearRetainingCapacity();
                current_metadata.deinit(allocator);
                current_metadata = TaskMetadata.init(allocator);
            }

            // Parse new target
            const colon_idx = std.mem.indexOf(u8, line, ":").?;
            const target_name = std.mem.trim(u8, line[0..colon_idx], " \t");
            const deps_str = std.mem.trim(u8, line[colon_idx + 1 ..], " \t");

            // Skip special targets (starting with .)
            if (target_name.len > 0 and target_name[0] == '.') continue;

            current_target = try allocator.dupe(u8, target_name);

            // Infer tags from target name
            try inferTags(allocator, target_name, &current_metadata.tags);

            // Parse dependencies
            if (deps_str.len > 0) {
                var dep_iter = std.mem.splitScalar(u8, deps_str, ' ');
                while (dep_iter.next()) |dep| {
                    const dep_trimmed = std.mem.trim(u8, dep, " \t");
                    if (dep_trimmed.len > 0) {
                        try current_deps.append(allocator, try allocator.dupe(u8, dep_trimmed));
                    }
                }
            }
        } else if ((line[0] == '\t' or line[0] == ' ') and current_target != null) {
            // Command for current target (indented lines)
            const cmd = std.mem.trim(u8, line, " \t");
            if (cmd.len > 0) {
                try current_commands.append(allocator, try allocator.dupe(u8, cmd));
                // Analyze command for semantic patterns
                try analyzeCommand(allocator, cmd, &current_metadata);
            }
        }
    }

    // Write last target
    if (current_target) |target| {
        try writeTaskWithMetadata(allocator, &writer, target, current_deps.items, current_commands.items, &current_metadata);
        allocator.free(target);
        for (current_deps.items) |dep| allocator.free(dep);
        for (current_commands.items) |cmd| allocator.free(cmd);
    }

    // Clean up phony_targets
    var key_iter = phony_targets.keyIterator();
    while (key_iter.next()) |key| {
        allocator.free(key.*);
    }

    return try buf.toOwnedSlice(allocator);
}

fn writeTask(
    allocator: std.mem.Allocator,
    writer: anytype,
    target: []const u8,
    deps: []const []const u8,
    commands: []const []const u8,
) !void {
    try writer.print("[tasks.{s}]\n", .{target});

    if (deps.len > 0) {
        try writer.writeAll("deps = [");
        for (deps, 0..) |dep, idx| {
            if (idx > 0) try writer.writeAll(", ");
            try writer.print("\"{s}\"", .{dep});
        }
        try writer.writeAll("]\n");
    }

    if (commands.len > 0) {
        if (commands.len == 1) {
            // Single command: use string format
            const escaped = try escapeString(allocator, commands[0]);
            defer allocator.free(escaped);
            try writer.print("cmd = \"{s}\"\n", .{escaped});
        } else {
            // Multiple commands: join with &&
            var joined = std.ArrayList(u8){};
            defer joined.deinit(allocator);
            const j_writer = joined.writer(allocator);
            for (commands, 0..) |cmd, idx| {
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

fn writeTaskWithMetadata(
    allocator: std.mem.Allocator,
    writer: anytype,
    target: []const u8,
    deps: []const []const u8,
    commands: []const []const u8,
    metadata: *TaskMetadata,
) !void {
    try writer.print("[tasks.{s}]\n", .{target});

    // Write tags if any
    if (metadata.tags.items.len > 0) {
        try writer.writeAll("tags = [");
        for (metadata.tags.items, 0..) |tag, idx| {
            if (idx > 0) try writer.writeAll(", ");
            try writer.print("\"{s}\"", .{tag});
        }
        try writer.writeAll("]\n");
    }

    // Write environment variables if any
    if (metadata.env.count() > 0) {
        try writer.writeAll("[tasks.");
        try writer.writeAll(target);
        try writer.writeAll(".env]\n");
        var env_iter = metadata.env.iterator();
        while (env_iter.next()) |entry| {
            try writer.print("{s} = \"{s}\"\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
        try writer.writeAll("\n[tasks.");
        try writer.writeAll(target);
        try writer.writeAll("]\n");
    }

    if (deps.len > 0) {
        try writer.writeAll("deps = [");
        for (deps, 0..) |dep, idx| {
            if (idx > 0) try writer.writeAll(", ");
            try writer.print("\"{s}\"", .{dep});
        }
        try writer.writeAll("]\n");
    }

    if (commands.len > 0) {
        if (commands.len == 1) {
            const escaped = try escapeString(allocator, commands[0]);
            defer allocator.free(escaped);
            try writer.print("cmd = \"{s}\"\n", .{escaped});
        } else {
            // Multiple commands: check if parallel
            const joiner = if (metadata.parallel) " & " else " && ";
            var joined = std.ArrayList(u8){};
            defer joined.deinit(allocator);
            const j_writer = joined.writer(allocator);
            for (commands, 0..) |cmd, idx| {
                if (idx > 0) try j_writer.writeAll(joiner);
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

/// Infer task tags from target name patterns
fn inferTags(allocator: std.mem.Allocator, target_name: []const u8, tags: *std.ArrayList([]const u8)) !void {
    const lower_name = try std.ascii.allocLowerString(allocator, target_name);
    defer allocator.free(lower_name);

    const tag_patterns = [_]struct { pattern: []const u8, tag: []const u8 }{
        .{ .pattern = "test", .tag = "test" },
        .{ .pattern = "check", .tag = "test" },
        .{ .pattern = "build", .tag = "build" },
        .{ .pattern = "compile", .tag = "build" },
        .{ .pattern = "deploy", .tag = "deploy" },
        .{ .pattern = "publish", .tag = "deploy" },
        .{ .pattern = "release", .tag = "deploy" },
        .{ .pattern = "clean", .tag = "cleanup" },
        .{ .pattern = "install", .tag = "setup" },
        .{ .pattern = "setup", .tag = "setup" },
        .{ .pattern = "dev", .tag = "dev" },
        .{ .pattern = "watch", .tag = "dev" },
        .{ .pattern = "serve", .tag = "dev" },
        .{ .pattern = "start", .tag = "dev" },
        .{ .pattern = "lint", .tag = "lint" },
        .{ .pattern = "format", .tag = "lint" },
        .{ .pattern = "fmt", .tag = "lint" },
        .{ .pattern = "ci", .tag = "ci" },
        .{ .pattern = "docker", .tag = "docker" },
        .{ .pattern = "container", .tag = "docker" },
    };

    var added_tags = std.StringHashMap(void).init(allocator);
    defer added_tags.deinit();

    for (tag_patterns) |pattern_entry| {
        if (std.mem.indexOf(u8, lower_name, pattern_entry.pattern) != null) {
            if (!added_tags.contains(pattern_entry.tag)) {
                try tags.append(allocator, try allocator.dupe(u8, pattern_entry.tag));
                try added_tags.put(pattern_entry.tag, {});
            }
        }
    }
}

/// Analyze command for semantic patterns
fn analyzeCommand(allocator: std.mem.Allocator, cmd: []const u8, metadata: *TaskMetadata) !void {
    // Detect parallel execution patterns (commands ending with &)
    if (std.mem.endsWith(u8, std.mem.trim(u8, cmd, " \t"), "&")) {
        metadata.parallel = true;
    }

    // Extract environment variable assignments (VAR=value)
    var i: usize = 0;
    while (i < cmd.len) : (i += 1) {
        if (cmd[i] == '=' and i > 0) {
            // Find start of variable name
            var start = i;
            while (start > 0 and (std.ascii.isAlphanumeric(cmd[start - 1]) or cmd[start - 1] == '_')) {
                start -= 1;
            }
            // Check if this looks like an env var (all caps or starts with uppercase)
            const var_name = cmd[start..i];
            if (var_name.len > 0 and std.ascii.isUpper(var_name[0])) {
                // Find end of value (space or &&)
                var end = i + 1;
                var in_quote = false;
                while (end < cmd.len) : (end += 1) {
                    if (cmd[end] == '"' or cmd[end] == '\'') {
                        in_quote = !in_quote;
                    } else if (!in_quote and (cmd[end] == ' ' or cmd[end] == '\t')) {
                        break;
                    } else if (!in_quote and end + 1 < cmd.len and cmd[end] == '&' and cmd[end + 1] == '&') {
                        break;
                    }
                }
                const var_value = std.mem.trim(u8, cmd[i + 1 .. end], " \t\"'");
                if (var_value.len > 0) {
                    const key = try allocator.dupe(u8, var_name);
                    const value = try allocator.dupe(u8, var_value);
                    try metadata.env.put(key, value);
                }
            }
        }
    }
}

test "parseToZrToml handles simple Makefile" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create test Makefile (tabs required in Makefile format)
    const makefile_content = ".PHONY: build test clean\n\n" ++
        "build: deps\n\tgo build -o app .\n\n" ++
        "test: build\n\tgo test ./...\n\n" ++
        "clean:\n\trm -rf app dist/\n";

    try tmp.dir.writeFile(.{
        .sub_path = "Makefile",
        .data = makefile_content,
    });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const makefile_path = try tmp.dir.realpath("Makefile", &path_buf);

    const result = try parseToZrToml(std.testing.allocator, makefile_path);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.build]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.test]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.clean]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "deps = [\"deps\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "go build") != null);
}

test "parseToZrToml with semantic analysis - tags and env vars" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Create Makefile with semantic patterns (tabs required for Makefile commands)
    const makefile_content = "NODE_ENV = production\n" ++
        "PORT = 8080\n\n" ++
        ".PHONY: test deploy dev\n\n" ++
        "test:\n\tnpm run test:unit\n\tnpm run test:integration\n\n" ++
        "deploy: build\n\tNODE_ENV=production kubectl apply -f k8s/\n\techo \"Deployed to production\"\n\n" ++
        "dev:\n\tnpm run watch &\n\tnpm run serve &\n";

    try tmp.dir.writeFile(.{
        .sub_path = "Makefile",
        .data = makefile_content,
    });

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const makefile_path = try tmp.dir.realpath("Makefile", &path_buf);

    const result = try parseToZrToml(std.testing.allocator, makefile_path);
    defer std.testing.allocator.free(result);

    // Verify task inference
    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.test]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.deploy]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "[tasks.dev]") != null);

    // Verify tag inference
    try std.testing.expect(std.mem.indexOf(u8, result, "tags = [\"test\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "tags = [\"deploy\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "tags = [\"dev\"]") != null);

    // Verify environment variable extraction
    try std.testing.expect(std.mem.indexOf(u8, result, "NODE_ENV") != null);

    // Verify parallel detection (dev task has & at end of commands)
    try std.testing.expect(std.mem.indexOf(u8, result, " & ") != null);
}
