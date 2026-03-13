const std = @import("std");
const Allocator = std.mem.Allocator;

/// Checkpoint state for a task execution
pub const CheckpointState = struct {
    task_name: []const u8,
    started_at: i64, // Unix timestamp
    checkpointed_at: i64, // Unix timestamp
    state: []const u8, // JSON-encoded task-specific state
    progress_pct: u8, // 0-100
    metadata: []const u8, // JSON-encoded metadata (attempt count, etc.)

    pub fn deinit(self: *CheckpointState, allocator: Allocator) void {
        allocator.free(self.task_name);
        allocator.free(self.state);
        allocator.free(self.metadata);
    }
};

/// Storage backend interface for checkpoints
pub const CheckpointStorage = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        save: *const fn (ptr: *anyopaque, state: CheckpointState, allocator: Allocator) anyerror!void,
        load: *const fn (ptr: *anyopaque, task_name: []const u8, allocator: Allocator) anyerror!?CheckpointState,
        delete: *const fn (ptr: *anyopaque, task_name: []const u8, allocator: Allocator) anyerror!void,
        list: *const fn (ptr: *anyopaque, allocator: Allocator) anyerror![][]const u8,
        deinit: *const fn (ptr: *anyopaque, allocator: Allocator) void,
    };

    pub fn save(self: CheckpointStorage, state: CheckpointState, allocator: Allocator) !void {
        return self.vtable.save(self.ptr, state, allocator);
    }

    pub fn load(self: CheckpointStorage, task_name: []const u8, allocator: Allocator) !?CheckpointState {
        return self.vtable.load(self.ptr, task_name, allocator);
    }

    pub fn delete(self: CheckpointStorage, task_name: []const u8, allocator: Allocator) !void {
        return self.vtable.delete(self.ptr, task_name, allocator);
    }

    pub fn list(self: CheckpointStorage, allocator: Allocator) ![][]const u8 {
        return self.vtable.list(self.ptr, allocator);
    }

    pub fn deinit(self: CheckpointStorage, allocator: Allocator) void {
        self.vtable.deinit(self.ptr, allocator);
    }
};

/// File system storage backend
pub const FileSystemStorage = struct {
    checkpoint_dir: []const u8,
    allocator: Allocator,

    pub fn init(checkpoint_dir: []const u8, allocator: Allocator) !FileSystemStorage {
        // Create directory if it doesn't exist
        std.fs.cwd().makePath(checkpoint_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        return FileSystemStorage{
            .checkpoint_dir = try allocator.dupe(u8, checkpoint_dir),
            .allocator = allocator,
        };
    }

    pub fn storage(self: *FileSystemStorage) CheckpointStorage {
        return CheckpointStorage{
            .ptr = self,
            .vtable = &.{
                .save = saveImpl,
                .load = loadImpl,
                .delete = deleteImpl,
                .list = listImpl,
                .deinit = deinitImpl,
            },
        };
    }

    fn saveImpl(ptr: *anyopaque, state: CheckpointState, allocator: Allocator) anyerror!void {
        const self: *FileSystemStorage = @ptrCast(@alignCast(ptr));

        const filename = try std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ self.checkpoint_dir, state.task_name });
        defer allocator.free(filename);

        const json_str = try std.fmt.allocPrint(allocator, "{{\"task_name\":\"{s}\",\"started_at\":{d},\"checkpointed_at\":{d},\"progress_pct\":{d},\"state\":{s},\"metadata\":{s}}}", .{
            state.task_name,
            state.started_at,
            state.checkpointed_at,
            state.progress_pct,
            state.state,
            state.metadata,
        });
        defer allocator.free(json_str);

        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        try file.writeAll(json_str);
    }

    fn loadImpl(ptr: *anyopaque, task_name: []const u8, allocator: Allocator) anyerror!?CheckpointState {
        const self: *FileSystemStorage = @ptrCast(@alignCast(ptr));

        const filename = try std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ self.checkpoint_dir, task_name });
        defer allocator.free(filename);

        const file = std.fs.cwd().openFile(filename, .{}) catch |err| switch (err) {
            error.FileNotFound => return null,
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
        defer allocator.free(content);

        // Parse JSON manually (simple field extraction)
        var state = CheckpointState{
            .task_name = undefined,
            .started_at = 0,
            .checkpointed_at = 0,
            .state = undefined,
            .progress_pct = 0,
            .metadata = undefined,
        };

        // Extract fields using simple JSON parsing
        // Format: {"task_name":"...","started_at":123,"checkpointed_at":456,"progress_pct":50,"state":{...},"metadata":{...}}
        var task_name_start: ?usize = null;
        var task_name_end: ?usize = null;
        var state_start: ?usize = null;
        var state_end: ?usize = null;
        var metadata_start: ?usize = null;
        var metadata_end: ?usize = null;

        // Find task_name field
        if (std.mem.indexOf(u8, content, "\"task_name\":\"")) |idx| {
            task_name_start = idx + 13;
            if (std.mem.indexOfPos(u8, content, task_name_start.?, "\"")) |end_idx| {
                task_name_end = end_idx;
                state.task_name = try allocator.dupe(u8, content[task_name_start.?..task_name_end.?]);
            }
        }

        // Find started_at field
        if (std.mem.indexOf(u8, content, "\"started_at\":")) |idx| {
            const num_start = idx + 13;
            var num_end = num_start;
            while (num_end < content.len and content[num_end] >= '0' and content[num_end] <= '9') : (num_end += 1) {}
            state.started_at = std.fmt.parseInt(i64, content[num_start..num_end], 10) catch 0;
        }

        // Find checkpointed_at field
        if (std.mem.indexOf(u8, content, "\"checkpointed_at\":")) |idx| {
            const num_start = idx + 18;
            var num_end = num_start;
            while (num_end < content.len and content[num_end] >= '0' and content[num_end] <= '9') : (num_end += 1) {}
            state.checkpointed_at = std.fmt.parseInt(i64, content[num_start..num_end], 10) catch 0;
        }

        // Find progress_pct field
        if (std.mem.indexOf(u8, content, "\"progress_pct\":")) |idx| {
            const num_start = idx + 15;
            var num_end = num_start;
            while (num_end < content.len and content[num_end] >= '0' and content[num_end] <= '9') : (num_end += 1) {}
            state.progress_pct = std.fmt.parseInt(u8, content[num_start..num_end], 10) catch 0;
        }

        // Find state field (JSON object)
        if (std.mem.indexOf(u8, content, "\"state\":")) |idx| {
            state_start = idx + 8;
            var depth: i32 = 0;
            var i = state_start.?;
            while (i < content.len) : (i += 1) {
                if (content[i] == '{') depth += 1;
                if (content[i] == '}') {
                    depth -= 1;
                    if (depth == 0) {
                        state_end = i + 1;
                        break;
                    }
                }
            }
            if (state_end) |end| {
                state.state = try allocator.dupe(u8, content[state_start.?..end]);
            }
        }

        // Find metadata field (JSON object)
        if (std.mem.indexOf(u8, content, "\"metadata\":")) |idx| {
            metadata_start = idx + 11;
            var depth: i32 = 0;
            var i = metadata_start.?;
            while (i < content.len) : (i += 1) {
                if (content[i] == '{') depth += 1;
                if (content[i] == '}') {
                    depth -= 1;
                    if (depth == 0) {
                        metadata_end = i + 1;
                        break;
                    }
                }
            }
            if (metadata_end) |end| {
                state.metadata = try allocator.dupe(u8, content[metadata_start.?..end]);
            }
        }

        // Validate all fields were parsed
        if (task_name_start == null or state_start == null or metadata_start == null) {
            if (task_name_start != null) allocator.free(state.task_name);
            if (state_start != null and state.state.len > 0) allocator.free(state.state);
            if (metadata_start != null and state.metadata.len > 0) allocator.free(state.metadata);
            return error.InvalidCheckpointFormat;
        }

        return state;
    }

    fn deleteImpl(ptr: *anyopaque, task_name: []const u8, allocator: Allocator) anyerror!void {
        const self: *FileSystemStorage = @ptrCast(@alignCast(ptr));

        const filename = try std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ self.checkpoint_dir, task_name });
        defer allocator.free(filename);

        std.fs.cwd().deleteFile(filename) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
    }

    fn listImpl(ptr: *anyopaque, allocator: Allocator) anyerror![][]const u8 {
        const self: *FileSystemStorage = @ptrCast(@alignCast(ptr));

        var dir = try std.fs.cwd().openDir(self.checkpoint_dir, .{ .iterate = true });
        defer dir.close();

        var names = std.ArrayList([]const u8){};
        errdefer {
            for (names.items) |name| {
                allocator.free(name);
            }
            names.deinit(allocator);
        }

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".json")) {
                const name_without_ext = entry.name[0 .. entry.name.len - 5]; // Remove ".json"
                try names.append(allocator, try allocator.dupe(u8, name_without_ext));
            }
        }

        return names.toOwnedSlice(allocator);
    }

    fn deinitImpl(ptr: *anyopaque, allocator: Allocator) void {
        const self: *FileSystemStorage = @ptrCast(@alignCast(ptr));
        allocator.free(self.checkpoint_dir);
    }
};

// Tests
test "FileSystemStorage: basic lifecycle" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const temp_dir = "zig-cache/test-checkpoints";
    std.fs.cwd().deleteTree(temp_dir) catch {};
    defer std.fs.cwd().deleteTree(temp_dir) catch {};

    var fs_storage = try FileSystemStorage.init(temp_dir, allocator);
    defer fs_storage.storage().deinit(allocator);

    const storage = fs_storage.storage();

    // Save a checkpoint
    const state = CheckpointState{
        .task_name = try allocator.dupe(u8, "test-task"),
        .started_at = 1000,
        .checkpointed_at = 1500,
        .state = try allocator.dupe(u8, "{}"),
        .progress_pct = 50,
        .metadata = try allocator.dupe(u8, "{}"),
    };
    defer {
        allocator.free(state.task_name);
        allocator.free(state.state);
        allocator.free(state.metadata);
    }

    try storage.save(state, allocator);

    // List checkpoints
    const names = try storage.list(allocator);
    defer {
        for (names) |name| {
            allocator.free(name);
        }
        allocator.free(names);
    }

    try testing.expectEqual(@as(usize, 1), names.len);
    try testing.expectEqualStrings("test-task", names[0]);

    // Delete checkpoint
    try storage.delete("test-task", allocator);

    const names2 = try storage.list(allocator);
    defer allocator.free(names2);
    try testing.expectEqual(@as(usize, 0), names2.len);
}

test "FileSystemStorage: delete nonexistent checkpoint" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const temp_dir = "zig-cache/test-checkpoints-2";
    std.fs.cwd().deleteTree(temp_dir) catch {};
    defer std.fs.cwd().deleteTree(temp_dir) catch {};

    var fs_storage = try FileSystemStorage.init(temp_dir, allocator);
    defer fs_storage.storage().deinit(allocator);

    const storage = fs_storage.storage();

    // Should not error on deleting nonexistent checkpoint
    try storage.delete("nonexistent", allocator);
}

test "FileSystemStorage: save and load checkpoint" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const temp_dir = "zig-cache/test-checkpoints-3";
    std.fs.cwd().deleteTree(temp_dir) catch {};
    defer std.fs.cwd().deleteTree(temp_dir) catch {};

    var fs_storage = try FileSystemStorage.init(temp_dir, allocator);
    defer fs_storage.storage().deinit(allocator);

    const storage = fs_storage.storage();

    // Save a checkpoint with actual data
    const state = CheckpointState{
        .task_name = try allocator.dupe(u8, "build-task"),
        .started_at = 1000,
        .checkpointed_at = 2000,
        .state = try allocator.dupe(u8, "{\"step\":3,\"files\":[\"a.o\",\"b.o\"]}"),
        .progress_pct = 75,
        .metadata = try allocator.dupe(u8, "{\"attempt\":2}"),
    };
    defer {
        allocator.free(state.task_name);
        allocator.free(state.state);
        allocator.free(state.metadata);
    }

    try storage.save(state, allocator);

    // Load the checkpoint back
    const loaded = try storage.load("build-task", allocator);
    try testing.expect(loaded != null);

    if (loaded) |l| {
        defer {
            allocator.free(l.task_name);
            allocator.free(l.state);
            allocator.free(l.metadata);
        }

        try testing.expectEqualStrings("build-task", l.task_name);
        try testing.expectEqual(@as(i64, 1000), l.started_at);
        try testing.expectEqual(@as(i64, 2000), l.checkpointed_at);
        try testing.expectEqual(@as(u8, 75), l.progress_pct);
        try testing.expectEqualStrings("{\"step\":3,\"files\":[\"a.o\",\"b.o\"]}", l.state);
        try testing.expectEqualStrings("{\"attempt\":2}", l.metadata);
    }

    // Clean up
    try storage.delete("build-task", allocator);
}
