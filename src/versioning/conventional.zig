const std = @import("std");
const types = @import("types.zig");

/// Commit type from conventional commits spec
pub const CommitType = enum {
    feat,
    fix,
    docs,
    style,
    refactor,
    perf,
    @"test",
    chore,
    ci,
    build,
    revert,
    other,

    pub fn fromString(s: []const u8) CommitType {
        if (std.mem.eql(u8, s, "feat")) return .feat;
        if (std.mem.eql(u8, s, "fix")) return .fix;
        if (std.mem.eql(u8, s, "docs")) return .docs;
        if (std.mem.eql(u8, s, "style")) return .style;
        if (std.mem.eql(u8, s, "refactor")) return .refactor;
        if (std.mem.eql(u8, s, "perf")) return .perf;
        if (std.mem.eql(u8, s, "test")) return .@"test";
        if (std.mem.eql(u8, s, "chore")) return .chore;
        if (std.mem.eql(u8, s, "ci")) return .ci;
        if (std.mem.eql(u8, s, "build")) return .build;
        if (std.mem.eql(u8, s, "revert")) return .revert;
        return .other;
    }

    pub fn toString(self: CommitType) []const u8 {
        return switch (self) {
            .feat => "feat",
            .fix => "fix",
            .docs => "docs",
            .style => "style",
            .refactor => "refactor",
            .perf => "perf",
            .@"test" => "test",
            .chore => "chore",
            .ci => "ci",
            .build => "build",
            .revert => "revert",
            .other => "other",
        };
    }
};

/// Parsed conventional commit
pub const ConventionalCommit = struct {
    commit_type: CommitType,
    scope: ?[]const u8,
    description: []const u8,
    body: ?[]const u8,
    breaking: bool,
    hash: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        commit_type: CommitType,
        scope: ?[]const u8,
        description: []const u8,
        body: ?[]const u8,
        breaking: bool,
        hash: []const u8,
    ) !ConventionalCommit {
        return .{
            .commit_type = commit_type,
            .scope = if (scope) |s| try allocator.dupe(u8, s) else null,
            .description = try allocator.dupe(u8, description),
            .body = if (body) |b| try allocator.dupe(u8, b) else null,
            .breaking = breaking,
            .hash = try allocator.dupe(u8, hash),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ConventionalCommit) void {
        if (self.scope) |s| self.allocator.free(s);
        self.allocator.free(self.description);
        if (self.body) |b| self.allocator.free(b);
        self.allocator.free(self.hash);
    }

    /// Determine the recommended bump type for this commit
    pub fn getBumpType(self: ConventionalCommit) types.BumpType {
        if (self.breaking) return .major;
        return switch (self.commit_type) {
            .feat => .minor,
            .fix, .perf => .patch,
            else => .patch, // Default to patch for other types
        };
    }
};

/// Parse a conventional commit message
/// Format: type(scope)!: description
/// The '!' indicates a breaking change
pub fn parseCommitMessage(allocator: std.mem.Allocator, message: []const u8, hash: []const u8) !?ConventionalCommit {
    // Find the first line (subject)
    const subject_end = std.mem.indexOfScalar(u8, message, '\n') orelse message.len;
    const subject = std.mem.trim(u8, message[0..subject_end], " \t");

    // Find the colon separator
    const colon_idx = std.mem.indexOfScalar(u8, subject, ':') orelse return null;
    if (colon_idx == 0) return null;

    const prefix = subject[0..colon_idx];
    const description = std.mem.trim(u8, subject[colon_idx + 1 ..], " \t");

    // Check for breaking change indicator (!)
    const breaking = std.mem.endsWith(u8, prefix, "!");
    const prefix_clean = if (breaking) prefix[0 .. prefix.len - 1] else prefix;

    // Parse type and optional scope
    var commit_type: CommitType = .other;
    var scope: ?[]const u8 = null;

    if (std.mem.indexOfScalar(u8, prefix_clean, '(')) |open_paren| {
        const type_str = prefix_clean[0..open_paren];
        commit_type = CommitType.fromString(type_str);

        if (std.mem.indexOfScalar(u8, prefix_clean, ')')) |close_paren| {
            if (close_paren > open_paren + 1) {
                scope = prefix_clean[open_paren + 1 .. close_paren];
            }
        }
    } else {
        commit_type = CommitType.fromString(prefix_clean);
    }

    // Extract body (if present)
    var body: ?[]const u8 = null;
    if (subject_end < message.len) {
        const body_text = std.mem.trim(u8, message[subject_end + 1 ..], " \t\n");
        if (body_text.len > 0) {
            body = body_text;
        }
    }

    // Check for BREAKING CHANGE in body
    const breaking_from_body = if (body) |b| std.mem.indexOf(u8, b, "BREAKING CHANGE") != null else false;

    return try ConventionalCommit.init(
        allocator,
        commit_type,
        scope,
        description,
        body,
        breaking or breaking_from_body,
        hash,
    );
}

/// Get commits from git log since a given ref
pub fn getCommitsSince(allocator: std.mem.Allocator, since_ref: []const u8) !std.ArrayList(ConventionalCommit) {
    var commits = std.ArrayList(ConventionalCommit){};
    errdefer {
        for (commits.items) |*c| c.deinit();
        commits.deinit(allocator);
    }

    // Run git log with custom format
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "git",
            "log",
            "--format=%H%n%s%n%b%n--END--",
            std.fmt.allocPrint(allocator, "{s}..HEAD", .{since_ref}) catch return commits,
        },
    }) catch return commits;
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    if (result.term.Exited != 0) return commits;

    // Parse output
    var line_iter = std.mem.splitSequence(u8, result.stdout, "--END--\n");
    while (line_iter.next()) |entry| {
        if (entry.len == 0) continue;

        var lines = std.mem.splitScalar(u8, entry, '\n');
        const hash_line = lines.next() orelse continue;
        const subject = lines.next() orelse continue;

        // Collect body
        var body_lines = std.ArrayList(u8){};
        defer body_lines.deinit(allocator);

        while (lines.next()) |line| {
            if (body_lines.items.len > 0) {
                try body_lines.append(allocator, '\n');
            }
            try body_lines.appendSlice(allocator, line);
        }

        const full_message = if (body_lines.items.len > 0)
            try std.fmt.allocPrint(allocator, "{s}\n{s}", .{ subject, body_lines.items })
        else
            try allocator.dupe(u8, subject);
        defer allocator.free(full_message);

        if (try parseCommitMessage(allocator, full_message, hash_line)) |commit| {
            try commits.append(allocator, commit);
        }
    }

    return commits;
}

/// Determine the recommended bump type from a list of commits
pub fn determineBumpType(commits: []const ConventionalCommit) types.BumpType {
    var has_breaking = false;
    var has_feat = false;
    var has_fix = false;

    for (commits) |commit| {
        if (commit.breaking) has_breaking = true;
        if (commit.commit_type == .feat) has_feat = true;
        if (commit.commit_type == .fix) has_fix = true;
    }

    if (has_breaking) return .major;
    if (has_feat) return .minor;
    if (has_fix) return .patch;
    return .patch; // Default
}

test "parseCommitMessage feat" {
    var commit = (try parseCommitMessage(std.testing.allocator, "feat: add new feature", "abc123")).?;
    defer commit.deinit();

    try std.testing.expectEqual(CommitType.feat, commit.commit_type);
    try std.testing.expectEqual(@as(?[]const u8, null), commit.scope);
    try std.testing.expectEqualStrings("add new feature", commit.description);
    try std.testing.expectEqual(false, commit.breaking);
}

test "parseCommitMessage with scope" {
    var commit = (try parseCommitMessage(std.testing.allocator, "fix(api): fix bug", "abc123")).?;
    defer commit.deinit();

    try std.testing.expectEqual(CommitType.fix, commit.commit_type);
    try std.testing.expectEqualStrings("api", commit.scope.?);
    try std.testing.expectEqualStrings("fix bug", commit.description);
}

test "parseCommitMessage breaking" {
    var commit = (try parseCommitMessage(std.testing.allocator, "feat!: breaking change", "abc123")).?;
    defer commit.deinit();

    try std.testing.expectEqual(CommitType.feat, commit.commit_type);
    try std.testing.expectEqual(true, commit.breaking);
}

test "parseCommitMessage with body breaking" {
    const msg = "feat: new feature\n\nBREAKING CHANGE: removes old API";
    var commit = (try parseCommitMessage(std.testing.allocator, msg, "abc123")).?;
    defer commit.deinit();

    try std.testing.expectEqual(true, commit.breaking);
}

test "determineBumpType" {
    var commits = [_]ConventionalCommit{
        try ConventionalCommit.init(std.testing.allocator, .feat, null, "test", null, false, "a"),
        try ConventionalCommit.init(std.testing.allocator, .fix, null, "test", null, false, "b"),
    };
    defer for (&commits) |*c| c.deinit();

    try std.testing.expectEqual(types.BumpType.minor, determineBumpType(&commits));
}

test "determineBumpType breaking" {
    var commits = [_]ConventionalCommit{
        try ConventionalCommit.init(std.testing.allocator, .feat, null, "test", null, true, "a"),
    };
    defer for (&commits) |*c| c.deinit();

    try std.testing.expectEqual(types.BumpType.major, determineBumpType(&commits));
}
