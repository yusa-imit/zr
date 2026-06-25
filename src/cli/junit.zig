const std = @import("std");
const scheduler = @import("../exec/scheduler.zig");

/// Write a JUnit XML report to `path` based on scheduler task results.
pub fn writeJunitXml(
    allocator: std.mem.Allocator,
    path: []const u8,
    suite_name: []const u8,
    results: []const scheduler.TaskResult,
    elapsed_ms: u64,
) !void {
    var failures: usize = 0;
    var skipped: usize = 0;
    for (results) |r| {
        if (r.skipped) skipped += 1 else if (!r.success) failures += 1;
    }
    const tests_count = results.len;
    const total_secs = @as(f64, @floatFromInt(elapsed_ms)) / 1000.0;

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    try buf.appendSlice(allocator, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");

    // <testsuites>
    {
        var tmp: [256]u8 = undefined;
        const header = try std.fmt.bufPrint(&tmp,
            "<testsuites name=\"zr\" tests=\"{d}\" failures=\"{d}\" errors=\"0\" skipped=\"{d}\" time=\"{d:.3}\">\n",
            .{ tests_count, failures, skipped, total_secs });
        try buf.appendSlice(allocator, header);
    }

    // <testsuite>
    try buf.appendSlice(allocator, "  <testsuite name=\"");
    try appendXmlEscaped(&buf, allocator, suite_name);
    {
        var tmp: [256]u8 = undefined;
        const attrs = try std.fmt.bufPrint(&tmp,
            "\" tests=\"{d}\" failures=\"{d}\" errors=\"0\" skipped=\"{d}\" time=\"{d:.3}\">\n",
            .{ tests_count, failures, skipped, total_secs });
        try buf.appendSlice(allocator, attrs);
    }

    for (results) |r| {
        const secs = @as(f64, @floatFromInt(r.duration_ms)) / 1000.0;

        try buf.appendSlice(allocator, "    <testcase name=\"");
        try appendXmlEscaped(&buf, allocator, r.task_name);
        {
            var tmp: [256]u8 = undefined;
            const time_attr = try std.fmt.bufPrint(&tmp, "\" classname=\"zr.task\" time=\"{d:.3}\"", .{secs});
            try buf.appendSlice(allocator, time_attr);
        }

        if (r.skipped) {
            try buf.appendSlice(allocator, ">\n      <skipped/>\n    </testcase>\n");
        } else if (!r.success) {
            {
                var tmp: [256]u8 = undefined;
                const fail_open = try std.fmt.bufPrint(&tmp,
                    ">\n      <failure message=\"exit code {d}\" type=\"ExecutionFailure\">Task '", .{r.exit_code});
                try buf.appendSlice(allocator, fail_open);
            }
            try appendXmlEscaped(&buf, allocator, r.task_name);
            {
                var tmp: [256]u8 = undefined;
                const fail_close = try std.fmt.bufPrint(&tmp, "' failed with exit code {d}</failure>\n    </testcase>\n", .{r.exit_code});
                try buf.appendSlice(allocator, fail_close);
            }
        } else {
            try buf.appendSlice(allocator, "/>\n");
        }
    }

    try buf.appendSlice(allocator, "  </testsuite>\n</testsuites>\n");

    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(buf.items);
}

fn appendXmlEscaped(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '&' => try buf.appendSlice(allocator, "&amp;"),
            '<' => try buf.appendSlice(allocator, "&lt;"),
            '>' => try buf.appendSlice(allocator, "&gt;"),
            '"' => try buf.appendSlice(allocator, "&quot;"),
            else => try buf.append(allocator, c),
        }
    }
}

test "writeJunitXml: generates valid XML for success/failure/skip" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a temporary directory in the current directory instead
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const full_path = "output.xml";

    const results = [_]scheduler.TaskResult{
        .{ .task_name = "compile", .success = true, .exit_code = 0, .duration_ms = 500 },
        .{ .task_name = "lint", .success = false, .exit_code = 1, .duration_ms = 200 },
        .{ .task_name = "format-check", .success = false, .exit_code = 0, .duration_ms = 100, .skipped = true },
    };

    // Get absolute path of temp directory
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const realpath = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(realpath);
    const abs_path = try std.fmt.bufPrint(&buf, "{s}/{s}", .{realpath, full_path});

    try writeJunitXml(allocator, abs_path, "build", &results, 800);

    const content = try tmp_dir.dir.readFileAlloc(allocator, full_path, 65536);
    defer allocator.free(content);

    // Verify XML header
    try testing.expect(std.mem.indexOf(u8, content, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>") != null);
    // Verify testsuites
    try testing.expect(std.mem.indexOf(u8, content, "tests=\"3\"") != null);
    try testing.expect(std.mem.indexOf(u8, content, "failures=\"1\"") != null);
    try testing.expect(std.mem.indexOf(u8, content, "skipped=\"1\"") != null);
    // Verify testcase elements
    try testing.expect(std.mem.indexOf(u8, content, "name=\"compile\"") != null);
    try testing.expect(std.mem.indexOf(u8, content, "name=\"lint\"") != null);
    // Verify failure element
    try testing.expect(std.mem.indexOf(u8, content, "<failure message=\"exit code 1\"") != null);
    // Verify skipped element
    try testing.expect(std.mem.indexOf(u8, content, "<skipped/>") != null);
}

test "writeJunitXml: XML-escapes special characters in task names" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const full_path = "output.xml";

    const results = [_]scheduler.TaskResult{
        .{ .task_name = "build<debug>&test", .success = true, .exit_code = 0, .duration_ms = 100 },
    };

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const realpath = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(realpath);
    const abs_path = try std.fmt.bufPrint(&buf, "{s}/{s}", .{realpath, full_path});

    try writeJunitXml(allocator, abs_path, "test<suite>", &results, 100);

    const content = try tmp_dir.dir.readFileAlloc(allocator, full_path, 65536);
    defer allocator.free(content);

    // Verify XML escaping
    try testing.expect(std.mem.indexOf(u8, content, "&lt;debug&gt;") != null);
    try testing.expect(std.mem.indexOf(u8, content, "&amp;test") != null);
    // Verify the suite name is escaped too
    try testing.expect(std.mem.indexOf(u8, content, "test&lt;suite&gt;") != null);
}

test "writeJunitXml: empty results generates valid XML" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const full_path = "output.xml";

    const results = [_]scheduler.TaskResult{};

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const realpath = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(realpath);
    const abs_path = try std.fmt.bufPrint(&buf, "{s}/{s}", .{realpath, full_path});

    try writeJunitXml(allocator, abs_path, "empty", &results, 0);

    const content = try tmp_dir.dir.readFileAlloc(allocator, full_path, 65536);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "tests=\"0\"") != null);
    try testing.expect(std.mem.indexOf(u8, content, "failures=\"0\"") != null);
    try testing.expect(std.mem.indexOf(u8, content, "</testsuite>") != null);
    try testing.expect(std.mem.indexOf(u8, content, "</testsuites>") != null);
}
