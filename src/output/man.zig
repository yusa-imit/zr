const std = @import("std");
const config_types = @import("../config/types.zig");

const Task = config_types.Task;
const TaskDescription = config_types.TaskDescription;

/// Generate man page format for a task
/// Format follows man(7) groff/troff markup conventions
pub fn formatManPage(
    allocator: std.mem.Allocator,
    task: Task,
    w: anytype,
) !void {
    // Man page header (.TH = Title Header)
    // Format: .TH name section date version manual
    try w.writeAll(".TH ZR-");
    const upper_name = try std.ascii.allocUpperString(allocator, task.name);
    defer allocator.free(upper_name);
    try w.print("{s} 1 ", .{upper_name});

    // Get current date in YYYY-MM-DD format
    const timestamp = std.time.timestamp();
    const epoch_day = @divFloor(timestamp, 86400);
    const year_day = @mod(epoch_day, 146097); // 400-year cycle
    const year_offset = @divFloor(year_day * 400, 146097);
    const year = 1970 + year_offset;
    const day_in_year = year_day - @divFloor(year_offset * 146097, 400);
    const month = @divFloor(day_in_year * 12, 365) + 1;
    const day = @mod(day_in_year, 31) + 1;
    try w.print("\"{d}-{d:0>2}-{d:0>2}\" ", .{year, month, day});

    try w.writeAll("\"ZR Manual\"\n");

    // NAME section
    try w.writeAll(".SH NAME\n");
    try w.print("zr-{s}", .{task.name});
    if (task.description) |desc| {
        try w.print(" \\- {s}", .{desc.getShort()});
    }
    try w.writeAll("\n");

    // SYNOPSIS section
    try w.writeAll(".SH SYNOPSIS\n");
    try w.writeAll(".B zr run\n");
    try w.print("{s}", .{task.name});

    // Add parameters to synopsis
    if (task.task_params.len > 0) {
        for (task.task_params) |param| {
            if (param.default != null) {
                try w.print(" [{s}=", .{param.name});
                try w.print("\\fI{s}\\fR", .{param.name});
                try w.writeAll("]");
            } else {
                try w.print(" {s}=", .{param.name});
                try w.print("\\fI{s}\\fR", .{param.name});
            }
        }
    }
    try w.writeAll("\n");

    // DESCRIPTION section
    if (task.description) |desc| {
        try w.writeAll(".SH DESCRIPTION\n");
        try w.print("{s}", .{desc.getShort()});
        try w.writeAll("\n");

        if (desc.getLong()) |long| {
            try w.writeAll(".PP\n");
            try w.print("{s}", .{long});
            try w.writeAll("\n");
        }
    }

    // PARAMETERS section
    if (task.task_params.len > 0) {
        try w.writeAll(".SH PARAMETERS\n");
        for (task.task_params) |param| {
            try w.writeAll(".TP\n");
            try w.writeAll(".B ");
            try w.print("{s}", .{param.name});
            if (param.default) |default| {
                try w.print(" (default: \\fI{s}\\fR)", .{default});
            } else {
                try w.writeAll(" (required)");
            }
            try w.writeAll("\n");

            if (param.description) |pdesc| {
                try w.print("{s}", .{pdesc});
                try w.writeAll("\n");
            }
        }
    }

    // EXAMPLES section
    if (task.examples) |examples| {
        if (examples.len > 0) {
            try w.writeAll(".SH EXAMPLES\n");
            for (examples) |example| {
                try w.writeAll(".PP\n");
                try w.writeAll(".nf\n");
                try w.writeAll(".RS\n");
                try w.print("{s}", .{example});
                try w.writeAll("\n");
                try w.writeAll(".RE\n");
                try w.writeAll(".fi\n");
            }
        }
    }

    // COMMAND section
    try w.writeAll(".SH COMMAND\n");
    try w.writeAll(".PP\n");
    try w.writeAll(".nf\n");
    try w.writeAll(".RS\n");
    try w.print("{s}", .{task.cmd});
    try w.writeAll("\n");
    try w.writeAll(".RE\n");
    try w.writeAll(".fi\n");

    // DEPENDENCIES section
    const total_deps = task.deps.len + task.deps_serial.len + task.deps_if.len + task.deps_optional.len;
    if (total_deps > 0) {
        try w.writeAll(".SH DEPENDENCIES\n");
        if (task.deps.len > 0) {
            try w.writeAll(".PP\n");
            try w.writeAll("Parallel dependencies:\n");
            try w.writeAll(".RS\n");
            for (task.deps) |dep| {
                try w.print(".IP \\(bu 2\n{s}\n", .{dep});
            }
            try w.writeAll(".RE\n");
        }
        if (task.deps_serial.len > 0) {
            try w.writeAll(".PP\n");
            try w.writeAll("Sequential dependencies:\n");
            try w.writeAll(".RS\n");
            for (task.deps_serial) |dep| {
                try w.print(".IP \\(bu 2\n{s}\n", .{dep});
            }
            try w.writeAll(".RE\n");
        }
        if (task.deps_optional.len > 0) {
            try w.writeAll(".PP\n");
            try w.writeAll("Optional dependencies:\n");
            try w.writeAll(".RS\n");
            for (task.deps_optional) |dep| {
                try w.print(".IP \\(bu 2\n{s}\n", .{dep});
            }
            try w.writeAll(".RE\n");
        }
    }

    // OUTPUTS section
    if (task.outputs) |outputs| {
        if (outputs.count() > 0) {
            try w.writeAll(".SH OUTPUTS\n");
            var it = outputs.iterator();
            while (it.next()) |entry| {
                try w.writeAll(".TP\n");
                try w.writeAll(".B ");
                try w.print("{s}", .{entry.key_ptr.*});
                try w.writeAll("\n");
                try w.print("{s}", .{entry.value_ptr.*});
                try w.writeAll("\n");
            }
        }
    }

    // SEE ALSO section
    if (task.see_also) |see_also| {
        if (see_also.len > 0) {
            try w.writeAll(".SH SEE ALSO\n");
            try w.writeAll(".PP\n");
            for (see_also, 0..) |related, i| {
                if (i > 0) try w.writeAll(", ");
                try w.writeAll(".BR zr-");
                try w.print("{s}", .{related});
                try w.writeAll(" (1)");
            }
            try w.writeAll("\n");
        }
    }

    // FOOTER
    try w.writeAll(".SH AUTHORS\n");
    try w.writeAll("Generated by zr task runner.\n");
}

test "formatManPage: basic task" {
    const allocator = std.testing.allocator;

    const task = Task{
        .name = "build",
        .cmd = "make all",
        .cwd = null,
        .description = .{ .string = "Build the project" },
        .examples = null,
        .outputs = null,
        .see_also = null,
        .deps = &[_][]const u8{},
        .deps_serial = &[_][]const u8{},
        .deps_if = &[_]config_types.ConditionalDep{},
        .deps_optional = &[_][]const u8{},
        .env = &[_][2][]const u8{},
        .env_file = null,
        .timeout_ms = null,
        .allow_failure = false,
        .retry_max = 0,
        .retry_delay_ms = 0,
        .retry_backoff = false,
        .retry_backoff_multiplier = null,
        .retry_jitter = false,
        .max_backoff_ms = null,
        .retry_on_codes = &[_]u8{},
        .retry_on_patterns = &[_][]const u8{},
        .condition = null,
        .skip_if = null,
        .output_if = null,
        .max_concurrent = 0,
        .cache = false,
        .max_cpu = null,
        .max_memory = null,
        .toolchain = &[_][]const u8{},
        .tags = &[_][]const u8{},
        .cpu_affinity = null,
        .numa_node = null,
        .watch = null,
        .hooks = &[_]config_types.TaskHook{},
        .template = null,
        .params = &[_][2][]const u8{},
        .circuit_breaker = null,
        .checkpoint = null,
        .output_file = null,
        .output_mode = null,
        .remote = null,
        .remote_cwd = null,
        .remote_env = null,
        .concurrency_group = null,
        .inherited = false,
        .mixins = &[_][]const u8{},
        .aliases = &[_][]const u8{},
        .silent = false,
        .task_params = &[_]config_types.TaskParam{},
        .sources = &[_][]const u8{},
        .generates = &[_][]const u8{},
    };

    var buf = std.ArrayList(u8).initCapacity(allocator, 1024) catch unreachable;
    defer buf.deinit(allocator);

    const writer = buf.writer(allocator);
    try formatManPage(allocator, task, writer);

    const output = buf.items;

    // Check for key man page sections
    try std.testing.expect(std.mem.indexOf(u8, output, ".TH ZR-BUILD") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, ".SH NAME") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, ".SH SYNOPSIS") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, ".SH DESCRIPTION") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Build the project") != null);
}
