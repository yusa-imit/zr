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
pub fn cmdDoctor(allocator: std.mem.Allocator, options: DoctorOptions) !u8 {
    const config_path = options.config_path orelse "zr.toml";

    // Check if config exists
    const config_exists = blk: {
        std.fs.cwd().access(config_path, .{}) catch {
            break :blk false;
        };
        break :blk true;
    };

    if (!config_exists) {
        std.debug.print("\n", .{});
        std.debug.print(" ℹ No zr.toml found. Running basic system checks.\n\n", .{});
        return try runBasicChecks(allocator, options);
    }

    // Load config using the loader module directly
    const loader = @import("../config/loader.zig");
    var config = try loader.loadFromFile(allocator, config_path);
    defer config.deinit();

    std.debug.print("\n", .{});
    std.debug.print(" 🔍 zr doctor\n\n", .{});

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

        std.debug.print(" {s} {s:<16}", .{ status_symbol, result.name });

        if (result.found_version) |version| {
            std.debug.print("{s}", .{version});
            if (result.required_version) |required| {
                std.debug.print("  (required: {s})", .{required});
            }
        } else {
            std.debug.print("not found", .{});
            if (result.required_version) |required| {
                std.debug.print("  (required: {s})", .{required});
            }
        }

        if (result.message) |msg| {
            std.debug.print("  {s}", .{msg});
        }

        std.debug.print("\n", .{});

        switch (result.status) {
            .ok => {},
            .warning => warning_count += 1,
            .error_ => error_count += 1,
        }
    }

    std.debug.print("\n", .{});

    if (error_count > 0 or warning_count > 0) {
        const total = error_count + warning_count;
        std.debug.print(" {d} issue(s) found. Run 'zr setup' to fix.\n", .{total});
    } else {
        std.debug.print(" ✓ All checks passed!\n", .{});
    }

    std.debug.print("\n", .{});

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

fn runBasicChecks(allocator: std.mem.Allocator, options: DoctorOptions) !u8 {
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

        std.debug.print(" {s} {s:<16}", .{ status_symbol, result.name });

        if (result.found_version) |version| {
            std.debug.print("{s}", .{version});
        } else {
            std.debug.print("not found", .{});
        }

        if (result.message) |msg| {
            std.debug.print("  {s}", .{msg});
        }

        std.debug.print("\n", .{});

        if (result.status == .error_) {
            error_count += 1;
        }
    }

    std.debug.print("\n", .{});

    if (error_count > 0) {
        std.debug.print(" {d} issue(s) found.\n\n", .{error_count});
    } else {
        std.debug.print(" ✓ Basic system checks passed!\n\n", .{});
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
    result.deinit(allocator);
}
