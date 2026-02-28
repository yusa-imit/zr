const std = @import("std");
const Config = @import("../config/types.zig").Config;
const run = @import("run.zig");
const list = @import("list.zig");
const graph = @import("graph.zig");
const validate = @import("validate.zig");
const color = @import("../output/color.zig");

/// Natural language interface - keyword pattern matching to task commands
/// This is NOT an LLM - it's simple keyword matching for common phrases
pub fn cmdAi(allocator: std.mem.Allocator, args: []const []const u8, _: ?[]const u8) !u8 {
    if (args.len == 0) {
        std.debug.print("✗ missing natural language query\n\n  Usage: zr ai \"<your query>\"\n\n  Hint: Try \"build the project\" or \"run tests\"\n", .{});
        return 1;
    }

    // Join all arguments into a single query
    var query = std.ArrayList(u8){};
    defer query.deinit(allocator);

    for (args, 0..) |arg, i| {
        if (i > 0) try query.append(allocator, ' ');
        try query.appendSlice(allocator, arg);
    }

    const query_str = try query.toOwnedSlice(allocator);
    defer allocator.free(query_str);

    // Normalize query: lowercase + trim
    const normalized = try allocator.alloc(u8, query_str.len);
    defer allocator.free(normalized);
    _ = std.ascii.lowerString(normalized, query_str);

    // Pattern matching: extract command and task name
    const result = try parseQuery(allocator, normalized) orelse {
        std.debug.print("✗ Could not understand query: \"{s}\"\n\n  Supported patterns:\n  - \"build [the project]\" → zr run build\n  - \"test [everything]\" → zr run test\n  - \"run <task>\" → zr run <task>\n  - \"list [all] tasks\" → zr list\n  - \"show [me the] graph\" → zr graph\n  - \"validate [the] config\" → zr validate\n  - \"clean [up] [the project]\" → zr run clean\n  - \"install [dependencies]\" → zr run install\n  - \"deploy [the app]\" → zr run deploy\n  - \"start [the server]\" → zr run start\n  - \"stop [the server]\" → zr run stop\n\n  Hint: Use specific task names from your zr.toml\n", .{query_str});
        return 1;
    };
    defer allocator.free(result.task_name);

    // Show interpretation and suggest the actual command
    switch (result.command) {
        .run => {
            std.debug.print("» Interpreted as: zr run {s}\n\n", .{result.task_name});
            std.debug.print("  To execute, run:\n    zr run {s}\n", .{result.task_name});
            return 0;
        },
        .list => {
            std.debug.print("» Interpreted as: zr list\n\n", .{});
            std.debug.print("  To execute, run:\n    zr list\n", .{});
            return 0;
        },
        .graph => {
            std.debug.print("» Interpreted as: zr graph\n\n", .{});
            std.debug.print("  To execute, run:\n    zr graph\n", .{});
            return 0;
        },
        .validate => {
            std.debug.print("» Interpreted as: zr validate\n\n", .{});
            std.debug.print("  To execute, run:\n    zr validate\n", .{});
            return 0;
        },
    }
}

const Command = enum {
    run,
    list,
    graph,
    validate,
};

const ParseResult = struct {
    command: Command,
    task_name: []const u8, // owned, caller must free (empty for non-run commands)
};

/// Parse natural language query into a command + task name
/// Returns null if no pattern matches
fn parseQuery(allocator: std.mem.Allocator, query: []const u8) !?ParseResult {
    // Remove common filler words
    var cleaned = std.ArrayList(u8){};
    defer cleaned.deinit(allocator);

    var iter = std.mem.tokenizeAny(u8, query, " \t\n");
    while (iter.next()) |word| {
        // Skip filler words
        if (std.mem.eql(u8, word, "the") or
            std.mem.eql(u8, word, "a") or
            std.mem.eql(u8, word, "an") or
            std.mem.eql(u8, word, "me") or
            std.mem.eql(u8, word, "my") or
            std.mem.eql(u8, word, "please") or
            std.mem.eql(u8, word, "can") or
            std.mem.eql(u8, word, "you") or
            std.mem.eql(u8, word, "i") or
            std.mem.eql(u8, word, "want") or
            std.mem.eql(u8, word, "to"))
        {
            continue;
        }
        if (cleaned.items.len > 0) try cleaned.append(allocator, ' ');
        try cleaned.appendSlice(allocator, word);
    }

    const cleaned_str = cleaned.items;
    if (cleaned_str.len == 0) return null;

    // Pattern: "list [all] tasks" or "list"
    if (std.mem.indexOf(u8, cleaned_str, "list") != null) {
        if (std.mem.indexOf(u8, cleaned_str, "task") != null or cleaned_str.len <= 10) {
            return ParseResult{
                .command = .list,
                .task_name = try allocator.dupe(u8, ""),
            };
        }
    }

    // Pattern: "show [me] graph" or "graph" or "show graph"
    if (std.mem.indexOf(u8, cleaned_str, "graph") != null or
        (std.mem.indexOf(u8, cleaned_str, "show") != null and
        (std.mem.indexOf(u8, cleaned_str, "depend") != null or
        std.mem.indexOf(u8, cleaned_str, "visual") != null)))
    {
        return ParseResult{
            .command = .graph,
            .task_name = try allocator.dupe(u8, ""),
        };
    }

    // Pattern: "validate [config]"
    if (std.mem.indexOf(u8, cleaned_str, "validate") != null or
        std.mem.indexOf(u8, cleaned_str, "check config") != null)
    {
        return ParseResult{
            .command = .validate,
            .task_name = try allocator.dupe(u8, ""),
        };
    }

    // Pattern: "run <task>" - explicit run command
    if (std.mem.indexOf(u8, cleaned_str, "run ") != null) {
        const run_idx = std.mem.indexOf(u8, cleaned_str, "run ").?;
        const task_start = run_idx + 4; // "run "
        if (task_start < cleaned_str.len) {
            const task = std.mem.trim(u8, cleaned_str[task_start..], " ");
            if (task.len > 0) {
                return ParseResult{
                    .command = .run,
                    .task_name = try allocator.dupe(u8, task),
                };
            }
        }
    }

    // Pattern: single-word task names (build, test, clean, deploy, etc.)
    const common_tasks = [_][]const u8{
        "build",
        "test",
        "clean",
        "install",
        "deploy",
        "start",
        "stop",
        "lint",
        "format",
        "check",
        "watch",
        "dev",
        "prod",
        "release",
        "publish",
        "serve",
        "compile",
    };

    for (common_tasks) |task| {
        if (std.mem.indexOf(u8, cleaned_str, task) != null) {
            // Check if it's a whole word (not part of another word)
            const idx = std.mem.indexOf(u8, cleaned_str, task).?;
            const is_start = idx == 0 or cleaned_str[idx - 1] == ' ';
            const is_end = idx + task.len == cleaned_str.len or cleaned_str[idx + task.len] == ' ';

            if (is_start and is_end) {
                return ParseResult{
                    .command = .run,
                    .task_name = try allocator.dupe(u8, task),
                };
            }
        }
    }

    // Pattern: "<action> <task>" - extract task name after action verb
    const action_verbs = [_][]const u8{
        "execute",
        "perform",
        "do",
        "start",
        "stop",
        "restart",
    };

    for (action_verbs) |verb| {
        if (std.mem.indexOf(u8, cleaned_str, verb) != null) {
            const verb_idx = std.mem.indexOf(u8, cleaned_str, verb).?;
            const task_start = verb_idx + verb.len;
            if (task_start < cleaned_str.len) {
                const task = std.mem.trim(u8, cleaned_str[task_start..], " ");
                if (task.len > 0 and !std.mem.eql(u8, task, "task") and !std.mem.eql(u8, task, "tasks")) {
                    return ParseResult{
                        .command = .run,
                        .task_name = try allocator.dupe(u8, task),
                    };
                }
            }
        }
    }

    return null;
}

test "parseQuery: build patterns" {
    const allocator = std.testing.allocator;

    {
        const result = try parseQuery(allocator, "build") orelse unreachable;
        defer allocator.free(result.task_name);
        try std.testing.expectEqual(Command.run, result.command);
        try std.testing.expectEqualStrings("build", result.task_name);
    }

    {
        const result = try parseQuery(allocator, "build the project") orelse unreachable;
        defer allocator.free(result.task_name);
        try std.testing.expectEqual(Command.run, result.command);
        try std.testing.expectEqualStrings("build", result.task_name);
    }

    {
        const result = try parseQuery(allocator, "please build") orelse unreachable;
        defer allocator.free(result.task_name);
        try std.testing.expectEqual(Command.run, result.command);
        try std.testing.expectEqualStrings("build", result.task_name);
    }
}

test "parseQuery: test patterns" {
    const allocator = std.testing.allocator;

    {
        const result = try parseQuery(allocator, "test") orelse unreachable;
        defer allocator.free(result.task_name);
        try std.testing.expectEqual(Command.run, result.command);
        try std.testing.expectEqualStrings("test", result.task_name);
    }

    {
        const result = try parseQuery(allocator, "run tests") orelse unreachable;
        defer allocator.free(result.task_name);
        try std.testing.expectEqual(Command.run, result.command);
        try std.testing.expectEqualStrings("tests", result.task_name);
    }
}

test "parseQuery: list patterns" {
    const allocator = std.testing.allocator;

    {
        const result = try parseQuery(allocator, "list tasks") orelse unreachable;
        defer allocator.free(result.task_name);
        try std.testing.expectEqual(Command.list, result.command);
    }

    {
        const result = try parseQuery(allocator, "list all tasks") orelse unreachable;
        defer allocator.free(result.task_name);
        try std.testing.expectEqual(Command.list, result.command);
    }

    {
        const result = try parseQuery(allocator, "show me the list of tasks") orelse unreachable;
        defer allocator.free(result.task_name);
        try std.testing.expectEqual(Command.list, result.command);
    }
}

test "parseQuery: graph patterns" {
    const allocator = std.testing.allocator;

    {
        const result = try parseQuery(allocator, "show graph") orelse unreachable;
        defer allocator.free(result.task_name);
        try std.testing.expectEqual(Command.graph, result.command);
    }

    {
        const result = try parseQuery(allocator, "graph") orelse unreachable;
        defer allocator.free(result.task_name);
        try std.testing.expectEqual(Command.graph, result.command);
    }

    {
        const result = try parseQuery(allocator, "show me the dependency graph") orelse unreachable;
        defer allocator.free(result.task_name);
        try std.testing.expectEqual(Command.graph, result.command);
    }
}

test "parseQuery: validate patterns" {
    const allocator = std.testing.allocator;

    {
        const result = try parseQuery(allocator, "validate") orelse unreachable;
        defer allocator.free(result.task_name);
        try std.testing.expectEqual(Command.validate, result.command);
    }

    {
        const result = try parseQuery(allocator, "validate config") orelse unreachable;
        defer allocator.free(result.task_name);
        try std.testing.expectEqual(Command.validate, result.command);
    }

    {
        const result = try parseQuery(allocator, "check the config") orelse unreachable;
        defer allocator.free(result.task_name);
        try std.testing.expectEqual(Command.validate, result.command);
    }
}

test "parseQuery: explicit run command" {
    const allocator = std.testing.allocator;

    {
        const result = try parseQuery(allocator, "run build") orelse unreachable;
        defer allocator.free(result.task_name);
        try std.testing.expectEqual(Command.run, result.command);
        try std.testing.expectEqualStrings("build", result.task_name);
    }

    {
        const result = try parseQuery(allocator, "run custom-task-name") orelse unreachable;
        defer allocator.free(result.task_name);
        try std.testing.expectEqual(Command.run, result.command);
        try std.testing.expectEqualStrings("custom-task-name", result.task_name);
    }
}

test "parseQuery: action verb patterns" {
    const allocator = std.testing.allocator;

    {
        const result = try parseQuery(allocator, "execute build") orelse unreachable;
        defer allocator.free(result.task_name);
        try std.testing.expectEqual(Command.run, result.command);
        try std.testing.expectEqualStrings("build", result.task_name);
    }

    {
        const result = try parseQuery(allocator, "perform test") orelse unreachable;
        defer allocator.free(result.task_name);
        try std.testing.expectEqual(Command.run, result.command);
        try std.testing.expectEqualStrings("test", result.task_name);
    }
}

test "parseQuery: unrecognized query returns null" {
    const allocator = std.testing.allocator;

    {
        const result = try parseQuery(allocator, "make me a sandwich");
        try std.testing.expect(result == null);
    }

    {
        const result = try parseQuery(allocator, "hello world");
        try std.testing.expect(result == null);
    }

    {
        const result = try parseQuery(allocator, "");
        try std.testing.expect(result == null);
    }
}
