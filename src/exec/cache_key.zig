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
            if (task.ignore_error) 1 else 0,
        };
        hasher.update(&flags_buf);

        // Finalize hash
        var digest: [32]u8 = undefined;
        hasher.final(&digest);

        // Convert to hex string
        const hex_buf = try self.allocator.alloc(u8, 64);
        _ = try std.fmt.bufPrint(hex_buf, "{x:0>64}", .{std.fmt.fmtSliceHexLower(&digest)});

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
            var matches = try glob_mod.find(self.allocator, dir, pattern);
            defer {
                for (matches.items) |m| self.allocator.free(m);
                matches.deinit(self.allocator);
            }

            for (matches.items) |match| {
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
    fn hashTaskParams(
        _: *CacheKeyGenerator,
        hasher: *crypto.hash.sha2.Sha256,
        runtime_params: anytype,
    ) !void {
        // Check if runtime_params is a HashMap or similar
        const T = @TypeOf(runtime_params);
        const type_info = @typeInfo(T);

        if (type_info == .Pointer) {
            // Handle HashMap-like types
            if (@hasDecl(type_info.Pointer.child, "iterator")) {
                var iter = runtime_params.iterator();

                // Collect entries for sorting
                var entries = std.ArrayList(struct {
                    key: []const u8,
                    value: []const u8,
                }).init(std.heap.page_allocator);
                defer entries.deinit();

                while (iter.next()) |entry| {
                    try entries.append(.{
                        .key = entry.key_ptr.*,
                        .value = entry.value_ptr.*,
                    });
                }

                // Sort by key for determinism
                std.mem.sort(@TypeOf(entries.items[0]), entries.items, {}, struct {
                    fn lessThan(_: void, a: @TypeOf(entries.items[0]), b: @TypeOf(entries.items[0])) bool {
                        return std.mem.order(u8, a.key, b.key) == .lt;
                    }
                }.lessThan);

                // Hash sorted entries
                for (entries.items) |entry| {
                    hasher.update(entry.key);
                    hasher.update(&[_]u8{'='});
                    hasher.update(entry.value);
                    hasher.update(&[_]u8{0});
                }
            } else if (@hasDecl(type_info.Pointer.child, "count")) {
                // Handle struct with count() method (likely empty params)
                // Empty params, no hashing needed
                return;
            }
        }
    }
};

