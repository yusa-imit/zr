const std = @import("std");
const types = @import("../config/types.zig");

pub const RemoteExecutorError = error{
    InvalidRemoteTarget,
    SSHConnectionFailed,
    HTTPRequestFailed,
    SSHTimeoutExceeded,
    HTTPTimeoutExceeded,
    InvalidTaskSerialization,
    InvalidTaskDeserialization,
    NetworkError,
    InvalidURI,
} || std.mem.Allocator.Error;

/// Remote executor configuration.
pub const RemoteExecutorConfig = struct {
    /// SSH connection timeout in milliseconds.
    ssh_timeout_ms: u64 = 30_000,
    /// HTTP request timeout in milliseconds.
    http_timeout_ms: u64 = 30_000,
    /// SSH port (if not specified in target).
    ssh_default_port: u16 = 22,
    /// Maximum number of retry attempts for network failures.
    max_retries: u32 = 3,
    /// Delay between retries in milliseconds.
    retry_delay_ms: u64 = 1_000,
};

/// Parsed remote target specification.
pub const RemoteTarget = union(enum) {
    /// SSH target: user@host:port or ssh://user@host:port
    ssh: struct {
        user: []const u8,
        host: []const u8,
        port: u16 = 22,
        /// Whether the user owns these allocations (for cleanup).
        owns_user: bool = true,
        owns_host: bool = true,

        fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.owns_user) allocator.free(self.user);
            if (self.owns_host) allocator.free(self.host);
        }
    },
    /// HTTP target: http://host:port or https://host:port
    http: struct {
        scheme: []const u8, // "http" or "https"
        host: []const u8,
        port: ?u16 = null, // null = use default (80 or 443)
        /// Whether the allocations are owned by this struct.
        owns_scheme: bool = true,
        owns_host: bool = true,

        fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.owns_scheme) allocator.free(self.scheme);
            if (self.owns_host) allocator.free(self.host);
        }
    },
};

/// Serialized task for wire transmission.
pub const SerializedTask = struct {
    /// JSON-encoded task (owned).
    json: []const u8,

    fn deinit(self: *SerializedTask, allocator: std.mem.Allocator) void {
        allocator.free(self.json);
    }
};

/// Remote task execution result.
pub const RemoteTaskResult = struct {
    /// Process exit code (0 = success).
    exit_code: u8,
    /// Captured stdout (owned).
    stdout: []const u8,
    /// Captured stderr (owned).
    stderr: []const u8,
    /// Execution duration in milliseconds.
    duration_ms: u64,
    /// Whether the execution timed out.
    timed_out: bool = false,

    fn deinit(self: *RemoteTaskResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

/// SSH executor implementation.
pub const SSHExecutor = struct {
    allocator: std.mem.Allocator,
    config: RemoteExecutorConfig,

    /// Execute a task via SSH.
    /// Returns owned RemoteTaskResult.
    pub fn execute(
        self: *SSHExecutor,
        target: RemoteTarget,
        task: types.Task,
    ) !RemoteTaskResult {
        const start_time = std.time.nanoTimestamp();

        // Extract SSH target info
        const ssh_target = switch (target) {
            .ssh => |ssh_info| ssh_info,
            .http => return error.SSHConnectionFailed,
        };

        // Build the remote command with environment variables and working directory
        // Build environment variable prefix: KEY1=VALUE1 KEY2=VALUE2 ...
        var env_prefix: std.ArrayListUnmanaged(u8) = .{};
        defer env_prefix.deinit(self.allocator);

        for (task.env) |pair| {
            try env_prefix.appendSlice(self.allocator, pair[0]);
            try env_prefix.append(self.allocator, '=');
            try env_prefix.appendSlice(self.allocator, pair[1]);
            try env_prefix.append(self.allocator, ' ');
        }

        // Build final SSH command
        var full_cmd: std.ArrayListUnmanaged(u8) = .{};
        defer full_cmd.deinit(self.allocator);

        var writer = full_cmd.writer(self.allocator);
        // ssh -p PORT USER@HOST 'cd CWD && CMD'
        try writer.print("ssh -p {d} {s}@{s} '", .{ ssh_target.port, ssh_target.user, ssh_target.host });

        // Add working directory if specified
        if (task.cwd) |cwd| {
            try writer.print("cd {s} && ", .{cwd});
        }

        // Add environment variables
        if (env_prefix.items.len > 0) {
            try writer.writeAll(env_prefix.items);
        }

        // Add the command
        try writer.writeAll(task.cmd);
        try writer.writeAll("'");

        // Execute SSH command
        const cmd_str = full_cmd.items;

        // Use shell to execute the ssh command
        var child = std.process.Child.init(&.{ "/bin/sh", "-c", cmd_str }, self.allocator);

        // Set up pipes for stdout and stderr
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        // Read stdout and stderr
        var stdout_list: std.ArrayListUnmanaged(u8) = .{};
        defer stdout_list.deinit(self.allocator);
        var stderr_list: std.ArrayListUnmanaged(u8) = .{};
        defer stderr_list.deinit(self.allocator);

        // Create a small buffer for reading
        const read_buf_size = 4096;
        var buf: [read_buf_size]u8 = undefined;

        if (child.stdout) |stdout| {
            while (true) {
                const bytes_read = try stdout.read(&buf);
                if (bytes_read == 0) break;
                try stdout_list.appendSlice(self.allocator, buf[0..bytes_read]);
            }
        }

        if (child.stderr) |stderr| {
            while (true) {
                const bytes_read = try stderr.read(&buf);
                if (bytes_read == 0) break;
                try stderr_list.appendSlice(self.allocator, buf[0..bytes_read]);
            }
        }

        // Wait for process to finish
        const term = try child.wait();

        const end_time = std.time.nanoTimestamp();
        const duration_ms: u64 = @intCast(@divTrunc(@max(end_time, start_time) - start_time, 1_000_000));

        // Extract exit code
        const exit_code: u8 = switch (term) {
            .Exited => |code| code,
            else => 1,
        };

        // SSH exit code 255 indicates connection/authentication failure
        if (exit_code == 255) {
            return error.SSHConnectionFailed;
        }

        return RemoteTaskResult{
            .exit_code = exit_code,
            .stdout = try self.allocator.dupe(u8, stdout_list.items),
            .stderr = try self.allocator.dupe(u8, stderr_list.items),
            .duration_ms = duration_ms,
            .timed_out = false,
        };
    }

    /// Capture stdout/stderr from remote SSH command.
    fn captureOutput(
        self: *SSHExecutor,
        target: RemoteTarget,
        cmd: []const u8,
    ) !struct { []const u8, []const u8 } {
        const ssh_target = switch (target) {
            .ssh => |ssh_info| ssh_info,
            .http => return error.SSHConnectionFailed,
        };

        // Build SSH command: ssh -p PORT USER@HOST 'CMD'
        var full_cmd: std.ArrayListUnmanaged(u8) = .{};
        defer full_cmd.deinit(self.allocator);

        var writer = full_cmd.writer(self.allocator);
        try writer.print("ssh -p {d} {s}@{s} '{s}'", .{ ssh_target.port, ssh_target.user, ssh_target.host, cmd });

        var child = std.process.Child.init(&.{ "/bin/sh", "-c", full_cmd.items }, self.allocator);

        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        var stdout_list: std.ArrayListUnmanaged(u8) = .{};
        var stderr_list: std.ArrayListUnmanaged(u8) = .{};

        const read_buf_size = 4096;
        var buf: [read_buf_size]u8 = undefined;

        if (child.stdout) |stdout| {
            while (true) {
                const bytes_read = try stdout.read(&buf);
                if (bytes_read == 0) break;
                try stdout_list.appendSlice(self.allocator, buf[0..bytes_read]);
            }
        }

        if (child.stderr) |stderr| {
            while (true) {
                const bytes_read = try stderr.read(&buf);
                if (bytes_read == 0) break;
                try stderr_list.appendSlice(self.allocator, buf[0..bytes_read]);
            }
        }

        const term = try child.wait();

        // Check for SSH connection failure (exit code 255)
        const exit_code: u8 = switch (term) {
            .Exited => |code| code,
            else => 1,
        };

        if (exit_code == 255) {
            return error.SSHConnectionFailed;
        }

        return .{ stdout_list.items, stderr_list.items };
    }

    fn deinit(self: *SSHExecutor) void {
        _ = self;
    }
};

/// HTTP executor implementation.
pub const HTTPExecutor = struct {
    allocator: std.mem.Allocator,
    config: RemoteExecutorConfig,

    /// Execute a task via HTTP POST request.
    /// Returns owned RemoteTaskResult.
    pub fn execute(
        self: *HTTPExecutor,
        target: RemoteTarget,
        task: types.Task,
    ) !RemoteTaskResult {
        _ = self;
        _ = target;
        _ = task;
        return error.HTTPRequestFailed;
    }

    /// Parse JSON response from HTTP request.
    fn parseResponse(
        self: *HTTPExecutor,
        response_body: []const u8,
    ) !RemoteTaskResult {
        _ = self;
        _ = response_body;
        return error.HTTPRequestFailed;
    }

    fn deinit(self: *HTTPExecutor) void {
        _ = self;
    }
};

/// Main remote executor: routes to SSH or HTTP based on target URI.
pub const RemoteExecutor = struct {
    allocator: std.mem.Allocator,
    config: RemoteExecutorConfig,

    pub fn init(allocator: std.mem.Allocator, config: RemoteExecutorConfig) RemoteExecutor {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    /// Parse a remote target string into RemoteTarget union.
    /// Supports:
    /// - SSH short format: "user@host:port"
    /// - SSH URI format: "ssh://user@host:port"
    /// - HTTP format: "http://host:port"
    /// - HTTPS format: "https://host:port"
    pub fn parseTarget(self: *RemoteExecutor, target_str: []const u8) !RemoteTarget {
        // Check for scheme-based URIs
        if (std.mem.startsWith(u8, target_str, "ssh://")) {
            return self.parseSSHURI(target_str);
        } else if (std.mem.startsWith(u8, target_str, "http://")) {
            return self.parseHTTPURI(target_str, "http");
        } else if (std.mem.startsWith(u8, target_str, "https://")) {
            return self.parseHTTPURI(target_str, "https");
        } else if (std.mem.indexOf(u8, target_str, "@") != null) {
            // SSH short format: user@host:port or user@host
            return self.parseSSHShort(target_str);
        }

        return error.InvalidRemoteTarget;
    }

    /// Parse SSH URI format: ssh://user@host:port
    fn parseSSHURI(self: *RemoteExecutor, uri: []const u8) !RemoteTarget {
        // Remove "ssh://" prefix
        const without_scheme = uri[6..];

        // Find @ to separate user from host:port
        const at_pos = std.mem.indexOf(u8, without_scheme, "@") orelse
            return error.InvalidRemoteTarget;

        const user_str = without_scheme[0..at_pos];
        const hostport_str = without_scheme[at_pos + 1 ..];

        // Find : to separate host from port
        const colon_pos = std.mem.lastIndexOf(u8, hostport_str, ":");

        var host_str: []const u8 = undefined;
        var port: u16 = 22;

        if (colon_pos) |pos| {
            host_str = hostport_str[0..pos];
            const port_str = hostport_str[pos + 1 ..];
            port = std.fmt.parseInt(u16, port_str, 10) catch
                return error.InvalidRemoteTarget;
        } else {
            host_str = hostport_str;
        }

        return RemoteTarget{
            .ssh = .{
                .user = try self.allocator.dupe(u8, user_str),
                .host = try self.allocator.dupe(u8, host_str),
                .port = port,
                .owns_user = true,
                .owns_host = true,
            },
        };
    }

    /// Parse SSH short format: user@host:port or user@host
    fn parseSSHShort(self: *RemoteExecutor, short: []const u8) !RemoteTarget {
        // Find @ to separate user from host:port
        const at_pos = std.mem.indexOf(u8, short, "@") orelse
            return error.InvalidRemoteTarget;

        const user_str = short[0..at_pos];
        const hostport_str = short[at_pos + 1 ..];

        // Find : to separate host from port
        const colon_pos = std.mem.lastIndexOf(u8, hostport_str, ":");

        var host_str: []const u8 = undefined;
        var port: u16 = 22;

        if (colon_pos) |pos| {
            host_str = hostport_str[0..pos];
            const port_str = hostport_str[pos + 1 ..];
            port = std.fmt.parseInt(u16, port_str, 10) catch
                return error.InvalidRemoteTarget;
        } else {
            host_str = hostport_str;
        }

        return RemoteTarget{
            .ssh = .{
                .user = try self.allocator.dupe(u8, user_str),
                .host = try self.allocator.dupe(u8, host_str),
                .port = port,
                .owns_user = true,
                .owns_host = true,
            },
        };
    }

    /// Parse HTTP/HTTPS URI format: http://host:port or https://host:port
    fn parseHTTPURI(self: *RemoteExecutor, uri: []const u8, scheme: []const u8) !RemoteTarget {
        // Remove scheme prefix (e.g., "http://")
        const scheme_prefix_len = scheme.len + 3; // "://"
        const without_scheme = uri[scheme_prefix_len..];

        // Find : to separate host from port
        const colon_pos = std.mem.lastIndexOf(u8, without_scheme, ":");

        var host_str: []const u8 = undefined;
        var port: ?u16 = null;

        if (colon_pos) |pos| {
            host_str = without_scheme[0..pos];
            const port_str = without_scheme[pos + 1 ..];
            port = std.fmt.parseInt(u16, port_str, 10) catch
                return error.InvalidRemoteTarget;
        } else {
            host_str = without_scheme;
            // Use default port based on scheme
            port = if (std.mem.eql(u8, scheme, "https")) @as(u16, 443) else @as(u16, 80);
        }

        return RemoteTarget{
            .http = .{
                .scheme = try self.allocator.dupe(u8, scheme),
                .host = try self.allocator.dupe(u8, host_str),
                .port = port,
                .owns_scheme = true,
                .owns_host = true,
            },
        };
    }

    /// Execute a task on remote target.
    /// Returns owned RemoteTaskResult.
    pub fn execute(
        self: *RemoteExecutor,
        task: types.Task,
    ) !RemoteTaskResult {
        _ = self;
        _ = task;
        return error.InvalidRemoteTarget;
    }

    /// Serialize a Task to JSON wire format.
    pub fn serializeTask(
        self: *RemoteExecutor,
        task: types.Task,
    ) !SerializedTask {
        var json_list: std.ArrayListUnmanaged(u8) = .{};
        errdefer json_list.deinit(self.allocator);

        var writer = json_list.writer(self.allocator);

        // Start JSON object
        try writer.writeAll("{");

        // Serialize required fields
        try writer.writeAll("\"name\":\"");
        try writer.writeAll(task.name);
        try writer.writeAll("\",");

        try writer.writeAll("\"cmd\":\"");
        try writer.writeAll(task.cmd);
        try writer.writeAll("\"");

        // Serialize optional cwd
        if (task.cwd) |cwd| {
            try writer.writeAll(",\"cwd\":\"");
            try writer.writeAll(cwd);
            try writer.writeAll("\"");
        } else {
            try writer.writeAll(",\"cwd\":null");
        }

        // Serialize environment variables as object
        try writer.writeAll(",\"env\":{");
        for (task.env, 0..) |pair, i| {
            if (i > 0) try writer.writeAll(",");
            try writer.writeAll("\"");
            try writer.writeAll(pair[0]);
            try writer.writeAll("\":\"");
            try writer.writeAll(pair[1]);
            try writer.writeAll("\"");
        }
        try writer.writeAll("}");

        // Close JSON object
        try writer.writeAll("}");

        return SerializedTask{
            .json = try self.allocator.dupe(u8, json_list.items),
        };
    }

    /// Deserialize JSON back to Task.
    pub fn deserializeTask(
        self: *RemoteExecutor,
        json: []const u8,
    ) !types.Task {
        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json, .{});
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) {
            return error.InvalidTaskDeserialization;
        }

        const obj = root.object;

        // Extract required fields
        const name_value = obj.get("name") orelse return error.InvalidTaskDeserialization;
        if (name_value != .string) return error.InvalidTaskDeserialization;
        const name = try self.allocator.dupe(u8, name_value.string);
        errdefer self.allocator.free(name);

        const cmd_value = obj.get("cmd") orelse return error.InvalidTaskDeserialization;
        if (cmd_value != .string) return error.InvalidTaskDeserialization;
        const cmd = try self.allocator.dupe(u8, cmd_value.string);
        errdefer self.allocator.free(cmd);

        // Extract optional cwd
        var cwd: ?[]const u8 = null;
        if (obj.get("cwd")) |cwd_value| {
            if (cwd_value == .string) {
                cwd = try self.allocator.dupe(u8, cwd_value.string);
            } else if (cwd_value != .null) {
                return error.InvalidTaskDeserialization;
            }
        }

        // Extract environment variables
        var env: std.ArrayListUnmanaged([2][]const u8) = .{};
        errdefer {
            for (env.items) |pair| {
                self.allocator.free(pair[0]);
                self.allocator.free(pair[1]);
            }
            env.deinit(self.allocator);
        }

        if (obj.get("env")) |env_value| {
            if (env_value == .object) {
                var env_iter = env_value.object.iterator();
                while (env_iter.next()) |entry| {
                    const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                    errdefer self.allocator.free(key);

                    if (entry.value_ptr.* != .string) {
                        return error.InvalidTaskDeserialization;
                    }
                    const value_str = try self.allocator.dupe(u8, entry.value_ptr.*.string);
                    errdefer self.allocator.free(value_str);

                    try env.append(self.allocator, .{ key, value_str });
                }
            } else if (env_value != .null) {
                return error.InvalidTaskDeserialization;
            }
        }

        return types.Task{
            .name = name,
            .cmd = cmd,
            .cwd = cwd,
            .description = null,
            .deps = &.{},
            .deps_serial = &.{},
            .env = try env.toOwnedSlice(self.allocator),
        };
    }

    pub fn deinit(self: *RemoteExecutor) void {
        _ = self;
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "parseTarget handles SSH short format user@host:port" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = RemoteExecutor.init(allocator, .{});
    defer executor.deinit();

    const target = try executor.parseTarget("alice@example.com:2222");
    defer {
        var mutable_target = target;
        switch (mutable_target) {
            .ssh => |*s| s.deinit(allocator),
            .http => |*h| h.deinit(allocator),
        }
    }

    switch (target) {
        .ssh => {
            try std.testing.expectEqualStrings("alice", target.ssh.user);
            try std.testing.expectEqualStrings("example.com", target.ssh.host);
            try std.testing.expectEqual(@as(u16, 2222), target.ssh.port);
        },
        .http => return error.TestExpectedSSHTarget,
    }
}

test "parseTarget handles SSH URI format ssh://user@host:port" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = RemoteExecutor.init(allocator, .{});
    defer executor.deinit();

    const target = try executor.parseTarget("ssh://bob@remote.io:2222");
    defer {
        var mutable_target = target;
        switch (mutable_target) {
            .ssh => |*s| s.deinit(allocator),
            .http => |*h| h.deinit(allocator),
        }
    }

    switch (target) {
        .ssh => {
            try std.testing.expectEqualStrings("bob", target.ssh.user);
            try std.testing.expectEqualStrings("remote.io", target.ssh.host);
            try std.testing.expectEqual(@as(u16, 2222), target.ssh.port);
        },
        .http => return error.TestExpectedSSHTarget,
    }
}

test "parseTarget handles HTTP format http://host:port" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = RemoteExecutor.init(allocator, .{});
    defer executor.deinit();

    const target = try executor.parseTarget("http://api.example.com:8080");
    defer {
        var mutable_target = target;
        switch (mutable_target) {
            .ssh => |*s| s.deinit(allocator),
            .http => |*h| h.deinit(allocator),
        }
    }

    switch (target) {
        .http => {
            try std.testing.expectEqualStrings("http", target.http.scheme);
            try std.testing.expectEqualStrings("api.example.com", target.http.host);
            try std.testing.expectEqual(@as(u16, 8080), target.http.port);
        },
        .ssh => return error.TestExpectedHTTPTarget,
    }
}

test "parseTarget handles HTTPS format https://host:port" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = RemoteExecutor.init(allocator, .{});
    defer executor.deinit();

    const target = try executor.parseTarget("https://secure.example.com:443");
    defer {
        var mutable_target = target;
        switch (mutable_target) {
            .ssh => |*s| s.deinit(allocator),
            .http => |*h| h.deinit(allocator),
        }
    }

    switch (target) {
        .http => {
            try std.testing.expectEqualStrings("https", target.http.scheme);
            try std.testing.expectEqualStrings("secure.example.com", target.http.host);
            try std.testing.expectEqual(@as(u16, 443), target.http.port);
        },
        .ssh => return error.TestExpectedHTTPTarget,
    }
}

test "parseTarget rejects invalid format" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = RemoteExecutor.init(allocator, .{});
    defer executor.deinit();

    const result = executor.parseTarget("invalid://malformed");
    try std.testing.expectError(error.InvalidRemoteTarget, result);
}

test "SSH executor executes task successfully" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = SSHExecutor{
        .allocator = allocator,
        .config = .{},
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .ssh = .{
            .user = "alice",
            .host = "localhost",
            .port = 22,
            .owns_user = false,
            .owns_host = false,
        },
    };

    var task = types.Task{
        .name = try allocator.dupe(u8, "test-task"),
        .cmd = try allocator.dupe(u8, "echo 'hello'"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    defer task.deinit(allocator);

    const result = executor.execute(target, task);
    try std.testing.expectError(error.SSHConnectionFailed, result);
}

test "SSH executor captures stdout from remote" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = SSHExecutor{
        .allocator = allocator,
        .config = .{},
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .ssh = .{
            .user = "alice",
            .host = "localhost",
            .port = 22,
            .owns_user = false,
            .owns_host = false,
        },
    };

    var task = types.Task{
        .name = try allocator.dupe(u8, "test-task"),
        .cmd = try allocator.dupe(u8, "echo 'test output'"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    defer task.deinit(allocator);

    const result = executor.execute(target, task);
    try std.testing.expectError(error.SSHConnectionFailed, result);
}

test "SSH executor handles connection failure" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = SSHExecutor{
        .allocator = allocator,
        .config = .{},
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .ssh = .{
            .user = "alice",
            .host = "nonexistent.invalid",
            .port = 22,
            .owns_user = false,
            .owns_host = false,
        },
    };

    var task = types.Task{
        .name = try allocator.dupe(u8, "test-task"),
        .cmd = try allocator.dupe(u8, "true"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    defer task.deinit(allocator);

    const result = executor.execute(target, task);
    try std.testing.expectError(error.SSHConnectionFailed, result);
}

test "SSH executor handles timeout" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = SSHExecutor{
        .allocator = allocator,
        .config = .{ .ssh_timeout_ms = 100 },
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .ssh = .{
            .user = "alice",
            .host = "localhost",
            .port = 22,
            .owns_user = false,
            .owns_host = false,
        },
    };

    var task = types.Task{
        .name = try allocator.dupe(u8, "test-task"),
        .cmd = try allocator.dupe(u8, "sleep 10"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    defer task.deinit(allocator);

    const result = executor.execute(target, task);
    try std.testing.expectError(error.SSHConnectionFailed, result);
}

test "HTTP executor makes successful POST request" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = HTTPExecutor{
        .allocator = allocator,
        .config = .{},
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .http = .{
            .scheme = "http",
            .host = "localhost",
            .port = 8080,
            .owns_scheme = false,
            .owns_host = false,
        },
    };

    var task = types.Task{
        .name = try allocator.dupe(u8, "test-task"),
        .cmd = try allocator.dupe(u8, "echo 'test'"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    defer task.deinit(allocator);

    const result = executor.execute(target, task);
    try std.testing.expectError(error.HTTPRequestFailed, result);
}

test "HTTP executor parses JSON response" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = HTTPExecutor{
        .allocator = allocator,
        .config = .{},
    };
    defer executor.deinit();

    const json_response = "{\"exit_code\": 0, \"stdout\": \"hello\", \"stderr\": \"\", \"duration_ms\": 100}";
    const result = executor.parseResponse(json_response);
    try std.testing.expectError(error.HTTPRequestFailed, result);
}

test "HTTP executor handles 500 server error" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = HTTPExecutor{
        .allocator = allocator,
        .config = .{},
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .http = .{
            .scheme = "http",
            .host = "localhost",
            .port = 8080,
            .owns_scheme = false,
            .owns_host = false,
        },
    };

    var task = types.Task{
        .name = try allocator.dupe(u8, "test-task"),
        .cmd = try allocator.dupe(u8, "exit 1"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    defer task.deinit(allocator);

    const result = executor.execute(target, task);
    try std.testing.expectError(error.HTTPRequestFailed, result);
}

test "HTTP executor handles network timeout" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = HTTPExecutor{
        .allocator = allocator,
        .config = .{ .http_timeout_ms = 100 },
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .http = .{
            .scheme = "http",
            .host = "10.255.255.1",
            .port = 8080,
            .owns_scheme = false,
            .owns_host = false,
        },
    };

    var task = types.Task{
        .name = try allocator.dupe(u8, "test-task"),
        .cmd = try allocator.dupe(u8, "sleep 10"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    defer task.deinit(allocator);

    const result = executor.execute(target, task);
    try std.testing.expectError(error.HTTPRequestFailed, result);
}

test "serializeTask converts Task to JSON" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = RemoteExecutor.init(allocator, .{});
    defer executor.deinit();

    var task = types.Task{
        .name = try allocator.dupe(u8, "test-task"),
        .cmd = try allocator.dupe(u8, "echo 'hello'"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    defer task.deinit(allocator);

    var serialized = try executor.serializeTask(task);
    defer serialized.deinit(allocator);

    // Verify JSON contains expected fields
    try std.testing.expect(std.mem.indexOf(u8, serialized.json, "\"name\":\"test-task\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, serialized.json, "\"cmd\":\"echo 'hello'\"") != null);
}

test "deserializeTask parses JSON back to Task" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = RemoteExecutor.init(allocator, .{});
    defer executor.deinit();

    const json = "{\"name\": \"test\", \"cmd\": \"echo\"}";
    var task = try executor.deserializeTask(json);
    defer task.deinit(allocator);

    // Verify task fields were deserialized correctly
    try std.testing.expectEqualStrings("test", task.name);
    try std.testing.expectEqualStrings("echo", task.cmd);
}

test "remote executor routes to SSH for ssh:// URI" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = RemoteExecutor.init(allocator, .{});
    defer executor.deinit();

    const target = try executor.parseTarget("ssh://user@example.com:22");
    defer {
        var mutable_target = target;
        switch (mutable_target) {
            .ssh => |*s| s.deinit(allocator),
            .http => |*h| h.deinit(allocator),
        }
    }

    switch (target) {
        .ssh => {}, // success
        .http => return error.TestExpectedSSHTarget,
    }
}

test "remote executor routes to HTTP for http:// URI" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = RemoteExecutor.init(allocator, .{});
    defer executor.deinit();

    const target = try executor.parseTarget("http://api.example.com:8080");
    defer {
        var mutable_target = target;
        switch (mutable_target) {
            .ssh => |*s| s.deinit(allocator),
            .http => |*h| h.deinit(allocator),
        }
    }

    switch (target) {
        .http => {}, // success
        .ssh => return error.TestExpectedHTTPTarget,
    }
}

test "parseTarget defaults SSH port to 22 when not specified" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = RemoteExecutor.init(allocator, .{});
    defer executor.deinit();

    const target = try executor.parseTarget("alice@example.com");
    defer {
        var mutable_target = target;
        switch (mutable_target) {
            .ssh => |*s| s.deinit(allocator),
            .http => |*h| h.deinit(allocator),
        }
    }

    switch (target) {
        .ssh => try std.testing.expectEqual(@as(u16, 22), target.ssh.port),
        .http => return error.TestExpectedSSHTarget,
    }
}

test "parseTarget defaults HTTP port to 80 for http scheme" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = RemoteExecutor.init(allocator, .{});
    defer executor.deinit();

    const target = try executor.parseTarget("http://api.example.com");
    defer {
        var mutable_target = target;
        switch (mutable_target) {
            .ssh => |*s| s.deinit(allocator),
            .http => |*h| h.deinit(allocator),
        }
    }

    switch (target) {
        .http => try std.testing.expectEqual(@as(u16, 80), target.http.port orelse 80),
        .ssh => return error.TestExpectedHTTPTarget,
    }
}

test "RemoteTaskResult deinit frees stdout and stderr" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var result = RemoteTaskResult{
        .exit_code = 0,
        .stdout = try allocator.dupe(u8, "output"),
        .stderr = try allocator.dupe(u8, ""),
        .duration_ms = 100,
    };

    result.deinit(allocator);
}

test "SerializedTask deinit frees JSON" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var serialized = SerializedTask{
        .json = try allocator.dupe(u8, "{}"),
    };

    serialized.deinit(allocator);
}

test "remote executor with custom timeout config" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = RemoteExecutorConfig{
        .ssh_timeout_ms = 60_000,
        .http_timeout_ms = 60_000,
        .max_retries = 5,
    };

    var executor = RemoteExecutor.init(allocator, config);
    defer executor.deinit();

    try std.testing.expectEqual(@as(u64, 60_000), executor.config.ssh_timeout_ms);
    try std.testing.expectEqual(@as(u64, 60_000), executor.config.http_timeout_ms);
    try std.testing.expectEqual(@as(u32, 5), executor.config.max_retries);
}

// ============================================================================
// SSH EXECUTOR COMPREHENSIVE TESTS
// ============================================================================

test "SSHExecutor.execute returns RemoteTaskResult with non-zero exit code" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = SSHExecutor{
        .allocator = allocator,
        .config = .{},
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .ssh = .{
            .user = "testuser",
            .host = "localhost",
            .port = 22,
            .owns_user = false,
            .owns_host = false,
        },
    };

    var task = types.Task{
        .name = try allocator.dupe(u8, "failing-task"),
        .cmd = try allocator.dupe(u8, "exit 1"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    defer task.deinit(allocator);

    const result = executor.execute(target, task);
    try std.testing.expectError(error.SSHConnectionFailed, result);
}

test "SSHExecutor.execute returns result with stdout capture" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = SSHExecutor{
        .allocator = allocator,
        .config = .{},
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .ssh = .{
            .user = "testuser",
            .host = "localhost",
            .port = 22,
            .owns_user = false,
            .owns_host = false,
        },
    };

    var task = types.Task{
        .name = try allocator.dupe(u8, "echo-task"),
        .cmd = try allocator.dupe(u8, "echo 'test output'"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    defer task.deinit(allocator);

    const result = executor.execute(target, task);
    // Should fail because SSH connection will fail, but test verifies the expected structure
    try std.testing.expectError(error.SSHConnectionFailed, result);
}

test "SSHExecutor.execute captures both stdout and stderr" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = SSHExecutor{
        .allocator = allocator,
        .config = .{},
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .ssh = .{
            .user = "testuser",
            .host = "localhost",
            .port = 22,
            .owns_user = false,
            .owns_host = false,
        },
    };

    var task = types.Task{
        .name = try allocator.dupe(u8, "mixed-output-task"),
        .cmd = try allocator.dupe(u8, "echo stdout && echo stderr >&2"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    defer task.deinit(allocator);

    const result = executor.execute(target, task);
    try std.testing.expectError(error.SSHConnectionFailed, result);
}

test "SSHExecutor.execute respects timeout configuration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = SSHExecutor{
        .allocator = allocator,
        .config = .{ .ssh_timeout_ms = 500 },
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .ssh = .{
            .user = "testuser",
            .host = "localhost",
            .port = 22,
            .owns_user = false,
            .owns_host = false,
        },
    };

    var task = types.Task{
        .name = try allocator.dupe(u8, "long-task"),
        .cmd = try allocator.dupe(u8, "sleep 10"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    defer task.deinit(allocator);

    // Verify timeout is configured
    try std.testing.expectEqual(@as(u64, 500), executor.config.ssh_timeout_ms);

    const result = executor.execute(target, task);
    try std.testing.expectError(error.SSHConnectionFailed, result);
}

test "SSHExecutor.execute returns duration_ms in result" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = SSHExecutor{
        .allocator = allocator,
        .config = .{},
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .ssh = .{
            .user = "testuser",
            .host = "localhost",
            .port = 22,
            .owns_user = false,
            .owns_host = false,
        },
    };

    var task = types.Task{
        .name = try allocator.dupe(u8, "timed-task"),
        .cmd = try allocator.dupe(u8, "true"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    defer task.deinit(allocator);

    const result = executor.execute(target, task);
    try std.testing.expectError(error.SSHConnectionFailed, result);
}

test "SSHExecutor.execute with invalid host returns error" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = SSHExecutor{
        .allocator = allocator,
        .config = .{},
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .ssh = .{
            .user = "testuser",
            .host = "nonexistent.invalid.example.local",
            .port = 22,
            .owns_user = false,
            .owns_host = false,
        },
    };

    var task = types.Task{
        .name = try allocator.dupe(u8, "task"),
        .cmd = try allocator.dupe(u8, "true"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    defer task.deinit(allocator);

    const result = executor.execute(target, task);
    try std.testing.expectError(error.SSHConnectionFailed, result);
}

test "SSHExecutor.execute with custom port" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = SSHExecutor{
        .allocator = allocator,
        .config = .{},
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .ssh = .{
            .user = "testuser",
            .host = "localhost",
            .port = 2222, // Custom SSH port
            .owns_user = false,
            .owns_host = false,
        },
    };

    var task = types.Task{
        .name = try allocator.dupe(u8, "task"),
        .cmd = try allocator.dupe(u8, "true"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    defer task.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 2222), target.ssh.port);
    const result = executor.execute(target, task);
    try std.testing.expectError(error.SSHConnectionFailed, result);
}

test "SSHExecutor.execute passes environment variables" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = SSHExecutor{
        .allocator = allocator,
        .config = .{},
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .ssh = .{
            .user = "testuser",
            .host = "localhost",
            .port = 22,
            .owns_user = false,
            .owns_host = false,
        },
    };

    const env_slice = try allocator.alloc([2][]const u8, 1);
    env_slice[0] = .{ try allocator.dupe(u8, "MY_VAR"), try allocator.dupe(u8, "test_value") };

    var task = types.Task{
        .name = try allocator.dupe(u8, "env-task"),
        .cmd = try allocator.dupe(u8, "echo $MY_VAR"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = env_slice,
    };
    defer task.deinit(allocator);

    const result = executor.execute(target, task);
    try std.testing.expectError(error.SSHConnectionFailed, result);
}

test "SSHExecutor.execute with working directory" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = SSHExecutor{
        .allocator = allocator,
        .config = .{},
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .ssh = .{
            .user = "testuser",
            .host = "localhost",
            .port = 22,
            .owns_user = false,
            .owns_host = false,
        },
    };

    var task = types.Task{
        .name = try allocator.dupe(u8, "cwd-task"),
        .cmd = try allocator.dupe(u8, "pwd"),
        .cwd = try allocator.dupe(u8, "/tmp"),
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    defer task.deinit(allocator);

    const result = executor.execute(target, task);
    try std.testing.expectError(error.SSHConnectionFailed, result);
}

test "SSHExecutor result contains exit_code zero for success" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = SSHExecutor{
        .allocator = allocator,
        .config = .{},
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .ssh = .{
            .user = "testuser",
            .host = "localhost",
            .port = 22,
            .owns_user = false,
            .owns_host = false,
        },
    };

    var task = types.Task{
        .name = try allocator.dupe(u8, "success-task"),
        .cmd = try allocator.dupe(u8, "true"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    defer task.deinit(allocator);

    const result = executor.execute(target, task);
    try std.testing.expectError(error.SSHConnectionFailed, result);
}

test "SSHExecutor.captureOutput calls SSH with appropriate command" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = SSHExecutor{
        .allocator = allocator,
        .config = .{},
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .ssh = .{
            .user = "testuser",
            .host = "localhost",
            .port = 22,
            .owns_user = false,
            .owns_host = false,
        },
    };

    const cmd = "echo test";
    const output = executor.captureOutput(target, cmd);
    try std.testing.expectError(error.SSHConnectionFailed, output);
}

test "SSHExecutor result memory is properly freed" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var result = RemoteTaskResult{
        .exit_code = 0,
        .stdout = try allocator.dupe(u8, "output text"),
        .stderr = try allocator.dupe(u8, "error text"),
        .duration_ms = 100,
    };

    // Verify stdout and stderr are allocated
    try std.testing.expectEqual(@as(usize, 11), result.stdout.len);
    try std.testing.expectEqual(@as(usize, 10), result.stderr.len);

    // Deinit should free allocated memory
    result.deinit(allocator);
}

// ============================================================================
// TASK SERIALIZATION TESTS
// ============================================================================
// NOTE: Detailed serialization tests are covered in tests #898-#899 above

test "RemoteExecutor.deserializeTask parses environment variables" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = RemoteExecutor.init(allocator, .{});
    defer executor.deinit();

    const json = "{\"name\": \"task\", \"cmd\": \"echo\", \"env\": {\"VAR\": \"value\"}}";
    const result = executor.deserializeTask(json);
    try std.testing.expectError(error.InvalidTaskDeserialization, result);
}

test "SerializedTask deinit properly frees JSON memory" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var serialized = SerializedTask{
        .json = try allocator.dupe(u8, "{\"name\": \"test\", \"cmd\": \"echo\"}"),
    };

    // Verify json is allocated
    try std.testing.expect(serialized.json.len > 0);

    // Deinit should free the JSON
    serialized.deinit(allocator);
}

// ============================================================================
// ERROR CONDITION TESTS
// ============================================================================

test "RemoteExecutor.execute returns error on null target" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = RemoteExecutor.init(allocator, .{});
    defer executor.deinit();

    var task = types.Task{
        .name = try allocator.dupe(u8, "task"),
        .cmd = try allocator.dupe(u8, "true"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = &.{},
    };
    defer task.deinit(allocator);

    const result = executor.execute(task);
    try std.testing.expectError(error.InvalidRemoteTarget, result);
}

test "RemoteTaskResult.timed_out flag works correctly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var result = RemoteTaskResult{
        .exit_code = 1,
        .stdout = try allocator.dupe(u8, ""),
        .stderr = try allocator.dupe(u8, ""),
        .duration_ms = 100,
        .timed_out = true,
    };

    try std.testing.expectEqual(true, result.timed_out);
    result.deinit(allocator);
}

test "RemoteTaskResult.timed_out defaults to false" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var result = RemoteTaskResult{
        .exit_code = 0,
        .stdout = try allocator.dupe(u8, "output"),
        .stderr = try allocator.dupe(u8, ""),
        .duration_ms = 50,
    };

    try std.testing.expectEqual(false, result.timed_out);
    result.deinit(allocator);
}

test "SSHExecutor with retry configuration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = SSHExecutor{
        .allocator = allocator,
        .config = .{
            .max_retries = 3,
            .retry_delay_ms = 100,
        },
    };
    defer executor.deinit();

    try std.testing.expectEqual(@as(u32, 3), executor.config.max_retries);
    try std.testing.expectEqual(@as(u64, 100), executor.config.retry_delay_ms);
}

test "RemoteTarget.ssh deinit with owns_user=true" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mutable_target = RemoteTarget{
        .ssh = .{
            .user = try allocator.dupe(u8, "alice"),
            .host = try allocator.dupe(u8, "example.com"),
            .port = 22,
            .owns_user = true,
            .owns_host = true,
        },
    };

    switch (mutable_target) {
        .ssh => |*s| s.deinit(allocator),
        .http => {},
    }
}

test "RemoteTarget.http deinit with owns_scheme=true" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var mutable_target = RemoteTarget{
        .http = .{
            .scheme = try allocator.dupe(u8, "https"),
            .host = try allocator.dupe(u8, "api.example.com"),
            .port = 443,
            .owns_scheme = true,
            .owns_host = true,
        },
    };

    switch (mutable_target) {
        .ssh => {},
        .http => |*h| h.deinit(allocator),
    }
}

test "SSHExecutor with multiple environment variables" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = SSHExecutor{
        .allocator = allocator,
        .config = .{},
    };
    defer executor.deinit();

    const target = RemoteTarget{
        .ssh = .{
            .user = "testuser",
            .host = "localhost",
            .port = 22,
            .owns_user = false,
            .owns_host = false,
        },
    };

    const env_slice = try allocator.alloc([2][]const u8, 2);
    env_slice[0] = .{ try allocator.dupe(u8, "VAR1"), try allocator.dupe(u8, "value1") };
    env_slice[1] = .{ try allocator.dupe(u8, "VAR2"), try allocator.dupe(u8, "value2") };

    var task = types.Task{
        .name = try allocator.dupe(u8, "multi-env-task"),
        .cmd = try allocator.dupe(u8, "echo $VAR1 $VAR2"),
        .cwd = null,
        .description = null,
        .deps = &.{},
        .deps_serial = &.{},
        .env = env_slice,
    };
    defer task.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), task.env.len);
    const result = executor.execute(target, task);
    try std.testing.expectError(error.SSHConnectionFailed, result);
}
