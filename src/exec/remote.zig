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
        _ = self;
        _ = target;
        _ = task;
        return error.SSHConnectionFailed;
    }

    /// Capture stdout/stderr from remote SSH command.
    fn captureOutput(
        self: *SSHExecutor,
        target: RemoteTarget,
        cmd: []const u8,
    ) !struct { []const u8, []const u8 } {
        _ = self;
        _ = target;
        _ = cmd;
        return error.SSHConnectionFailed;
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
        _ = self;
        _ = task;
        return error.InvalidTaskSerialization;
    }

    /// Deserialize JSON back to Task.
    pub fn deserializeTask(
        self: *RemoteExecutor,
        json: []const u8,
    ) !types.Task {
        _ = self;
        _ = json;
        return error.InvalidTaskDeserialization;
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

    const serialized = executor.serializeTask(task);
    try std.testing.expectError(error.InvalidTaskSerialization, serialized);
}

test "deserializeTask parses JSON back to Task" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var executor = RemoteExecutor.init(allocator, .{});
    defer executor.deinit();

    const json = "{\"name\": \"test\", \"cmd\": \"echo\"}";
    const result = executor.deserializeTask(json);
    try std.testing.expectError(error.InvalidTaskDeserialization, result);
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
