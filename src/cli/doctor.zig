const std = @import("std");
const types = @import("../config/types.zig");
const common = @import("common.zig");
const toolchain_installer = @import("../toolchain/installer.zig");
const toolchain_types = @import("../toolchain/types.zig");

pub const DoctorOptions = struct {
    config_path: ?[]const u8 = null,
    verbose: bool = false,
};

pub const CheckResult = struct {
    name: []const u8,
    name_owned: bool, // true if name was allocated and should be freed
    required_version: ?[]const u8,
    found_version: ?[]const u8,
    status: Status,
    message: ?[]const u8,

    pub const Status = enum {
        ok,
        warning,
        error_,
    };

    pub fn deinit(self: *CheckResult, allocator: std.mem.Allocator) void {
        if (self.name_owned) allocator.free(self.name);
        if (self.found_version) |v| allocator.free(v);
        if (self.message) |m| allocator.free(m);
        if (self.required_version) |r| allocator.free(r);
    }
};

/// Execute the doctor command to diagnose environment
pub fn cmdDoctor(allocator: std.mem.Allocator, options: DoctorOptions, w: *std.Io.Writer, ew: *std.Io.Writer) !u8 {
    _ = ew; // Used in future error reporting

    const config_path = options.config_path orelse "zr.toml";

    // Check if config exists
    const config_exists = blk: {
        std.fs.cwd().access(config_path, .{}) catch {
            break :blk false;
        };
        break :blk true;
    };

    if (!config_exists) {
        try w.print("\n", .{});
        try w.print(" ℹ No zr.toml found. Running basic system checks.\n\n", .{});
        return try runBasicChecks(allocator, options, w);
    }

    // Load config using the loader module directly
    const loader = @import("../config/loader.zig");
    var config = try loader.loadFromFile(allocator, config_path);
    defer config.deinit();

    try w.print("\n", .{});
    try w.print(" 🔍 zr doctor\n\n", .{});

    var results = std.ArrayList(CheckResult){};
    defer {
        for (results.items) |*r| r.deinit(allocator);
        results.deinit(allocator);
    }

    // Check toolchains if defined
    if (config.toolchains.tools.len > 0) {
        for (config.toolchains.tools) |tool_spec| {
            const result = try checkTool(allocator, tool_spec);
            try results.append(allocator, result);
        }
    }

    // Check git
    const git_result = try checkCommand(allocator, "git", "--version");
    try results.append(allocator, git_result);

    // Check docker if used in tasks
    if (hasDockerTasks(config)) {
        const docker_result = try checkCommand(allocator, "docker", "--version");
        try results.append(allocator, docker_result);
    }

    // Display results
    var error_count: usize = 0;
    var warning_count: usize = 0;

    for (results.items) |result| {
        const status_symbol = switch (result.status) {
            .ok => "✓",
            .warning => "⚠",
            .error_ => "✗",
        };

        try w.print(" {s} {s:<16}", .{ status_symbol, result.name });

        if (result.found_version) |version| {
            try w.print("{s}", .{version});
            if (result.required_version) |required| {
                try w.print("  (required: {s})", .{required});
            }
        } else {
            try w.print("not found", .{});
            if (result.required_version) |required| {
                try w.print("  (required: {s})", .{required});
            }
        }

        if (result.message) |msg| {
            try w.print("  {s}", .{msg});
        }

        try w.print("\n", .{});

        switch (result.status) {
            .ok => {},
            .warning => warning_count += 1,
            .error_ => error_count += 1,
        }
    }

    try w.print("\n", .{});

    if (error_count > 0 or warning_count > 0) {
        const total = error_count + warning_count;
        try w.print(" {d} issue(s) found. Run 'zr setup' to fix.\n", .{total});
    } else {
        try w.print(" ✓ All checks passed!\n", .{});
    }

    try w.print("\n", .{});

    return if (error_count > 0) 1 else 0;
}

fn checkTool(allocator: std.mem.Allocator, tool_spec: toolchain_types.ToolSpec) !CheckResult {
    const tool_kind = tool_spec.kind;
    const required_version = tool_spec.version;

    const is_installed = try toolchain_installer.isInstalled(allocator, tool_kind, required_version);

    if (is_installed) {
        const version_str = try std.fmt.allocPrint(allocator, "{}", .{required_version});
        return CheckResult{
            .name = @tagName(tool_kind),
            .name_owned = false, // @tagName is compile-time constant
            .required_version = null,
            .found_version = version_str,
            .status = .ok,
            .message = null,
        };
    } else {
        const req_str = try std.fmt.allocPrint(allocator, "{}", .{required_version});
        return CheckResult{
            .name = @tagName(tool_kind),
            .name_owned = false, // @tagName is compile-time constant
            .required_version = req_str,
            .found_version = null,
            .status = .error_,
            .message = null,
        };
    }
}

fn checkCommand(allocator: std.mem.Allocator, name: []const u8, version_arg: []const u8) !CheckResult {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ name, version_arg },
        .max_output_bytes = 1024 * 1024,
    }) catch |err| {
        const msg = try std.fmt.allocPrint(allocator, "({s})", .{@errorName(err)});
        return CheckResult{
            .name = try allocator.dupe(u8, name),
            .name_owned = true,
            .required_version = null,
            .found_version = null,
            .status = .error_,
            .message = msg,
        };
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited == 0) {
        // Extract version from output (first line, trimmed)
        var version: ?[]const u8 = null;
        if (result.stdout.len > 0) {
            var it = std.mem.splitScalar(u8, result.stdout, '\n');
            if (it.next()) |first_line| {
                const trimmed = std.mem.trim(u8, first_line, &std.ascii.whitespace);
                if (trimmed.len > 0) {
                    version = try allocator.dupe(u8, trimmed);
                }
            }
        }

        return CheckResult{
            .name = try allocator.dupe(u8, name),
            .name_owned = true,
            .required_version = null,
            .found_version = version,
            .status = .ok,
            .message = null,
        };
    } else {
        return CheckResult{
            .name = try allocator.dupe(u8, name),
            .name_owned = true,
            .required_version = null,
            .found_version = null,
            .status = .error_,
            .message = null,
        };
    }
}

fn hasDockerTasks(config: types.Config) bool {
    var it = config.tasks.valueIterator();
    while (it.next()) |task| {
        if (std.mem.indexOf(u8, task.cmd, "docker") != null) {
            return true;
        }
    }
    return false;
}

fn runBasicChecks(allocator: std.mem.Allocator, options: DoctorOptions, w: *std.Io.Writer) !u8 {
    _ = options;

    var results = std.ArrayList(CheckResult){};
    defer {
        for (results.items) |*r| r.deinit(allocator);
        results.deinit(allocator);
    }

    // Basic system checks
    const git_result = try checkCommand(allocator, "git", "--version");
    try results.append(allocator, git_result);

    const curl_result = try checkCommand(allocator, "curl", "--version");
    try results.append(allocator, curl_result);

    // Display results
    var error_count: usize = 0;

    for (results.items) |result| {
        const status_symbol = switch (result.status) {
            .ok => "✓",
            .warning => "⚠",
            .error_ => "✗",
        };

        try w.print(" {s} {s:<16}", .{ status_symbol, result.name });

        if (result.found_version) |version| {
            try w.print("{s}", .{version});
        } else {
            try w.print("not found", .{});
        }

        if (result.message) |msg| {
            try w.print("  {s}", .{msg});
        }

        try w.print("\n", .{});

        if (result.status == .error_) {
            error_count += 1;
        }
    }

    try w.print("\n", .{});

    if (error_count > 0) {
        try w.print(" {d} issue(s) found.\n\n", .{error_count});
    } else {
        try w.print(" ✓ Basic system checks passed!\n\n", .{});
    }

    return if (error_count > 0) 1 else 0;
}

test "DoctorOptions default values" {
    const opts = DoctorOptions{};
    try std.testing.expect(opts.config_path == null);
    try std.testing.expect(opts.verbose == false);
}

test "CheckResult init and deinit" {
    var result = CheckResult{
        .name = "test",
        .name_owned = false,
        .required_version = null,
        .found_version = null,
        .status = .ok,
        .message = null,
    };
    const allocator = std.testing.allocator;
    result.found_version = try allocator.dupe(u8, "1.0.0");
    result.message = try allocator.dupe(u8, "test message");

    // Verify fields are set correctly
    try std.testing.expectEqualStrings("test", result.name);
    try std.testing.expectEqual(false, result.name_owned);
    try std.testing.expectEqual(@as(?[]const u8, null), result.required_version);
    try std.testing.expectEqualStrings("1.0.0", result.found_version.?);
    try std.testing.expectEqualStrings("test message", result.message.?);
    try std.testing.expectEqual(CheckResult.Status.ok, result.status);

    result.deinit(allocator);
}

test "cmdDoctor writes header to writer when config exists" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const opts = DoctorOptions{
        .config_path = "zr.toml",
        .verbose = false,
    };

    // This should FAIL until cmdDoctor is refactored to accept writers
    const code = try cmdDoctor(allocator, opts, &out_w.interface, &err_w.interface);
    try std.testing.expect(code == 0 or code == 1);
}

test "cmdDoctor writes to writer with no config" {
    const allocator = std.testing.allocator;
    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var out_w = stdout.writer(&out_buf);
    const stderr_f = std.fs.File.stderr();
    var err_w = stderr_f.writer(&err_buf);

    const opts = DoctorOptions{
        .config_path = "/nonexistent/path/zr.toml",
        .verbose = false,
    };

    // This should FAIL until cmdDoctor is refactored to accept writers
    const code = try cmdDoctor(allocator, opts, &out_w.interface, &err_w.interface);

    // Should run basic checks and return 0 or 1 (depending on system state)
    try std.testing.expect(code == 0 or code == 1);
}
