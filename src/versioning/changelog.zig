const std = @import("std");
const conventional = @import("conventional.zig");
const CommitType = conventional.CommitType;
const ConventionalCommit = conventional.ConventionalCommit;

/// Generate CHANGELOG.md content from commits
pub fn generateChangelog(
    allocator: std.mem.Allocator,
    version: []const u8,
    commits: []const ConventionalCommit,
    date: ?[]const u8,
) ![]const u8 {
    var output = std.ArrayList(u8){};
    errdefer output.deinit(allocator);

    const writer = output.writer(allocator);

    // Header
    const date_str = date orelse try getCurrentDate(allocator);
    defer if (date == null) allocator.free(date_str);

    try writer.print("## [{s}] - {s}\n\n", .{ version, date_str });

    // Group commits by type
    var breaking = std.ArrayList(*const ConventionalCommit){};
    defer breaking.deinit(allocator);
    var features = std.ArrayList(*const ConventionalCommit){};
    defer features.deinit(allocator);
    var fixes = std.ArrayList(*const ConventionalCommit){};
    defer fixes.deinit(allocator);
    var perf = std.ArrayList(*const ConventionalCommit){};
    defer perf.deinit(allocator);
    var other = std.ArrayList(*const ConventionalCommit){};
    defer other.deinit(allocator);

    for (commits) |*commit| {
        if (commit.breaking) {
            try breaking.append(allocator, commit);
        } else {
            switch (commit.commit_type) {
                .feat => try features.append(allocator, commit),
                .fix => try fixes.append(allocator, commit),
                .perf => try perf.append(allocator, commit),
                else => try other.append(allocator, commit),
            }
        }
    }

    // Write sections
    if (breaking.items.len > 0) {
        try writer.writeAll("### ⚠ BREAKING CHANGES\n\n");
        for (breaking.items) |commit| {
            try writeCommitEntry(writer, commit);
        }
        try writer.writeAll("\n");
    }

    if (features.items.len > 0) {
        try writer.writeAll("### Features\n\n");
        for (features.items) |commit| {
            try writeCommitEntry(writer, commit);
        }
        try writer.writeAll("\n");
    }

    if (fixes.items.len > 0) {
        try writer.writeAll("### Bug Fixes\n\n");
        for (fixes.items) |commit| {
            try writeCommitEntry(writer, commit);
        }
        try writer.writeAll("\n");
    }

    if (perf.items.len > 0) {
        try writer.writeAll("### Performance\n\n");
        for (perf.items) |commit| {
            try writeCommitEntry(writer, commit);
        }
        try writer.writeAll("\n");
    }

    if (other.items.len > 0) {
        try writer.writeAll("### Other Changes\n\n");
        for (other.items) |commit| {
            try writeCommitEntry(writer, commit);
        }
        try writer.writeAll("\n");
    }

    return output.toOwnedSlice(allocator);
}

fn writeCommitEntry(writer: anytype, commit: *const ConventionalCommit) !void {
    if (commit.scope) |scope| {
        try writer.print("- **{s}**: {s} ([{s}])\n", .{
            scope,
            commit.description,
            commit.hash[0..@min(7, commit.hash.len)],
        });
    } else {
        try writer.print("- {s} ([{s}])\n", .{
            commit.description,
            commit.hash[0..@min(7, commit.hash.len)],
        });
    }
}

fn getCurrentDate(allocator: std.mem.Allocator) ![]const u8 {
    const timestamp = std.time.timestamp();
    const epoch_seconds = @as(u64, @intCast(timestamp));

    // Calculate year, month, day from epoch seconds
    const seconds_per_day = 86400;
    const days_since_epoch = epoch_seconds / seconds_per_day;

    // Simple algorithm for date calculation
    // Epoch is 1970-01-01
    var year: u32 = 1970;
    var days_remaining = days_since_epoch;

    while (true) {
        const days_in_year = if (isLeapYear(year)) @as(u64, 366) else @as(u64, 365);
        if (days_remaining < days_in_year) break;
        days_remaining -= days_in_year;
        year += 1;
    }

    const days_in_months = if (isLeapYear(year))
        [_]u32{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    else
        [_]u32{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

    var month: u32 = 1;
    for (days_in_months) |days_in_month| {
        if (days_remaining < days_in_month) break;
        days_remaining -= days_in_month;
        month += 1;
    }

    const day = days_remaining + 1;

    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{ year, month, day });
}

fn isLeapYear(year: u32) bool {
    if (year % 4 != 0) return false;
    if (year % 100 != 0) return true;
    if (year % 400 != 0) return false;
    return true;
}

/// Prepend new version section to existing CHANGELOG.md
pub fn prependToChangelog(
    allocator: std.mem.Allocator,
    changelog_path: []const u8,
    new_section: []const u8,
) !void {
    // Read existing changelog (if it exists)
    var existing_content: []const u8 = "";
    const file = std.fs.cwd().openFile(changelog_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            // Create new changelog
            const header = "# Changelog\n\nAll notable changes to this project will be documented in this file.\n\n";
            const full_content = try std.fmt.allocPrint(allocator, "{s}{s}", .{ header, new_section });
            defer allocator.free(full_content);
            try std.fs.cwd().writeFile(.{ .sub_path = changelog_path, .data = full_content });
            return;
        }
        return err;
    };
    defer file.close();

    existing_content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(existing_content);

    // Find where to insert (after first header)
    var insert_pos: usize = 0;
    var lines = std.mem.splitScalar(u8, existing_content, '\n');
    var line_count: usize = 0;

    while (lines.next()) |line| {
        line_count += 1;
        insert_pos += line.len + 1; // +1 for newline

        // Skip header lines and initial description
        if (line.len > 0 and line[0] == '#' and line_count > 1) {
            insert_pos -= line.len + 1; // Back up to before this line
            break;
        }
    }

    // Build new content
    const new_content = try std.fmt.allocPrint(
        allocator,
        "{s}{s}{s}",
        .{ existing_content[0..insert_pos], new_section, existing_content[insert_pos..] },
    );
    defer allocator.free(new_content);

    // Write back
    try std.fs.cwd().writeFile(.{ .sub_path = changelog_path, .data = new_content });
}

test "generateChangelog basic" {
    var commits = [_]ConventionalCommit{
        try ConventionalCommit.init(std.testing.allocator, .feat, null, "add feature", null, false, "abc1234"),
        try ConventionalCommit.init(std.testing.allocator, .fix, "api", "fix bug", null, false, "def5678"),
    };
    defer for (&commits) |*c| c.deinit();

    const changelog = try generateChangelog(std.testing.allocator, "1.0.0", &commits, "2026-02-22");
    defer std.testing.allocator.free(changelog);

    try std.testing.expect(std.mem.indexOf(u8, changelog, "## [1.0.0] - 2026-02-22") != null);
    try std.testing.expect(std.mem.indexOf(u8, changelog, "### Features") != null);
    try std.testing.expect(std.mem.indexOf(u8, changelog, "add feature") != null);
    try std.testing.expect(std.mem.indexOf(u8, changelog, "### Bug Fixes") != null);
    try std.testing.expect(std.mem.indexOf(u8, changelog, "fix bug") != null);
}

test "generateChangelog breaking" {
    var commits = [_]ConventionalCommit{
        try ConventionalCommit.init(std.testing.allocator, .feat, null, "breaking change", null, true, "abc1234"),
    };
    defer for (&commits) |*c| c.deinit();

    const changelog = try generateChangelog(std.testing.allocator, "2.0.0", &commits, "2026-02-22");
    defer std.testing.allocator.free(changelog);

    try std.testing.expect(std.mem.indexOf(u8, changelog, "### ⚠ BREAKING CHANGES") != null);
    try std.testing.expect(std.mem.indexOf(u8, changelog, "breaking change") != null);
}

test "getCurrentDate" {
    const date = try getCurrentDate(std.testing.allocator);
    defer std.testing.allocator.free(date);

    // Should be in YYYY-MM-DD format
    try std.testing.expectEqual(@as(usize, 10), date.len);
    try std.testing.expectEqual(@as(u8, '-'), date[4]);
    try std.testing.expectEqual(@as(u8, '-'), date[7]);
}

test "isLeapYear" {
    try std.testing.expectEqual(true, isLeapYear(2000));
    try std.testing.expectEqual(false, isLeapYear(1900));
    try std.testing.expectEqual(true, isLeapYear(2024));
    try std.testing.expectEqual(false, isLeapYear(2023));
}
