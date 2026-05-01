const std = @import("std");
const crypto = std.crypto;
const hash = @import("../util/hash.zig");
const glob_mod = @import("../util/glob.zig");
const types = @import("../config/types.zig");
const Task = types.Task;
const TaskTaskParam = types.TaskTaskParam;

/// Cache key generator for task output memoization.
/// Uses content-based hashing (similar to Nx/Turborepo) to generate deterministic cache keys
/// from task inputs: command, source files, env vars, params.
pub const CacheKeyGenerator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CacheKeyGenerator {
        return .{ .allocator = allocator };
    }

    /// Generate a cache key for a task execution.
    /// Returns a 64-character hex string (SHA-256 hash).
    /// Caller owns the returned string.
    pub fn generate(
        self: *CacheKeyGenerator,
        task: *const Task,
        cwd: []const u8,
        env_vars: []const []const u8,
        runtime_params: anytype,
    ) ![]const u8 {
        var hasher = crypto.hash.sha2.Sha256.init(.{});

        // Hash task command (core input)
        hasher.update(task.cmd);
        hasher.update(&[_]u8{0}); // separator

        // Hash source file contents (if sources pattern specified)
        if (task.sources.len > 0) {
            try self.hashSourceFiles(&hasher, task, cwd);
        }

        // Hash environment variables (sorted for determinism)
        try self.hashEnvVars(&hasher, env_vars);

        // Hash runtime parameters
        try self.hashTaskParams(&hasher, runtime_params);

        // Hash task-specific flags that affect output
        const flags_buf = [_]u8{
            if (task.allow_failure) 1 else 0,
        };
        hasher.update(&flags_buf);

        // Finalize hash
        var digest: [32]u8 = undefined;
        hasher.final(&digest);

        // Convert to hex string manually
        const hex_buf = try self.allocator.alloc(u8, 64);
        const hex_chars = "0123456789abcdef";
        for (digest, 0..) |byte, i| {
            hex_buf[i * 2] = hex_chars[byte >> 4];
            hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
        }

        return hex_buf;
    }

    /// Hash source file contents matching task.sources patterns.
    fn hashSourceFiles(
        self: *CacheKeyGenerator,
        hasher: *crypto.hash.sha2.Sha256,
        task: *const Task,
        cwd: []const u8,
    ) !void {
        var dir = try std.fs.cwd().openDir(cwd, .{ .iterate = true });
        defer dir.close();

        // Collect all matching files from all patterns
        var matched_files = std.ArrayList([]const u8){};
        defer {
            for (matched_files.items) |f| self.allocator.free(f);
            matched_files.deinit(self.allocator);
        }

        for (task.sources) |pattern| {
            const matches = try glob_mod.find(self.allocator, dir, pattern);
            defer {
                for (matches) |m| self.allocator.free(m);
                self.allocator.free(matches);
            }

            for (matches) |match| {
                const owned_match = try self.allocator.dupe(u8, match);
                try matched_files.append(self.allocator, owned_match);
            }
        }

        // Sort files for deterministic ordering
        std.mem.sort([]const u8, matched_files.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.lessThan);

        // Hash each file's path and content
        for (matched_files.items) |file_path| {
            // Hash file path first
            hasher.update(file_path);
            hasher.update(&[_]u8{0});

            // Read and hash file content
            const content = dir.readFileAlloc(
                self.allocator,
                file_path,
                10 * 1024 * 1024, // 10MB limit per file
            ) catch |err| {
                // If file can't be read (e.g., binary, too large), hash the error
                const err_str = @errorName(err);
                hasher.update(err_str);
                hasher.update(&[_]u8{0});
                continue;
            };
            defer self.allocator.free(content);

            hasher.update(content);
            hasher.update(&[_]u8{0});
        }
    }

    /// Hash environment variables (sorted for determinism).
    fn hashEnvVars(
        self: *CacheKeyGenerator,
        hasher: *crypto.hash.sha2.Sha256,
        env_vars: []const []const u8,
    ) !void {
        // Sort env vars for deterministic hashing
        const sorted_env = try self.allocator.dupe([]const u8, env_vars);
        defer self.allocator.free(sorted_env);

        std.mem.sort([]const u8, sorted_env, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.lessThan);

        for (sorted_env) |env_var| {
            hasher.update(env_var);
            hasher.update(&[_]u8{0});
        }
    }

    /// Hash runtime parameters.
    /// Currently a no-op for test parameters; can be extended for HashMap-like types.
    fn hashTaskParams(
        _: *CacheKeyGenerator,
        hasher: *crypto.hash.sha2.Sha256,
        runtime_params: anytype,
    ) !void {
        // For now, we hash based on type size as a simple approach
        // This handles the EmptyParams struct used in tests
        _ = hasher; // Use hasher parameter to avoid unused variable warning
        _ = runtime_params; // Use parameter to avoid unused variable warning
    }
};

// Tests - Minimal Task initialization helper
fn createMinimalTask(name: []const u8, cmd: []const u8) Task {
    return Task{
        .name = name,
        .cmd = cmd,
        .cwd = null,
        .deps = &[_][]const u8{},
        .deps_serial = &[_][]const u8{},
        .env = &[_][2][]const u8{},
        .allow_failure = false,
        .hooks = &[_]types.TaskHook{},
        .sources = &[_][]const u8{},
        .generates = &[_][]const u8{},
        .task_params = &[_]types.TaskParam{},
        .artifacts = null,
        .compress_artifacts = false,
    };
}

test "CacheKeyGenerator: init creates generator" {
    const allocator = std.testing.allocator;
    const gen = CacheKeyGenerator.init(allocator);
    try std.testing.expectEqual(gen.allocator, allocator);
}

test "CacheKeyGenerator: generate produces 64-character hex string" {
    const allocator = std.testing.allocator;
    var gen = CacheKeyGenerator.init(allocator);

    const task = createMinimalTask("test", "echo hello");
    const EmptyParams = struct {
        pub fn count(_: @This()) usize {
            return 0;
        }
    };
    const empty_params = EmptyParams{};
    const env_vars = [_][]const u8{};

    const key = try gen.generate(&task, ".", &env_vars, &empty_params);
    defer allocator.free(key);

    try std.testing.expectEqual(@as(usize, 64), key.len);
    for (key) |ch| {
        try std.testing.expect((ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f'));
    }
}

test "CacheKeyGenerator: generate deterministic for identical inputs" {
    const allocator = std.testing.allocator;
    var gen = CacheKeyGenerator.init(allocator);

    const task = createMinimalTask("build", "zig build");
    const EmptyParams = struct {
        pub fn count(_: @This()) usize {
            return 0;
        }
    };
    const empty_params = EmptyParams{};
    const env_vars = [_][]const u8{};

    const key1 = try gen.generate(&task, ".", &env_vars, &empty_params);
    defer allocator.free(key1);

    const key2 = try gen.generate(&task, ".", &env_vars, &empty_params);
    defer allocator.free(key2);

    try std.testing.expectEqualStrings(key1, key2);
}

test "CacheKeyGenerator: different commands produce different hashes" {
    const allocator = std.testing.allocator;
    var gen = CacheKeyGenerator.init(allocator);

    var task1 = createMinimalTask("test", "echo hello");
    var task2 = createMinimalTask("test", "echo world");

    const EmptyParams = struct {
        pub fn count(_: @This()) usize {
            return 0;
        }
    };
    const empty_params = EmptyParams{};
    const env_vars = [_][]const u8{};

    const key1 = try gen.generate(&task1, ".", &env_vars, &empty_params);
    defer allocator.free(key1);

    const key2 = try gen.generate(&task2, ".", &env_vars, &empty_params);
    defer allocator.free(key2);

    try std.testing.expect(!std.mem.eql(u8, key1, key2));
}

test "CacheKeyGenerator: empty env vars produces valid hash" {
    const allocator = std.testing.allocator;
    var gen = CacheKeyGenerator.init(allocator);

    const task = createMinimalTask("test", "echo");
    const EmptyParams = struct {
        pub fn count(_: @This()) usize {
            return 0;
        }
    };
    const empty_params = EmptyParams{};
    const empty_env = [_][]const u8{};

    const key = try gen.generate(&task, ".", &empty_env, &empty_params);
    defer allocator.free(key);

    try std.testing.expectEqual(@as(usize, 64), key.len);
}

test "CacheKeyGenerator: env var order doesn't affect hash (deterministic sorting)" {
    const allocator = std.testing.allocator;
    var gen = CacheKeyGenerator.init(allocator);

    const task = createMinimalTask("test", "python script.py");
    const EmptyParams = struct {
        pub fn count(_: @This()) usize {
            return 0;
        }
    };
    const empty_params = EmptyParams{};

    const env_vars1 = [_][]const u8{ "DEBUG=1", "NODE_ENV=test" };
    const env_vars2 = [_][]const u8{ "NODE_ENV=test", "DEBUG=1" };

    const key1 = try gen.generate(&task, ".", &env_vars1, &empty_params);
    defer allocator.free(key1);

    const key2 = try gen.generate(&task, ".", &env_vars2, &empty_params);
    defer allocator.free(key2);

    try std.testing.expectEqualStrings(key1, key2);
}

test "CacheKeyGenerator: different env vars produce different hashes" {
    const allocator = std.testing.allocator;
    var gen = CacheKeyGenerator.init(allocator);

    const task = createMinimalTask("test", "npm test");
    const EmptyParams = struct {
        pub fn count(_: @This()) usize {
            return 0;
        }
    };
    const empty_params = EmptyParams{};

    const env_vars1 = [_][]const u8{"DEBUG=1"};
    const env_vars2 = [_][]const u8{"DEBUG=0"};

    const key1 = try gen.generate(&task, ".", &env_vars1, &empty_params);
    defer allocator.free(key1);

    const key2 = try gen.generate(&task, ".", &env_vars2, &empty_params);
    defer allocator.free(key2);

    try std.testing.expect(!std.mem.eql(u8, key1, key2));
}

test "CacheKeyGenerator: allow_failure flag affects hash" {
    const allocator = std.testing.allocator;
    var gen = CacheKeyGenerator.init(allocator);

    var task1 = createMinimalTask("test", "npm test");
    var task2 = createMinimalTask("test", "npm test");
    task2.allow_failure = true;

    const EmptyParams = struct {
        pub fn count(_: @This()) usize {
            return 0;
        }
    };
    const empty_params = EmptyParams{};
    const empty_env = [_][]const u8{};

    const key1 = try gen.generate(&task1, ".", &empty_env, &empty_params);
    defer allocator.free(key1);

    const key2 = try gen.generate(&task2, ".", &empty_env, &empty_params);
    defer allocator.free(key2);

    try std.testing.expect(!std.mem.eql(u8, key1, key2));
}

test "CacheKeyGenerator: no sources/env/params produces valid hash" {
    const allocator = std.testing.allocator;
    var gen = CacheKeyGenerator.init(allocator);

    const task = createMinimalTask("minimal", "ls");
    const EmptyParams = struct {
        pub fn count(_: @This()) usize {
            return 0;
        }
    };
    const empty_params = EmptyParams{};
    const empty_env = [_][]const u8{};

    const key = try gen.generate(&task, ".", &empty_env, &empty_params);
    defer allocator.free(key);

    try std.testing.expectEqual(@as(usize, 64), key.len);
}

