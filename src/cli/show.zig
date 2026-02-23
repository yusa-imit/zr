const std = @import("std");
const Allocator = std.mem.Allocator;
const color = @import("../output/color.zig");
const common = @import("common.zig");
const types = @import("../config/types.zig");

pub fn cmdShow(
    allocator: Allocator,
    task_name: []const u8,
    config_path: []const u8,
    w: *std.Io.Writer,
    ew: *std.Io.Writer,
    use_color: bool,
) !u8 {
    // Load config
    var config = (try common.loadConfig(allocator, config_path, null, ew, use_color)) orelse return 1;
    defer config.deinit();

    // Find task
    const task = config.tasks.get(task_name) orelse {
        try color.printError(ew, use_color,
            "show: Task '{s}' not found\n\n  Hint: Run 'zr list' to see available tasks\n",
            .{task_name},
        );
        return 1;
    };

    // Print task details
    try color.printBold(w, use_color, "Task: {s}\n", .{task_name});
    try w.print("\n", .{});

    // Description
    if (task.description) |desc| {
        try color.printDim(w, use_color, "  {s}\n\n", .{desc});
    }

    // Command
    try color.printBold(w, use_color, "Command:\n", .{});
    try w.print("  {s}\n\n", .{task.cmd});

    // Working directory
    if (task.cwd) |cwd| {
        try color.printBold(w, use_color, "Working Directory:\n", .{});
        try w.print("  {s}\n\n", .{cwd});
    }

    // Dependencies
    if (task.deps.len > 0 or task.deps_serial.len > 0) {
        try color.printBold(w, use_color, "Dependencies:\n", .{});
        if (task.deps.len > 0) {
            try w.print("  Parallel:\n", .{});
            for (task.deps) |dep| {
                try w.print("    • {s}\n", .{dep});
            }
        }
        if (task.deps_serial.len > 0) {
            try w.print("  Serial:\n", .{});
            for (task.deps_serial) |dep| {
                try w.print("    • {s}\n", .{dep});
            }
        }
        try w.print("\n", .{});
    }

    // Tags
    if (task.tags.len > 0) {
        try color.printBold(w, use_color, "Tags:\n", .{});
        try w.print("  ", .{});
        for (task.tags, 0..) |tag, i| {
            if (i > 0) try w.print(", ", .{});
            try w.print("{s}", .{tag});
        }
        try w.print("\n\n", .{});
    }

    // Environment variables
    if (task.env.len > 0) {
        try color.printBold(w, use_color, "Environment:\n", .{});
        for (task.env) |kv| {
            try w.print("  {s} = {s}\n", .{ kv[0], kv[1] });
        }
        try w.print("\n", .{});
    }

    // Execution settings
    var has_exec_settings = false;
    if (task.timeout_ms != null or
        task.allow_failure or
        task.retry_max > 0 or
        task.max_concurrent > 0)
    {
        has_exec_settings = true;
    }

    if (has_exec_settings) {
        try color.printBold(w, use_color, "Execution:\n", .{});

        if (task.timeout_ms) |timeout| {
            const seconds = timeout / 1000;
            if (seconds < 60) {
                try w.print("  Timeout: {d}s\n", .{seconds});
            } else {
                const minutes = seconds / 60;
                try w.print("  Timeout: {d}min\n", .{minutes});
            }
        }

        if (task.allow_failure) {
            try w.print("  Allow Failure: yes\n", .{});
        }

        if (task.retry_max > 0) {
            try w.print("  Retry: {d} attempt(s)", .{task.retry_max});
            if (task.retry_delay_ms > 0) {
                const delay_s = task.retry_delay_ms / 1000;
                try w.print(", {d}s delay", .{delay_s});
            }
            if (task.retry_backoff) {
                try w.print(", exponential backoff", .{});
            }
            try w.print("\n", .{});
        }

        if (task.max_concurrent > 0) {
            try w.print("  Max Concurrent: {d}\n", .{task.max_concurrent});
        }

        try w.print("\n", .{});
    }

    // Resource limits
    if (task.max_cpu != null or task.max_memory != null) {
        try color.printBold(w, use_color, "Resource Limits:\n", .{});

        if (task.max_cpu) |max_cpu| {
            try w.print("  CPU: {d}%\n", .{max_cpu});
        }

        if (task.max_memory) |max_mem| {
            const mb = max_mem / (1024 * 1024);
            const gb = @as(f64, @floatFromInt(max_mem)) / (1024.0 * 1024.0 * 1024.0);
            if (mb < 1024) {
                try w.print("  Memory: {d}MB\n", .{mb});
            } else {
                try w.print("  Memory: {d:.1}GB\n", .{gb});
            }
        }

        try w.print("\n", .{});
    }

    // Condition
    if (task.condition) |cond| {
        try color.printBold(w, use_color, "Condition:\n", .{});
        try w.print("  {s}\n\n", .{cond});
    }

    // Cache
    if (task.cache) {
        try color.printBold(w, use_color, "Caching:\n", .{});
        try color.printSuccess(w, use_color, "  Enabled ✓\n\n", .{});
    }

    // Toolchain
    if (task.toolchain.len > 0) {
        try color.printBold(w, use_color, "Toolchain:\n", .{});
        for (task.toolchain) |tool_spec| {
            try w.print("  • {s}\n", .{tool_spec});
        }
        try w.print("\n", .{});
    }

    return 0;
}

// Tests
test "cmdShow nonexistent task returns error" {
    const allocator = std.testing.allocator;

    var out_buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);

    var err_buf: [4096]u8 = undefined;
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    // Test with non-existent task - this will fail to load config but that's okay for this test
    const exit_code = try cmdShow(allocator, "nonexistent", "zr.toml", &out_w.interface, &err_w.interface, false);
    try std.testing.expectEqual(@as(u8, 1), exit_code);
}
