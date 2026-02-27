// Fuzz test for TOML parser
// Build and run with: zig build fuzz-toml
// This file is compiled as a standalone executable that imports from zr's main module

const std = @import("std");
// Import from the main zr module which has access to all source files
const zr = @import("zr");
const parser = zr.config_parser;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    const random = prng.random();

    var out_buf: [8192]u8 = undefined;
    const stdout_file = std.fs.File.stdout();
    var stdout_writer = stdout_file.writer(&out_buf);
    const stdout = &stdout_writer.interface;
    try stdout.print("Starting TOML parser fuzz test...\n", .{});
    try stdout.print("Press Ctrl+C to stop\n\n", .{});

    var iteration: usize = 0;
    var parse_errors: usize = 0;
    var oom_errors: usize = 0;

    const start_time = std.time.milliTimestamp();

    while (true) {
        iteration += 1;

        // Generate random TOML-like input (biased towards valid structure)
        const input = try generateFuzzInput(allocator, random);
        defer allocator.free(input);

        // Try to parse
        var parsed = parser.parseToml(allocator, input) catch |err| {
            if (err == error.OutOfMemory) {
                oom_errors += 1;
            } else {
                parse_errors += 1;
            }
            continue;
        };
        // Success - clean up
        parsed.deinit();

        // Report progress every 1000 iterations
        if (iteration % 1000 == 0) {
            const elapsed_ms = std.time.milliTimestamp() - start_time;
            const elapsed_sec = @divTrunc(elapsed_ms, 1000);
            try stdout.print(
                "Iterations: {d} | Elapsed: {d}s | Parse errors: {d} | OOM: {d}\n",
                .{ iteration, elapsed_sec, parse_errors, oom_errors },
            );
        }
    }
}

fn generateFuzzInput(allocator: std.mem.Allocator, random: std.Random) ![]const u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);

    const strategy = random.intRangeAtMost(u8, 0, 4);

    switch (strategy) {
        0 => {
            // Completely random bytes
            const len = random.intRangeAtMost(usize, 0, 1024);
            try buf.ensureTotalCapacity(allocator, len);
            for (0..len) |_| {
                try buf.append(allocator, random.int(u8));
            }
        },
        1 => {
            // Valid-ish structure with random values
            try buf.appendSlice(allocator, "[tasks.test]\n");
            try buf.appendSlice(allocator, "cmd = \"");
            const cmd_len = random.intRangeAtMost(usize, 0, 100);
            for (0..cmd_len) |_| {
                const ch = random.intRangeAtMost(u8, 32, 126);
                if (ch != '"' and ch != '\\') try buf.append(allocator, ch);
            }
            try buf.appendSlice(allocator, "\"\n");
            try buf.appendSlice(allocator, "timeout = \"");
            try buf.writer(allocator).print("{d}s\"\n", .{random.intRangeAtMost(u32, 1, 3600)});
        },
        2 => {
            // Malformed sections
            try buf.appendSlice(allocator, "[[[[[invalid");
            const extra = random.intRangeAtMost(usize, 0, 100);
            for (0..extra) |_| {
                try buf.append(allocator, random.intRangeAtMost(u8, 32, 126));
            }
        },
        3 => {
            // Very long lines
            const line_len = random.intRangeAtMost(usize, 1000, 10000);
            for (0..line_len) |_| {
                try buf.append(allocator, random.intRangeAtMost(u8, 32, 126));
            }
            try buf.append(allocator, '\n');
        },
        4 => {
            // Mix of valid and invalid TOML
            const sections = random.intRangeAtMost(usize, 1, 10);
            for (0..sections) |i| {
                try buf.writer(allocator).print("[tasks.task{d}]\n", .{i});
                try buf.appendSlice(allocator, "cmd = ");
                if (random.boolean()) {
                    try buf.appendSlice(allocator, "\"echo test\"\n");
                } else {
                    // Invalid value
                    try buf.appendSlice(allocator, "invalid{value}\n");
                }
                if (random.boolean()) {
                    try buf.appendSlice(allocator, "deps = [");
                    const dep_count = random.intRangeAtMost(usize, 0, 5);
                    for (0..dep_count) |j| {
                        if (j > 0) try buf.appendSlice(allocator, ", ");
                        try buf.writer(allocator).print("\"dep{d}\"", .{j});
                    }
                    try buf.appendSlice(allocator, "]\n");
                }
            }
        },
        else => unreachable,
    }

    return buf.toOwnedSlice(allocator);
}
