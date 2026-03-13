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
        allocator.free(content); // Free immediately since we don't parse yet

        // TODO: Implement JSON parsing to deserialize checkpoint state
        // For now, return null to indicate checkpoint loading not implemented yet
        return null;
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
