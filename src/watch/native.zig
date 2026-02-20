const std = @import("std");
const builtin = @import("builtin");

/// Native filesystem watcher using OS-specific APIs:
/// - Linux: inotify
/// - macOS: kqueue
/// - Windows: ReadDirectoryChangesW
///
/// Provides an event-driven interface with automatic recursive directory watching.
pub const NativeWatcher = struct {
    allocator: std.mem.Allocator,
    paths: []const []const u8,
    backend: Backend,

    const Self = @This();

    pub const WatchEvent = struct {
        path: []const u8,
        kind: EventKind,
    };

    pub const EventKind = enum {
        created,
        modified,
        deleted,
    };

    const Backend = if (builtin.os.tag == .linux)
        LinuxBackend
    else if (builtin.os.tag == .macos)
        MacOSBackend
    else if (builtin.os.tag == .windows)
        WindowsBackend
    else
        @compileError("Unsupported platform for native watcher");

    pub fn init(allocator: std.mem.Allocator, paths: []const []const u8) !Self {
        const backend = try Backend.init(allocator, paths);
        return Self{
            .allocator = allocator,
            .paths = paths,
            .backend = backend,
        };
    }

    pub fn deinit(self: *Self) void {
        self.backend.deinit();
    }

    /// Wait for the next filesystem event. Blocks until an event occurs.
    pub fn waitForEvent(self: *Self) !WatchEvent {
        return try self.backend.waitForEvent();
    }
};

// ============================================================================
// Linux inotify backend
// ============================================================================

const LinuxBackend = if (builtin.os.tag == .linux) struct {
    allocator: std.mem.Allocator,
    fd: std.posix.fd_t,
    /// Maps inotify watch descriptor -> owned path string
    wd_to_path: std.AutoHashMap(i32, []const u8),
    /// Maps path -> inotify watch descriptor for removal
    path_to_wd: std.StringHashMap(i32),
    buffer: []u8,

    const BUFFER_SIZE = 4096;

    pub fn init(allocator: std.mem.Allocator, paths: []const []const u8) !@This() {
        const fd = try std.posix.inotify_init1(std.os.linux.IN.CLOEXEC);
        errdefer std.posix.close(fd);

        var wd_to_path = std.AutoHashMap(i32, []const u8).init(allocator);
        errdefer wd_to_path.deinit();
        var path_to_wd = std.StringHashMap(i32).init(allocator);
        errdefer path_to_wd.deinit();

        var self = @This(){
            .allocator = allocator,
            .fd = fd,
            .wd_to_path = wd_to_path,
            .path_to_wd = path_to_wd,
            .buffer = try allocator.alloc(u8, BUFFER_SIZE),
        };
        errdefer allocator.free(self.buffer);

        // Add all watch paths recursively
        for (paths) |path| {
            try self.addWatchRecursive(path);
        }

        return self;
    }

    pub fn deinit(self: *@This()) void {
        var it = self.wd_to_path.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.wd_to_path.deinit();
        self.path_to_wd.deinit();
        self.allocator.free(self.buffer);
        std.posix.close(self.fd);
    }

    fn addWatchRecursive(self: *@This(), root: []const u8) !void {
        // Add watch for the root itself
        try self.addWatch(root);

        // Recursively add watches for subdirectories
        const stat = std.fs.cwd().statFile(root) catch return;
        if (stat.kind != .directory) return;

        var dir = std.fs.cwd().openDir(root, .{ .iterate = true }) catch return;
        defer dir.close();
        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind != .directory) continue;
            if (shouldSkip(entry.basename)) continue;

            const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ root, entry.path });
            defer self.allocator.free(full_path);

            try self.addWatch(full_path);
        }
    }

    fn addWatch(self: *@This(), path: []const u8) !void {
        const mask = std.os.linux.IN.CREATE | std.os.linux.IN.MODIFY | std.os.linux.IN.DELETE | std.os.linux.IN.MOVED_TO | std.os.linux.IN.MOVED_FROM;

        const path_z = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(path_z);

        const wd = try std.posix.inotify_add_watch(self.fd, path_z, mask);

        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);

        try self.wd_to_path.put(wd, owned_path);
        try self.path_to_wd.put(owned_path, wd);
    }

    pub fn waitForEvent(self: *@This()) !NativeWatcher.WatchEvent {
        while (true) {
            const n = try std.posix.read(self.fd, self.buffer);
            if (n == 0) continue;

            var offset: usize = 0;
            while (offset < n) {
                const event = @as(*const std.os.linux.inotify_event, @ptrCast(@alignCast(&self.buffer[offset])));
                offset += @sizeOf(std.os.linux.inotify_event) + event.len;

                // Ignore events we don't care about
                if (shouldSkip(std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&event.name)), 0))) continue;

                const base_path = self.wd_to_path.get(event.wd) orelse continue;

                // Build full path
                const name_slice = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&event.name)), 0);
                const full_path = if (name_slice.len > 0)
                    try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ base_path, name_slice })
                else
                    try self.allocator.dupe(u8, base_path);

                const kind: NativeWatcher.EventKind = if (event.mask & std.os.linux.IN.CREATE != 0 or event.mask & std.os.linux.IN.MOVED_TO != 0)
                    .created
                else if (event.mask & std.os.linux.IN.MODIFY != 0)
                    .modified
                else if (event.mask & std.os.linux.IN.DELETE != 0 or event.mask & std.os.linux.IN.MOVED_FROM != 0)
                    .deleted
                else
                    continue;

                // If a new directory was created, watch it recursively
                if (kind == .created) {
                    const stat = std.fs.cwd().statFile(full_path) catch |err| switch (err) {
                        error.FileNotFound => {
                            // File was deleted before we could stat it
                            continue;
                        },
                        else => return err,
                    };
                    if (stat.kind == .directory) {
                        self.addWatchRecursive(full_path) catch {};
                    }
                }

                return NativeWatcher.WatchEvent{
                    .path = full_path,
                    .kind = kind,
                };
            }
        }
    }
} else struct {
    pub fn init(_: std.mem.Allocator, _: []const []const u8) !@This() {
        unreachable;
    }
    pub fn deinit(_: *@This()) void {
        unreachable;
    }
    pub fn waitForEvent(_: *@This()) !NativeWatcher.WatchEvent {
        unreachable;
    }
};

// ============================================================================
// macOS kqueue backend
// ============================================================================

const MacOSBackend = if (builtin.os.tag == .macos) struct {
    allocator: std.mem.Allocator,
    kq: std.posix.fd_t,
    /// Maps file descriptor -> owned path string
    fd_to_path: std.AutoHashMap(std.posix.fd_t, []const u8),
    /// File descriptors we're watching
    watch_fds: std.ArrayList(std.posix.fd_t),

    // kqueue constants from <sys/event.h>
    const EVFILT_VNODE: i16 = -4;
    const EV_ADD: u16 = 0x0001;
    const EV_ENABLE: u16 = 0x0004;
    const EV_CLEAR: u16 = 0x0020;
    const NOTE_WRITE: u32 = 0x0002;
    const NOTE_DELETE: u32 = 0x0001;
    const NOTE_EXTEND: u32 = 0x0004;
    const NOTE_ATTRIB: u32 = 0x0008;

    pub fn init(allocator: std.mem.Allocator, paths: []const []const u8) !@This() {
        const kq = try std.posix.kqueue();
        errdefer std.posix.close(kq);

        var fd_to_path = std.AutoHashMap(std.posix.fd_t, []const u8).init(allocator);
        errdefer fd_to_path.deinit();
        var watch_fds = std.ArrayList(std.posix.fd_t){};
        errdefer watch_fds.deinit(allocator);

        var self = @This(){
            .allocator = allocator,
            .kq = kq,
            .fd_to_path = fd_to_path,
            .watch_fds = watch_fds,
        };

        // Add all watch paths recursively
        for (paths) |path| {
            try self.addWatchRecursive(path);
        }

        return self;
    }

    pub fn deinit(self: *@This()) void {
        for (self.watch_fds.items) |fd| {
            std.posix.close(fd);
        }
        var it = self.fd_to_path.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.fd_to_path.deinit();
        self.watch_fds.deinit(self.allocator);
        std.posix.close(self.kq);
    }

    fn addWatchRecursive(self: *@This(), root: []const u8) !void {
        try self.addWatch(root);

        const stat = std.fs.cwd().statFile(root) catch return;
        if (stat.kind != .directory) return;

        var dir = std.fs.cwd().openDir(root, .{ .iterate = true }) catch return;
        defer dir.close();
        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (shouldSkip(entry.basename)) continue;

            const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ root, entry.path });
            defer self.allocator.free(full_path);

            try self.addWatch(full_path);
        }
    }

    fn addWatch(self: *@This(), path: []const u8) !void {
        const fd = try std.posix.open(path, .{ .ACCMODE = .RDONLY }, 0);
        errdefer std.posix.close(fd);

        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);

        // Register the fd with kqueue
        const kev: std.posix.Kevent = .{
            .ident = @intCast(fd),
            .filter = EVFILT_VNODE,
            .flags = EV_ADD | EV_ENABLE | EV_CLEAR,
            .fflags = NOTE_WRITE | NOTE_DELETE | NOTE_EXTEND | NOTE_ATTRIB,
            .data = 0,
            .udata = 0,
        };

        const changelist = [_]std.posix.Kevent{kev};
        _ = try std.posix.kevent(self.kq, &changelist, &[_]std.posix.Kevent{}, null);

        try self.fd_to_path.put(fd, owned_path);
        try self.watch_fds.append(self.allocator, fd);
    }

    pub fn waitForEvent(self: *@This()) !NativeWatcher.WatchEvent {
        var events: [1]std.posix.Kevent = undefined;

        while (true) {
            const n = try std.posix.kevent(self.kq, &[_]std.posix.Kevent{}, events[0..], null);
            if (n == 0) continue;

            const event = events[0];
            const fd: std.posix.fd_t = @intCast(event.ident);
            const path = self.fd_to_path.get(fd) orelse continue;

            const kind: NativeWatcher.EventKind = if (event.fflags & NOTE_DELETE != 0)
                .deleted
            else if (event.fflags & NOTE_WRITE != 0 or event.fflags & NOTE_EXTEND != 0)
                .modified
            else if (event.fflags & NOTE_ATTRIB != 0)
                .modified
            else
                continue;

            const path_copy = try self.allocator.dupe(u8, path);
            return NativeWatcher.WatchEvent{
                .path = path_copy,
                .kind = kind,
            };
        }
    }
} else struct {
    pub fn init(_: std.mem.Allocator, _: []const []const u8) !@This() {
        unreachable;
    }
    pub fn deinit(_: *@This()) void {
        unreachable;
    }
    pub fn waitForEvent(_: *@This()) !NativeWatcher.WatchEvent {
        unreachable;
    }
};

// ============================================================================
// Windows ReadDirectoryChangesW backend
// ============================================================================

const WindowsBackend = if (builtin.os.tag == .windows) struct {
    allocator: std.mem.Allocator,
    handles: std.ArrayList(std.os.windows.HANDLE),
    paths: std.ArrayList([]const u8),
    buffer: []u8,

    const BUFFER_SIZE = 4096;

    pub fn init(allocator: std.mem.Allocator, watch_paths: []const []const u8) !@This() {
        var handles = std.ArrayList(std.os.windows.HANDLE){};
        errdefer handles.deinit(allocator);
        var paths_list = std.ArrayList([]const u8){};
        errdefer paths_list.deinit(allocator);

        const buffer = try allocator.alloc(u8, BUFFER_SIZE);
        errdefer allocator.free(buffer);

        var self = @This(){
            .allocator = allocator,
            .handles = handles,
            .paths = paths_list,
            .buffer = buffer,
        };

        for (watch_paths) |path| {
            try self.addWatch(path);
        }

        return self;
    }

    pub fn deinit(self: *@This()) void {
        for (self.handles.items) |handle| {
            std.os.windows.CloseHandle(handle);
        }
        for (self.paths.items) |path| {
            self.allocator.free(path);
        }
        self.handles.deinit(self.allocator);
        self.paths.deinit(self.allocator);
        self.allocator.free(self.buffer);
    }

    fn addWatch(self: *@This(), path: []const u8) !void {
        const path_w = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, path);
        defer self.allocator.free(path_w);

        const handle = std.os.windows.kernel32.CreateFileW(
            path_w,
            std.os.windows.FILE_LIST_DIRECTORY,
            std.os.windows.FILE_SHARE_READ | std.os.windows.FILE_SHARE_WRITE | std.os.windows.FILE_SHARE_DELETE,
            null,
            std.os.windows.OPEN_EXISTING,
            std.os.windows.FILE_FLAG_BACKUP_SEMANTICS,
            null,
        ) catch return error.CannotWatch;

        if (handle == std.os.windows.INVALID_HANDLE_VALUE) return error.CannotWatch;

        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);

        try self.handles.append(self.allocator, handle);
        try self.paths.append(self.allocator, owned_path);
    }

    pub fn waitForEvent(self: *@This()) !NativeWatcher.WatchEvent {
        const FILE_NOTIFY_CHANGE_FILE_NAME = 0x00000001;
        const FILE_NOTIFY_CHANGE_DIR_NAME = 0x00000002;
        const FILE_NOTIFY_CHANGE_SIZE = 0x00000008;
        const FILE_NOTIFY_CHANGE_LAST_WRITE = 0x00000010;

        const filter = FILE_NOTIFY_CHANGE_FILE_NAME |
            FILE_NOTIFY_CHANGE_DIR_NAME |
            FILE_NOTIFY_CHANGE_SIZE |
            FILE_NOTIFY_CHANGE_LAST_WRITE;

        while (true) {
            for (self.handles.items, 0..) |handle, idx| {
                var bytes_returned: u32 = 0;

                const success = std.os.windows.kernel32.ReadDirectoryChangesW(
                    handle,
                    self.buffer.ptr,
                    @intCast(self.buffer.len),
                    1, // watch subtree
                    filter,
                    &bytes_returned,
                    null,
                    null,
                );

                if (success == 0 or bytes_returned == 0) continue;

                // Parse FILE_NOTIFY_INFORMATION structure
                var offset: usize = 0;
                while (offset < bytes_returned) {
                    const info = @as(*const std.os.windows.FILE_NOTIFY_INFORMATION, @ptrCast(@alignCast(&self.buffer[offset])));

                    const filename_bytes = @as([*]const u16, @ptrCast(@alignCast(&info.FileName)))[0 .. info.FileNameLength / 2];
                    const filename = std.unicode.utf16LeToUtf8Alloc(self.allocator, filename_bytes) catch continue;
                    defer self.allocator.free(filename);

                    if (shouldSkip(std.fs.path.basename(filename))) {
                        if (info.NextEntryOffset == 0) break;
                        offset += info.NextEntryOffset;
                        continue;
                    }

                    const base_path = self.paths.items[idx];
                    const full_path = try std.fmt.allocPrint(self.allocator, "{s}\\{s}", .{ base_path, filename });

                    const kind: NativeWatcher.EventKind = switch (info.Action) {
                        std.os.windows.FILE_ACTION_ADDED => .created,
                        std.os.windows.FILE_ACTION_MODIFIED => .modified,
                        std.os.windows.FILE_ACTION_REMOVED => .deleted,
                        std.os.windows.FILE_ACTION_RENAMED_OLD_NAME => .deleted,
                        std.os.windows.FILE_ACTION_RENAMED_NEW_NAME => .created,
                        else => {
                            self.allocator.free(full_path);
                            if (info.NextEntryOffset == 0) break;
                            offset += info.NextEntryOffset;
                            continue;
                        },
                    };

                    return NativeWatcher.WatchEvent{
                        .path = full_path,
                        .kind = kind,
                    };
                }
            }

            // Sleep briefly to avoid busy-waiting
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }
    }
} else struct {
    pub fn init(_: std.mem.Allocator, _: []const []const u8) !@This() {
        unreachable;
    }
    pub fn deinit(_: *@This()) void {
        unreachable;
    }
    pub fn waitForEvent(_: *@This()) !NativeWatcher.WatchEvent {
        unreachable;
    }
};

// ============================================================================
// Common utilities
// ============================================================================

const SKIP_DIRS = [_][]const u8{
    ".git",
    "node_modules",
    "zig-out",
    ".zig-cache",
};

fn shouldSkip(basename: []const u8) bool {
    for (SKIP_DIRS) |skip| {
        if (std.mem.eql(u8, basename, skip)) return true;
    }
    return false;
}

// ============================================================================
// Tests
// ============================================================================

test "native watcher compiles" {
    // This test just ensures the backend compiles for the current platform
    const allocator = std.testing.allocator;
    const paths = [_][]const u8{"."};

    var watcher = try NativeWatcher.init(allocator, &paths);
    defer watcher.deinit();
}
