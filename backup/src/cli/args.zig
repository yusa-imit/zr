const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ArgsError = enum {
    MissingCommand,
    MissingRepository,
    MissingPath,
    MissingTaskName,

    pub fn toError(self: ArgsError) error{
        MissingCommand,
        MissingRepository,
        MissingPath,
        MissingTaskName,
    } {
        return switch (self) {
            .MissingCommand => error.MissingCommand,
            .MissingRepository => error.MissingRepository,
            .MissingPath => error.MissingPath,
            .MissingTaskName => error.MissingTaskName,
        };
    }
};

/// CLI 명령어들의 모든 인자를 관리하는 구조체
pub const Arguments = struct {
    allocator: Allocator,
    raw_args: std.process.ArgIterator,
    index: usize,
    args: std.ArrayList([]const u8),

    command: ?[]const u8,
    repository: ?[]const u8,
    remaining_args: ?std.ArrayList([]const u8),

    pub fn init(allocator: Allocator) !Arguments {
        var raw_args = try std.process.argsWithAllocator(allocator);
        // Skip the executable name
        _ = raw_args.skip();

        var args = std.ArrayList([]const u8).init(allocator);

        // 모든 인자를 복사
        while (raw_args.next()) |arg| {
            try args.append(try allocator.dupe(u8, arg));
        }

        return Arguments{
            .allocator = allocator,
            .raw_args = raw_args,
            .index = 0,
            .args = args,
            .command = null,
            .repository = null,
            .remaining_args = null,
        };
    }

    pub fn deinit(self: *Arguments) void {
        if (@TypeOf(self.raw_args) != @TypeOf(undefined)) {
            self.raw_args.deinit();
        }

        if (self.args.capacity > 0) {
            for (self.args.items) |arg| {
                self.allocator.free(arg);
            }
            self.args.deinit();
        }

        if (self.remaining_args) |*extra_args| {
            for (extra_args.items) |arg| {
                self.allocator.free(arg);
            }
            extra_args.deinit();
            self.remaining_args = null; // 중복 해제 방지
        }
    }
    pub fn next(self: *Arguments) ?[]const u8 {
        if (self.index < self.args.items.len) {
            const arg = self.args.items[self.index];
            self.index += 1;
            return arg;
        }
        return null;
    }

    pub fn peek(self: *Arguments) ?[]const u8 {
        if (self.index < self.args.items.len) {
            return self.args.items[self.index];
        }
        return null;
    }

    pub fn remaining(self: *Arguments) []const []const u8 {
        return self.args.items[self.index..];
    }

    pub fn requireNext(self: *Arguments, err: ArgsError) ![]const u8 {
        return self.next() orelse return err.toError();
    }

    /// 첫 번째 인자를 command로 파싱
    pub fn parseCommand(self: *Arguments) !void {
        self.command = try self.requireNext(.MissingCommand);
    }

    /// 다음 인자를 repository로 파싱
    pub fn parseRepository(self: *Arguments) !void {
        self.repository = try self.requireNext(.MissingRepository);
    }

    /// 나머지 모든 인자를 파싱
    pub fn parseRemaining(self: *Arguments) !void {
        var extra_args = std.ArrayList([]const u8).init(self.allocator);
        errdefer {
            for (extra_args.items) |arg| {
                self.allocator.free(arg);
            }
            extra_args.deinit();
        }

        while (self.next()) |arg| {
            try extra_args.append(try self.allocator.dupe(u8, arg));
        }

        if (self.remaining_args) |*prev_args| {
            for (prev_args.items) |arg| {
                self.allocator.free(arg);
            }
            prev_args.deinit();
        }

        self.remaining_args = extra_args;
    }

    pub fn iterator(self: *Arguments) !*Arguments {
        const new_args = try self.allocator.create(Arguments);
        new_args.* = .{
            .allocator = self.allocator,
            .raw_args = undefined, // iterator에서는 사용하지 않음
            .index = 0, // Start from beginning of remaining args
            .args = if (self.remaining_args) |*rem_args| rem_args.* else self.args,
            .command = null,
            .repository = null,
            .remaining_args = null,
        };
        return new_args;
    }

    pub fn taskIterator(self: *Arguments, repo_name: []const u8, task_command: []const u8) !*Arguments {
        var task_args = std.ArrayList([]const u8).init(self.allocator);
        errdefer {
            for (task_args.items) |arg| {
                self.allocator.free(arg);
            }
            task_args.deinit();
        }

        // 레포지토리 이름 추가
        try task_args.append(try self.allocator.dupe(u8, repo_name));

        // 명령어 토큰화하여 추가
        var cmd_iter = std.mem.tokenizeScalar(u8, task_command, ' ');
        while (cmd_iter.next()) |token| {
            try task_args.append(try self.allocator.dupe(u8, token));
        }

        // 나머지 인자들 추가
        for (self.remaining()) |arg| {
            try task_args.append(try self.allocator.dupe(u8, arg));
        }

        const new_args = try self.allocator.create(Arguments);
        errdefer self.allocator.destroy(new_args);

        new_args.* = .{
            .allocator = self.allocator,
            .raw_args = undefined,
            .index = 0,
            .args = task_args,
            .command = null,
            .repository = null,
            .remaining_args = null,
        };

        return new_args;
    }

    /// 현재 인자 값 가져오기 (커서 이동 없음)
    pub fn current(self: *Arguments) ?[]const u8 {
        if (self.index > 0 and self.index <= self.args.items.len) {
            return self.args.items[self.index - 1];
        }
        return null;
    }

    /// 커서를 뒤로 이동
    pub fn rewind(self: *Arguments) void {
        if (self.index > 0) {
            self.index -= 1;
        }
    }
};

test "Arguments parsing - basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Mock process arguments for testing
    var mock_args = std.ArrayList([]const u8).init(allocator);
    defer {
        for (mock_args.items) |arg| {
            allocator.free(arg);
        }
        mock_args.deinit();
    }

    try mock_args.append(try allocator.dupe(u8, "run"));
    try mock_args.append(try allocator.dupe(u8, "frontend"));
    try mock_args.append(try allocator.dupe(u8, "build"));

    var args = Arguments{
        .allocator = allocator,
        .raw_args = undefined,
        .index = 0,
        .args = mock_args,
        .command = null,
        .repository = null,
        .remaining_args = null,
    };

    // Test command parsing
    try args.parseCommand();
    try testing.expectEqualStrings("run", args.command.?);

    // Test next() functionality
    const repo = args.next();
    try testing.expect(repo != null);
    try testing.expectEqualStrings("frontend", repo.?);

    const task = args.next();
    try testing.expect(task != null);
    try testing.expectEqualStrings("build", task.?);

    const end = args.next();
    try testing.expect(end == null);
}

test "Arguments - peek and rewind functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var mock_args = std.ArrayList([]const u8).init(allocator);
    defer {
        for (mock_args.items) |arg| {
            allocator.free(arg);
        }
        mock_args.deinit();
    }

    try mock_args.append(try allocator.dupe(u8, "list"));
    try mock_args.append(try allocator.dupe(u8, "repos"));

    var args = Arguments{
        .allocator = allocator,
        .raw_args = undefined,
        .index = 0,
        .args = mock_args,
        .command = null,
        .repository = null,
        .remaining_args = null,
    };

    // Test peek without moving cursor
    const peeked = args.peek();
    try testing.expect(peeked != null);
    try testing.expectEqualStrings("list", peeked.?);

    // Cursor should still be at 0
    try testing.expectEqual(@as(usize, 0), args.index);

    // Move cursor and test current
    _ = args.next();
    const current = args.current();
    try testing.expect(current != null);
    try testing.expectEqualStrings("list", current.?);

    // Test rewind
    args.rewind();
    try testing.expectEqual(@as(usize, 0), args.index);
}
