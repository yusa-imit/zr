const std = @import("std");
const Config = @import("../config/types.zig").Config;
const TaskTemplate = @import("../config/types.zig").TaskTemplate;
const loader = @import("../config/loader.zig");
const color = @import("../output/color.zig");
const template_cmd = @import("../cli/template_cmd.zig");

/// List all available templates in the configuration.
pub fn listTemplates(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    _ = args; // No additional arguments needed for list

    var config = try loader.loadFromFile(allocator, "zr.toml");
    defer config.deinit();

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    defer out_w.interface.flush() catch {};

    if (config.templates.count() == 0) {
        try out_w.interface.print("No templates defined in zr.toml\n", .{});
        return 0;
    }

    // Print header
    try out_w.interface.print("\nAvailable Templates:\n\n", .{});

    // Iterate through templates and print summary
    var iter = config.templates.iterator();
    while (iter.next()) |entry| {
        const template = entry.value_ptr.*;

        try out_w.interface.print("  ", .{});
        try color.printBold(&out_w.interface, true, "{s}", .{template.name});

        if (template.description) |desc| {
            try out_w.interface.print(" - {s}", .{desc});
        }
        try out_w.interface.print("\n", .{});

        // Show parameters if any
        if (template.params.len > 0) {
            try out_w.interface.print("    Parameters: ", .{});
            for (template.params, 0..) |param, i| {
                if (i > 0) try out_w.interface.print(", ", .{});
                try out_w.interface.print("{s}", .{param});
            }
            try out_w.interface.print("\n", .{});
        }
    }

    try out_w.interface.print("\n", .{});
    return 0;
}

/// Show detailed information about a specific template.
pub fn showTemplate(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    defer out_w.interface.flush() catch {};

    var err_buf: [2048]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);
    defer err_w.interface.flush() catch {};

    if (args.len == 0) {
        try err_w.interface.print("Error: template name required\n", .{});
        try err_w.interface.print("Usage: zr template show <name>\n", .{});
        return 1;
    }

    const template_name = args[0];

    var config = try loader.loadFromFile(allocator, "zr.toml");
    defer config.deinit();

    const template = config.templates.get(template_name) orelse {
        try err_w.interface.print("Error: template '{s}' not found\n", .{template_name});
        return 1;
    };

    // Print template name
    try out_w.interface.print("\nTemplate: ", .{});
    try color.printBold(&out_w.interface, true, "{s}", .{template.name});
    try out_w.interface.print("\n\n", .{});

    // Print description if present
    if (template.description) |desc| {
        try out_w.interface.print("Description: {s}\n\n", .{desc});
    }

    // Print parameters
    if (template.params.len > 0) {
        try out_w.interface.print("Parameters:\n", .{});
        for (template.params) |param| {
            try out_w.interface.print("  - {s}\n", .{param});
        }
        try out_w.interface.print("\n", .{});
    }

    // Print command
    try out_w.interface.print("Command:\n  {s}\n\n", .{template.cmd});

    // Print optional fields
    if (template.cwd) |cwd| {
        try out_w.interface.print("Working Directory: {s}\n", .{cwd});
    }

    if (template.timeout_ms) |timeout| {
        try out_w.interface.print("Timeout: {d}ms\n", .{timeout});
    }

    if (template.allow_failure) {
        try out_w.interface.print("Allow Failure: true\n", .{});
    }

    if (template.retry_max > 0) {
        try out_w.interface.print("Retry: {d} times (delay: {d}ms, backoff: {})\n", .{
            template.retry_max,
            template.retry_delay_ms,
            template.retry_backoff,
        });
    }

    if (template.condition) |cond| {
        try out_w.interface.print("Condition: {s}\n", .{cond});
    }

    if (template.max_concurrent > 0) {
        try out_w.interface.print("Max Concurrent: {d}\n", .{template.max_concurrent});
    }

    if (template.cache) {
        try out_w.interface.print("Cache: enabled\n", .{});
    }

    if (template.max_cpu) |cpu| {
        try out_w.interface.print("Max CPU: {d}%\n", .{cpu});
    }

    if (template.max_memory) |mem| {
        try out_w.interface.print("Max Memory: {d} bytes\n", .{mem});
    }

    // Print dependencies
    if (template.deps.len > 0) {
        try out_w.interface.print("\nDependencies:\n", .{});
        for (template.deps) |dep| {
            try out_w.interface.print("  - {s}\n", .{dep});
        }
    }

    if (template.deps_serial.len > 0) {
        try out_w.interface.print("\nSerial Dependencies:\n", .{});
        for (template.deps_serial) |dep| {
            try out_w.interface.print("  - {s}\n", .{dep});
        }
    }

    // Print environment variables
    if (template.env.len > 0) {
        try out_w.interface.print("\nEnvironment Variables:\n", .{});
        for (template.env) |pair| {
            try out_w.interface.print("  {s} = {s}\n", .{ pair[0], pair[1] });
        }
    }

    // Print toolchain
    if (template.toolchain.len > 0) {
        try out_w.interface.print("\nToolchain:\n", .{});
        for (template.toolchain) |tool| {
            try out_w.interface.print("  - {s}\n", .{tool});
        }
    }

    try out_w.interface.print("\n", .{});
    return 0;
}

/// Apply a template to create a new task interactively.
pub fn applyTemplate(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    defer out_w.interface.flush() catch {};

    var err_buf: [2048]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);
    defer err_w.interface.flush() catch {};

    if (args.len == 0) {
        try err_w.interface.print("Error: template name required\n", .{});
        try err_w.interface.print("Usage: zr template apply <template-name> <task-name>\n", .{});
        return 1;
    }

    if (args.len < 2) {
        try err_w.interface.print("Error: task name required\n", .{});
        try err_w.interface.print("Usage: zr template apply <template-name> <task-name>\n", .{});
        return 1;
    }

    const template_name = args[0];
    const task_name = args[1];

    var config = try loader.loadFromFile(allocator, "zr.toml");
    defer config.deinit();

    const template = config.templates.get(template_name) orelse {
        try err_w.interface.print("Error: template '{s}' not found\n", .{template_name});
        return 1;
    };

    const stdin = std.fs.File.stdin();

    // Collect parameter values interactively
    var params = std.ArrayList([2][]const u8){};
    defer {
        for (params.items) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        params.deinit(allocator);
    }

    if (template.params.len > 0) {
        try out_w.interface.print("\nEnter parameter values:\n\n", .{});
        try out_w.interface.flush();

        for (template.params) |param| {
            try out_w.interface.print("  {s}: ", .{param});
            try out_w.interface.flush();

            // Read parameter value from stdin line by line
            var buffer = std.ArrayList(u8){};
            defer buffer.deinit(allocator);

            var read_buf: [1]u8 = undefined;
            while (true) {
                const n = stdin.read(&read_buf) catch |err| {
                    if (err == error.EndOfStream or err == error.NotOpenForReading) {
                        try err_w.interface.print("\nError: unexpected end of input\n", .{});
                        return 1;
                    }
                    return err;
                };
                if (n == 0) {
                    // EOF
                    try err_w.interface.print("\nError: unexpected end of input\n", .{});
                    return 1;
                }
                const ch = read_buf[0];
                if (ch == '\n') break;
                if (ch != '\r') {
                    try buffer.append(allocator, ch);
                }
            }

            const value = std.mem.trim(u8, buffer.items, &std.ascii.whitespace);
            if (value.len == 0) {
                try err_w.interface.print("Error: parameter value cannot be empty\n", .{});
                return 1;
            }

            const param_copy = try allocator.dupe(u8, param);
            const value_copy = try allocator.dupe(u8, value);
            try params.append(allocator, .{ param_copy, value_copy });
        }
    }

    // Generate TOML for the new task
    try out_w.interface.print("\nGenerated task configuration:\n\n", .{});
    try out_w.interface.print("[[tasks]]\n", .{});
    try out_w.interface.print("name = \"{s}\"\n", .{task_name});
    try out_w.interface.print("template = \"{s}\"\n", .{template_name});

    if (params.items.len > 0) {
        try out_w.interface.print("params = {{ ", .{});
        for (params.items, 0..) |pair, i| {
            if (i > 0) try out_w.interface.print(", ", .{});
            try out_w.interface.print("{s} = \"{s}\"", .{ pair[0], pair[1] });
        }
        try out_w.interface.print(" }}\n", .{});
    }

    try out_w.interface.print("\nAdd this to zr.toml? (y/n): ", .{});
    try out_w.interface.flush();

    var confirm_buffer = std.ArrayList(u8){};
    defer confirm_buffer.deinit(allocator);

    var read_buf: [1]u8 = undefined;
    while (true) {
        const n = stdin.read(&read_buf) catch |err| {
            if (err == error.EndOfStream or err == error.NotOpenForReading) {
                try out_w.interface.print("Cancelled.\n", .{});
                return 0;
            }
            return err;
        };
        if (n == 0) {
            // EOF
            try out_w.interface.print("Cancelled.\n", .{});
            return 0;
        }
        const ch = read_buf[0];
        if (ch == '\n') break;
        if (ch != '\r') {
            try confirm_buffer.append(allocator, ch);
        }
    }

    const confirm = std.mem.trim(u8, confirm_buffer.items, &std.ascii.whitespace);
    if (!std.mem.eql(u8, confirm, "y") and !std.mem.eql(u8, confirm, "Y")) {
        try out_w.interface.print("Cancelled.\n", .{});
        return 0;
    }

    // Append to zr.toml
    const file = try std.fs.cwd().openFile("zr.toml", .{ .mode = .read_write });
    defer file.close();

    try file.seekFromEnd(0);

    var file_buf: [4096]u8 = undefined;
    var file_w = file.writer(&file_buf);

    try file_w.interface.print("\n[[tasks]]\n", .{});
    try file_w.interface.print("name = \"{s}\"\n", .{task_name});
    try file_w.interface.print("template = \"{s}\"\n", .{template_name});

    if (params.items.len > 0) {
        try file_w.interface.print("params = {{ ", .{});
        for (params.items, 0..) |pair, i| {
            if (i > 0) try file_w.interface.print(", ", .{});
            try file_w.interface.print("{s} = \"{s}\"", .{ pair[0], pair[1] });
        }
        try file_w.interface.print(" }}\n", .{});
    }

    try file_w.interface.flush();

    try out_w.interface.print("\nTask '", .{});
    try color.printBold(&out_w.interface, true, "{s}", .{task_name});
    try out_w.interface.print("' added successfully!\n", .{});

    return 0;
}

test "template commands: listTemplates with no templates" {
    const allocator = std.testing.allocator;

    // This test requires a temp zr.toml with no templates
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "zr.toml", .data = "# Empty config\n" });

    var buf: [1024]u8 = undefined;
    const cwd = try tmp_dir.dir.realpath(".", &buf);
    const old_cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(old_cwd);

    try std.posix.chdir(cwd);
    defer std.posix.chdir(old_cwd) catch {};

    const exit_code = try listTemplates(allocator, &[_][]const u8{});
    try std.testing.expectEqual(@as(u8, 0), exit_code);
}

test "template commands: showTemplate with non-existent template" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "zr.toml", .data = "# Empty config\n" });

    var buf: [1024]u8 = undefined;
    const cwd = try tmp_dir.dir.realpath(".", &buf);
    const old_cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(old_cwd);

    try std.posix.chdir(cwd);
    defer std.posix.chdir(old_cwd) catch {};

    const exit_code = try showTemplate(allocator, &[_][]const u8{"nonexistent"});
    try std.testing.expectEqual(@as(u8, 1), exit_code);
}

/// List built-in templates (separate from user-defined templates in zr.toml)
pub fn listBuiltinTemplates(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    _ = allocator;
    _ = args;

    var out_buf: [8192]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    defer out_w.interface.flush() catch {};

    try template_cmd.listTemplates(&out_w.interface, null);
    return 0;
}

/// Show a built-in template
pub fn showBuiltinTemplate(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    _ = allocator;

    var out_buf: [8192]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    defer out_w.interface.flush() catch {};

    var err_buf: [2048]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);
    defer err_w.interface.flush() catch {};

    if (args.len == 0) {
        try err_w.interface.print("Error: template name required\n", .{});
        try err_w.interface.print("Usage: zr template show <name>\n", .{});
        return 1;
    }

    template_cmd.showTemplate(&out_w.interface, args[0]) catch |err| {
        if (err == error.TemplateNotFound) {
            return 1;
        }
        return err;
    };

    return 0;
}

/// Add a built-in template to the current project
pub fn addBuiltinTemplate(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    var out_buf: [8192]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    defer out_w.interface.flush() catch {};

    var err_buf: [2048]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);
    defer err_w.interface.flush() catch {};

    if (args.len == 0) {
        try err_w.interface.print("Error: template name required\n", .{});
        try err_w.interface.print("Usage: zr template add <name> [--var KEY=VALUE ...] [--output <path>]\n", .{});
        return 1;
    }

    const template_name = args[0];

    // Parse additional arguments for --var and --output
    var variables = std.StringHashMap([]const u8).init(allocator);
    defer variables.deinit();

    var output_path: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--var") and i + 1 < args.len) {
            i += 1;
            const var_arg = args[i];
            // Parse KEY=VALUE
            if (std.mem.indexOfScalar(u8, var_arg, '=')) |eq_pos| {
                const key = var_arg[0..eq_pos];
                const value = var_arg[eq_pos + 1 ..];
                try variables.put(key, value);
            } else {
                try err_w.interface.print("Error: Invalid --var format, expected KEY=VALUE\n", .{});
                return 1;
            }
        } else if (std.mem.eql(u8, arg, "--output") and i + 1 < args.len) {
            i += 1;
            output_path = args[i];
        }
    }

    template_cmd.addTemplate(allocator, &out_w.interface, template_name, variables, output_path) catch |err| {
        if (err == error.TemplateNotFound or err == error.MissingRequiredVariable) {
            return 1;
        }
        return err;
    };

    return 0;
}
