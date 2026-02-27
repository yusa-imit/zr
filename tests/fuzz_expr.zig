// Fuzz test for expression engine
// Build and run with: zig build fuzz-expr
// This file is compiled as a standalone executable that imports from zr's main module

const std = @import("std");
// Import from the main zr module which has access to all source files
const zr = @import("zr");
const expr = zr.config_expr;

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
    try stdout.print("Starting expression engine fuzz test...\n", .{});
    try stdout.print("Press Ctrl+C to stop\n\n", .{});

    var iteration: usize = 0;
    var eval_errors: usize = 0;
    var oom_errors: usize = 0;

    const start_time = std.time.milliTimestamp();

    while (true) {
        iteration += 1;

        // Generate random expression
        const input = try generateExprInput(allocator, random);
        defer allocator.free(input);

        // Try to evaluate (use null task_env)
        if (expr.evalCondition(allocator, input, null)) |_| {
            // Success - got a boolean result
        } else |err| switch (err) {
            error.OutOfMemory => oom_errors += 1,
            error.InvalidExpression => eval_errors += 1,
        }

        // Report progress every 1000 iterations
        if (iteration % 1000 == 0) {
            const elapsed_ms = std.time.milliTimestamp() - start_time;
            const elapsed_sec = @divTrunc(elapsed_ms, 1000);
            try stdout.print(
                "Iterations: {d} | Elapsed: {d}s | Eval errors: {d} | OOM: {d}\n",
                .{ iteration, elapsed_sec, eval_errors, oom_errors },
            );
        }
    }
}

fn generateExprInput(allocator: std.mem.Allocator, random: std.Random) ![]const u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);

    const strategy = random.intRangeAtMost(u8, 0, 6);

    switch (strategy) {
        0 => {
            // Completely random bytes
            const len = random.intRangeAtMost(usize, 0, 200);
            try buf.ensureTotalCapacity(allocator, len);
            for (0..len) |_| {
                try buf.append(allocator, random.int(u8));
            }
        },
        1 => {
            // Valid variable references
            const vars = [_][]const u8{
                "platform.os",
                "platform.arch",
                "platform.is_windows",
                "platform.is_macos",
                "platform.is_linux",
                "env.HOME",
                "env.PATH",
                "env.USER",
                "runtime.task",
                "runtime.hash",
                "runtime.iteration",
            };
            const var_name = vars[random.intRangeAtMost(usize, 0, vars.len - 1)];
            try buf.appendSlice(allocator, var_name);
        },
        2 => {
            // Valid function calls
            const funcs = [_][]const u8{
                "file.exists(\"test.txt\")",
                "file.changed(\"src/\")",
                "file.newer(\"a.txt\", \"b.txt\")",
                "file.hash(\"data.bin\")",
                "shell(\"echo test\")",
                "semver.gt(\"1.0.0\", \"0.9.0\")",
            };
            const func_call = funcs[random.intRangeAtMost(usize, 0, funcs.len - 1)];
            try buf.appendSlice(allocator, func_call);
        },
        3 => {
            // Binary operations
            try buf.appendSlice(allocator, "platform.os == \"");
            const os_choices = [_][]const u8{ "linux", "macos", "windows" };
            try buf.appendSlice(allocator, os_choices[random.intRangeAtMost(usize, 0, 2)]);
            try buf.appendSlice(allocator, "\"");
        },
        4 => {
            // Logical operations
            const op = if (random.boolean()) " && " else " || ";
            try buf.appendSlice(allocator, "platform.is_linux");
            try buf.appendSlice(allocator, op);
            try buf.appendSlice(allocator, "env.CI == \"true\"");
        },
        5 => {
            // Malformed expressions
            const malformed = [_][]const u8{
                "file.exists(",
                "platform..os",
                "shell(\"",
                "env.",
                "runtime.iteration.invalid",
                "unknown_function()",
                "!!!&&&&||||",
                "\"unterminated",
            };
            const mal = malformed[random.intRangeAtMost(usize, 0, malformed.len - 1)];
            try buf.appendSlice(allocator, mal);
        },
        6 => {
            // Deeply nested expressions
            const depth = random.intRangeAtMost(usize, 1, 10);
            for (0..depth) |_| {
                try buf.appendSlice(allocator, "file.exists(");
            }
            try buf.appendSlice(allocator, "\"test.txt\"");
            for (0..depth) |_| {
                try buf.appendSlice(allocator, ")");
            }
        },
        else => unreachable,
    }

    return buf.toOwnedSlice(allocator);
}
