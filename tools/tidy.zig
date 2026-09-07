//! Kingdom reference `tidy` lint: line length, doc headers, function length
//! (with a shrink-only baseline), a substring ban list, and file length.
//! Single file, zero dependencies. Compiles under Zig 0.15.2 and 0.16.0 by
//! comptime-branching on `builtin.zig_version` wherever the filesystem API
//! diverges (`std.fs` on 0.15, `std.Io.Dir`/`std.Io.File` on 0.16).

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const zig16 = builtin.zig_version.minor >= 16;

const max_line_len: usize = 100;
const max_fn_len: usize = 70;
const max_file_len: usize = 800;
const max_file_bytes: usize = 8 * 1024 * 1024;

const Severity = enum { fail, warn };

const Finding = struct {
    path: []const u8,
    line: usize,
    rule: []const u8,
    message: []const u8,
    replacement: ?[]const u8 = null,
    severity: Severity = .fail,
};

const Options = struct {
    root: []const u8 = ".",
    baseline_path: []const u8 = "./tidy_baseline.txt",
};

/// Parses `--root <dir>` and `--baseline <path>` from a raw argument list
/// (program name already stripped). Unknown flags are ignored so callers can
/// grow the flag set without breaking existing invocations.
pub fn parseArgs(args: []const []const u8) Options {
    std.debug.assert(args.len < 1_000_000); // sanity: never a runaway argv
    var opts = Options{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--root") and i + 1 < args.len) {
            opts.root = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--baseline") and i + 1 < args.len) {
            opts.baseline_path = args[i + 1];
            i += 1;
        }
    }
    return opts;
}

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

/// Finds the name of a function declared as `fn name(` on this line (with no
/// space between the name and the opening paren, per Zig style). Returns
/// null when the line does not open a named function.
pub fn extractFnName(line: []const u8) ?[]const u8 {
    const idx = std.mem.indexOf(u8, line, "fn ") orelse return null;
    if (idx > 0 and isIdentChar(line[idx - 1])) return null;
    var i = idx + 3;
    while (i < line.len and line[i] == ' ') i += 1;
    const start = i;
    while (i < line.len and isIdentChar(line[i])) i += 1;
    if (i == start or i >= line.len or line[i] != '(') return null;
    return line[start..i];
}

/// Returns true when `line`'s first non-blank content is a multiline string
/// literal marker (`\\`), whose contents must not be scanned for braces.
fn isMultilineStringLine(line: []const u8) bool {
    const trimmed = std.mem.trimStart(u8, line, " \t");
    return std.mem.startsWith(u8, trimmed, "\\\\");
}

/// Net change in brace depth contributed by one line, ignoring braces that
/// appear inside string/char literals or after a `//` line comment.
pub fn braceDelta(line: []const u8) i32 {
    if (isMultilineStringLine(line)) return 0;
    var delta: i32 = 0;
    var in_string = false;
    var in_char = false;
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        const c = line[i];
        if (in_string) {
            if (c == '\\') i += 1 else if (c == '"') {
                in_string = false;
            }
            continue;
        }
        if (in_char) {
            if (c == '\\') i += 1 else if (c == '\'') {
                in_char = false;
            }
            continue;
        }
        switch (c) {
            '/' => if (i + 1 < line.len and line[i + 1] == '/') break,
            '"' => in_string = true,
            '\'' => in_char = true,
            '{' => delta += 1,
            '}' => delta -= 1,
            else => {},
        }
    }
    return delta;
}

/// Measures the total line span (inclusive) of the function whose `fn
/// name(` line is `lines[start_idx]`, by tracking brace depth from that line
/// to the line where it first returns to zero. Returns null if the function
/// body never closes within `lines` (malformed/truncated input).
pub fn measureFunctionLines(lines: []const []const u8, start_idx: usize) ?usize {
    std.debug.assert(start_idx < lines.len);
    var depth: i32 = 0;
    var started = false;
    var i = start_idx;
    while (i < lines.len) : (i += 1) {
        const new_depth = depth + braceDelta(lines[i]);
        if (!started and new_depth > 0) started = true;
        depth = new_depth;
        if (started and depth <= 0) return i - start_idx + 1;
    }
    return null;
}

/// Splits `content` into lines (without trailing `\n` or `\r`), as slices
/// into `content`. Caller frees the returned slice with `allocator`.
pub fn splitLines(allocator: Allocator, content: []const u8) ![][]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer out.deinit(allocator);
    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |raw| {
        const line = if (raw.len > 0 and raw[raw.len - 1] == '\r') raw[0 .. raw.len - 1] else raw;
        try out.append(allocator, line);
    }
    if (out.items.len > 0 and out.items[out.items.len - 1].len == 0 and
        content.len > 0 and content[content.len - 1] == '\n')
    {
        _ = out.pop();
    }
    return out.toOwnedSlice(allocator);
}

fn isUnderSrc(path: []const u8) bool {
    return std.mem.startsWith(u8, path, "src/");
}

fn underDir(path: []const u8, dir: []const u8) bool {
    return std.mem.startsWith(u8, path, dir) and
        path.len > dir.len and path[dir.len] == '/';
}

fn basenameOf(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |idx| return path[idx + 1 ..];
    return path;
}

fn isMainZig(path: []const u8) bool {
    return std.mem.eql(u8, path, "src/main.zig");
}

fn addFinding(
    list: *std.ArrayList(Finding),
    allocator: Allocator,
    f: Finding,
) !void {
    try list.append(allocator, f);
}

/// Builds the ratchet-baseline key for a whole-file rule count: `path:rule`.
/// Rule names always contain a `-`, which can never appear in a Zig
/// identifier, so this key never collides with a `checkFunctionLength` key
/// (`path:function_name`) in the same `Baseline` map.
fn ratchetKey(allocator: Allocator, path: []const u8, rule: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}:{s}", .{ path, rule });
}

/// Records `count` occurrences of `rule` in `path` into `actual_out` (for
/// `reconcileBaseline` to compare afterward) and, when `count` exceeds the
/// baseline's recorded allowance for this `path`+`rule` (0 when absent),
/// appends one aggregate failing `Finding` — pre-existing debt up to the
/// baseline count is silently allowed, matching `checkFunctionLength`.
fn ratchetCount(
    out: *std.ArrayList(Finding),
    allocator: Allocator,
    path: []const u8,
    rule: []const u8,
    count: usize,
    first_line: usize,
    baseline: Baseline,
    actual_out: *std.StringHashMap(ActualLen),
) !void {
    std.debug.assert(first_line >= 1);
    const key = try ratchetKey(allocator, path, rule);
    const allowed = baseline.get(key) orelse 0;
    const gop = try actual_out.getOrPut(key);
    if (gop.found_existing) allocator.free(key);
    gop.value_ptr.* = .{ .line = first_line, .len = count };
    if (count > allowed) {
        const msg = try std.fmt.allocPrint(
            allocator,
            "{d} {s} violation(s) (baseline allows {d})",
            .{ count, rule, allowed },
        );
        try addFinding(out, allocator, .{
            .path = path,
            .line = first_line,
            .rule = rule,
            .message = msg,
            .replacement = "fix new violations, or list this file in tidy_baseline.txt",
        });
    }
}

/// Check 1: every line must be at most `max_line_len` Unicode code points
/// (not bytes). Pre-existing over-length lines in a file already listed in
/// the baseline (`path:line-length:N`) are allowed up to `N`; see
/// `ratchetCount`.
pub fn checkLineLength(
    allocator: Allocator,
    path: []const u8,
    lines: []const []const u8,
    baseline: Baseline,
    actual_out: *std.StringHashMap(ActualLen),
) ![]Finding {
    std.debug.assert(path.len > 0);
    var out: std.ArrayList(Finding) = .empty;
    errdefer out.deinit(allocator);
    var count: usize = 0;
    var first_line: usize = 1;
    for (lines, 0..) |line, idx| {
        const n = std.unicode.utf8CountCodepoints(line) catch line.len;
        if (n > max_line_len) {
            if (count == 0) first_line = idx + 1;
            count += 1;
        }
    }
    if (count > 0) {
        try ratchetCount(&out, allocator, path, "line-length", count, first_line, baseline, actual_out);
    }
    return out.toOwnedSlice(allocator);
}

/// Check 2: the first line of every `.zig` file under `src/` must start
/// with a top-of-file doc comment (`//!`). A missing header is a 0/1 count
/// under the same ratchet as `checkLineLength`.
pub fn checkDocHeader(
    allocator: Allocator,
    path: []const u8,
    lines: []const []const u8,
    baseline: Baseline,
    actual_out: *std.StringHashMap(ActualLen),
) ![]Finding {
    var out: std.ArrayList(Finding) = .empty;
    errdefer out.deinit(allocator);
    if (!isUnderSrc(path)) return out.toOwnedSlice(allocator);
    const first = if (lines.len > 0) lines[0] else "";
    const count: usize = if (std.mem.startsWith(u8, first, "//!")) 0 else 1;
    if (count > 0) {
        try ratchetCount(&out, allocator, path, "doc-header", count, 1, baseline, actual_out);
    }
    return out.toOwnedSlice(allocator);
}

/// Check 5: files longer than `max_file_len` lines are a WARNING (does not
/// fail the run on its own).
pub fn checkFileLength(
    allocator: Allocator,
    path: []const u8,
    lines: []const []const u8,
) ![]Finding {
    var out: std.ArrayList(Finding) = .empty;
    errdefer out.deinit(allocator);
    if (lines.len > max_file_len) {
        const msg = try std.fmt.allocPrint(
            allocator,
            "file is {d} lines (soft limit {d})",
            .{ lines.len, max_file_len },
        );
        try addFinding(&out, allocator, .{
            .path = path,
            .line = lines.len,
            .rule = "file-length",
            .message = msg,
            .severity = .warn,
        });
    }
    return out.toOwnedSlice(allocator);
}

const ActualLen = struct { line: usize, len: usize };

/// Parsed `tidy_baseline.txt`: maps `"path:function_name"` to the recorded
/// line count. The baseline may only shrink over time (see
/// `reconcileBaseline`).
const Baseline = struct {
    entries: std.StringHashMap(usize),

    fn init(allocator: Allocator) Baseline {
        return .{ .entries = std.StringHashMap(usize).init(allocator) };
    }

    fn deinit(self: *Baseline, allocator: Allocator) void {
        var it = self.entries.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        self.entries.deinit();
    }

    fn get(self: Baseline, key: []const u8) ?usize {
        return self.entries.get(key);
    }

    /// Parses `path:function_name:lines` lines. Blank lines and lines
    /// starting with `#` are ignored.
    fn parse(allocator: Allocator, content: []const u8) !Baseline {
        var self = Baseline.init(allocator);
        errdefer self.deinit(allocator);
        var it = std.mem.splitScalar(u8, content, '\n');
        while (it.next()) |raw| {
            const line = std.mem.trim(u8, raw, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;
            try self.parseLine(allocator, line);
        }
        return self;
    }

    fn parseLine(self: *Baseline, allocator: Allocator, line: []const u8) !void {
        const last_colon = std.mem.lastIndexOfScalar(u8, line, ':') orelse return;
        const lines_str = line[last_colon + 1 ..];
        const rest = line[0..last_colon];
        const mid_colon = std.mem.lastIndexOfScalar(u8, rest, ':') orelse return;
        const lines_n = std.fmt.parseInt(usize, lines_str, 10) catch return;
        const key = try allocator.dupe(u8, rest);
        _ = mid_colon;
        const gop = try self.entries.getOrPut(key);
        if (gop.found_existing) {
            allocator.free(key);
        }
        gop.value_ptr.* = lines_n;
    }
};

/// Check 3: any `fn` whose body spans more than `max_fn_len` lines fails,
/// unless listed in the baseline. Also records every function's actual
/// current span (regardless of length) into `actual_out`, keyed by
/// `"path:function_name"`, for `reconcileBaseline` to compare afterward.
pub fn checkFunctionLength(
    allocator: Allocator,
    path: []const u8,
    lines: []const []const u8,
    baseline: Baseline,
    actual_out: *std.StringHashMap(ActualLen),
) ![]Finding {
    var out: std.ArrayList(Finding) = .empty;
    errdefer out.deinit(allocator);
    var idx: usize = 0;
    while (idx < lines.len) : (idx += 1) {
        const name = extractFnName(lines[idx]) orelse continue;
        const len = measureFunctionLines(lines, idx) orelse continue;
        const key = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ path, name });
        const gop = try actual_out.getOrPut(key);
        if (gop.found_existing) {
            if (len > gop.value_ptr.len) gop.value_ptr.* = .{ .line = idx + 1, .len = len };
        } else {
            gop.value_ptr.* = .{ .line = idx + 1, .len = len };
        }
        if (len > max_fn_len and baseline.get(key) == null) {
            try addFunctionLengthFinding(&out, allocator, path, idx + 1, name, len);
        }
        // `key`'s bytes are read by `baseline.get` above; only free it after that read,
        // and only when `actual_out` didn't take ownership of this allocation.
        if (gop.found_existing) allocator.free(key);
    }
    return out.toOwnedSlice(allocator);
}

fn addFunctionLengthFinding(
    out: *std.ArrayList(Finding),
    allocator: Allocator,
    path: []const u8,
    line: usize,
    name: []const u8,
    len: usize,
) !void {
    const msg = try std.fmt.allocPrint(
        allocator,
        "fn `{s}` is {d} lines (limit {d})",
        .{ name, len, max_fn_len },
    );
    try addFinding(out, allocator, .{
        .path = path,
        .line = line,
        .rule = "function-length",
        .message = msg,
        .replacement = "shorten it, or add `path:fn:lines` to tidy_baseline.txt",
    });
}

const BanId = enum {
    catch_unreachable,
    panic_call,
    debug_print,
    time_call,
    crypto_random,
    self_alias,
    usingnamespace_kw,
    anyerror_pub,
    eq_error,
    neq_error,
    fixme_comment,
    dbg_call,
};

const BanRule = struct { id: BanId, needle: []const u8, replacement: []const u8 };

const ban_rules = [_]BanRule{
    .{
        .id = .catch_unreachable,
        .needle = "catch unreachable",
        .replacement = "handle the error, or add `// proof:` on this or the previous line",
    },
    .{
        .id = .panic_call,
        .needle = "@panic(",
        .replacement = "return an error instead of panicking (main.zig/bench/tests are exempt)",
    },
    .{
        .id = .debug_print,
        .needle = "std.debug.print(",
        .replacement = "use a real logger instead (main.zig/bench/tests are exempt)",
    },
    .{
        .id = .time_call,
        .needle = "std.time.",
        .replacement = "inject a clock dependency instead of calling std.time from src/",
    },
    .{
        .id = .crypto_random,
        .needle = "std.crypto.random",
        .replacement = "inject a Random dependency instead of a global RNG in src/",
    },
    .{
        .id = .self_alias,
        .needle = "const Self = @This()",
        .replacement = "spell out the type name instead of aliasing Self",
    },
    .{
        .id = .usingnamespace_kw,
        .needle = "usingnamespace",
        .replacement = "import and qualify names explicitly",
    },
    .{
        .id = .anyerror_pub,
        .needle = "anyerror",
        .replacement = "declare a concrete error set on the public fn",
    },
    .{
        .id = .eq_error,
        .needle = " == error.",
        .replacement = "use `catch |err| switch (err) { ... }` instead of comparing errors",
    },
    .{
        .id = .neq_error,
        .needle = " != error.",
        .replacement = "use `catch |err| switch (err) { ... }` instead of comparing errors",
    },
    .{
        .id = .fixme_comment,
        .needle = "// FIXME",
        .replacement = "resolve the issue, or file a tracked TODO with an owner",
    },
    .{
        .id = .dbg_call,
        .needle = "dbg(",
        .replacement = "remove the debug scaffolding before merging",
    },
};

fn exemptFromPanicOrPrint(path: []const u8) bool {
    return isMainZig(path) or underDir(path, "bench") or underDir(path, "tests");
}

fn banApplies(id: BanId, path: []const u8, line: []const u8) bool {
    return switch (id) {
        .panic_call, .debug_print => !exemptFromPanicOrPrint(path),
        .time_call => isUnderSrc(path) and !std.mem.endsWith(u8, basenameOf(path), "main.zig"),
        .crypto_random => isUnderSrc(path),
        .anyerror_pub => std.mem.indexOf(u8, line, "pub fn") != null,
        .catch_unreachable,
        .self_alias,
        .usingnamespace_kw,
        .eq_error,
        .neq_error,
        .fixme_comment,
        .dbg_call,
        => true,
    };
}

fn hasProof(lines: []const []const u8, idx: usize) bool {
    if (std.mem.indexOf(u8, lines[idx], "// proof:") != null) return true;
    return idx > 0 and std.mem.indexOf(u8, lines[idx - 1], "// proof:") != null;
}

/// Check 4: flags each banned substring, printing the paired replacement
/// suggestion. `catch unreachable` is allowed when the same or previous line
/// carries a `// proof:` comment; several rules only apply inside/outside
/// certain directories (see `banApplies`). Pre-existing hits in a file
/// already listed in the baseline (`path:ban-list:N`) are allowed up to `N`
/// total across all ban rules; see `ratchetCount`.
pub fn checkBanList(
    allocator: Allocator,
    path: []const u8,
    lines: []const []const u8,
    baseline: Baseline,
    actual_out: *std.StringHashMap(ActualLen),
) ![]Finding {
    var out: std.ArrayList(Finding) = .empty;
    errdefer out.deinit(allocator);
    var count: usize = 0;
    var first_line: usize = 1;
    for (lines, 0..) |line, idx| {
        for (ban_rules) |rule| {
            if (std.mem.indexOf(u8, line, rule.needle) == null) continue;
            if (!banApplies(rule.id, path, line)) continue;
            if (rule.id == .catch_unreachable and hasProof(lines, idx)) continue;
            if (count == 0) first_line = idx + 1;
            count += 1;
        }
    }
    if (count > 0) {
        try ratchetCount(&out, allocator, path, "ban-list", count, first_line, baseline, actual_out);
    }
    return out.toOwnedSlice(allocator);
}

/// After all files are scanned, compares every baseline entry against the
/// measured `actual` lengths. A function that shrank to <= `max_fn_len`, or
/// that grew past its recorded length, is a stale-baseline failure — the
/// baseline may only shrink. A baseline entry with no matching function is
/// also stale.
pub fn reconcileBaseline(
    allocator: Allocator,
    baseline: Baseline,
    actual: std.StringHashMap(ActualLen),
) ![]Finding {
    var out: std.ArrayList(Finding) = .empty;
    errdefer out.deinit(allocator);
    var it = baseline.entries.iterator();
    while (it.next()) |entry| {
        try reconcileOne(&out, allocator, entry.key_ptr.*, entry.value_ptr.*, actual);
    }
    return out.toOwnedSlice(allocator);
}

fn addStale(
    out: *std.ArrayList(Finding),
    allocator: Allocator,
    path: []const u8,
    line: usize,
    msg: []const u8,
) !void {
    try addFinding(out, allocator, .{
        .path = path,
        .line = line,
        .rule = "stale-baseline",
        .message = msg,
    });
}

/// A key's suffix (after the last `:`) is a rule name (contains `-`, e.g.
/// `line-length`) for a whole-file ratchet count, or a Zig function
/// identifier (never contains `-`) for a `checkFunctionLength` entry — the
/// two share one `Baseline` map but shrink toward different floors (0 vs
/// `max_fn_len`).
fn shrinkFloor(key: []const u8) usize {
    const suffix = if (std.mem.lastIndexOfScalar(u8, key, ':')) |i| key[i + 1 ..] else key;
    return if (std.mem.indexOfScalar(u8, suffix, '-') != null) 0 else max_fn_len;
}

fn reconcileOne(
    out: *std.ArrayList(Finding),
    allocator: Allocator,
    key: []const u8,
    recorded: usize,
    actual: std.StringHashMap(ActualLen),
) !void {
    const path = if (std.mem.lastIndexOfScalar(u8, key, ':')) |i| key[0..i] else key;
    const floor = shrinkFloor(key);
    const found = actual.get(key) orelse {
        const msg = try std.fmt.allocPrint(
            allocator,
            "baseline entry `{s}` matches no function",
            .{key},
        );
        return addStale(out, allocator, path, 1, msg);
    };
    if (found.len <= floor) {
        const msg = try std.fmt.allocPrint(
            allocator,
            "`{s}` shrank to {d}; remove it from tidy_baseline.txt",
            .{ key, found.len },
        );
        try addStale(out, allocator, path, found.line, msg);
    } else if (found.len > recorded) {
        const msg = try std.fmt.allocPrint(
            allocator,
            "`{s}` grew to {d} (baseline says {d}); the baseline may only shrink",
            .{ key, found.len, recorded },
        );
        try addStale(out, allocator, path, found.line, msg);
    }
}

fn appendChecked(findings: *std.ArrayList(Finding), allocator: Allocator, items: []Finding) !void {
    defer allocator.free(items);

    for (items) |f| try findings.append(allocator, f);
}

/// Runs all five checks over one file's already-split `lines`, appending
/// every finding into `findings` and recording function spans into
/// `actual_out` for the caller's later `reconcileBaseline` pass.
pub fn lintLines(
    allocator: Allocator,
    path: []const u8,
    lines: []const []const u8,
    baseline: Baseline,
    actual_out: *std.StringHashMap(ActualLen),
    findings: *std.ArrayList(Finding),
) !void {
    const len_findings = try checkLineLength(allocator, path, lines, baseline, actual_out);
    try appendChecked(findings, allocator, len_findings);
    const doc_findings = try checkDocHeader(allocator, path, lines, baseline, actual_out);
    try appendChecked(findings, allocator, doc_findings);
    const fn_findings = try checkFunctionLength(allocator, path, lines, baseline, actual_out);
    try appendChecked(findings, allocator, fn_findings);
    const ban_findings = try checkBanList(allocator, path, lines, baseline, actual_out);
    try appendChecked(findings, allocator, ban_findings);
    try appendChecked(findings, allocator, try checkFileLength(allocator, path, lines));
}

/// Convenience wrapper over `lintLines` that splits raw file `content` first.
pub fn lintFile(
    allocator: Allocator,
    path: []const u8,
    content: []const u8,
    baseline: Baseline,
    actual_out: *std.StringHashMap(ActualLen),
    findings: *std.ArrayList(Finding),
) !void {
    const lines = try splitLines(allocator, content);
    defer allocator.free(lines);

    try lintLines(allocator, path, lines, baseline, actual_out, findings);
}

fn anyFailing(findings: []const Finding) bool {
    for (findings) |f| {
        if (f.severity == .fail) return true;
    }
    return false;
}

/// Renders every finding as `path:line: rule: message [replacement]` (the
/// bracketed replacement only when the rule supplies one), followed by a
/// one-line summary. Caller frees the result with `allocator`.
pub fn formatFindings(allocator: Allocator, findings: []const Finding) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    var fails: usize = 0;
    for (findings) |f| {
        if (f.severity == .fail) fails += 1;
        try formatOneFinding(&buf, allocator, f);
    }
    try buf.print(
        allocator,
        "tidy: {d} finding(s), {d} failing, {d} warning(s)\n",
        .{ findings.len, fails, findings.len - fails },
    );
    return buf.toOwnedSlice(allocator);
}

fn formatOneFinding(buf: *std.ArrayList(u8), allocator: Allocator, f: Finding) !void {
    if (f.replacement) |r| {
        try buf.print(
            allocator,
            "{s}:{d}: {s}: {s} [{s}]\n",
            .{ f.path, f.line, f.rule, f.message, r },
        );
    } else {
        try buf.print(allocator, "{s}:{d}: {s}: {s}\n", .{ f.path, f.line, f.rule, f.message });
    }
}

fn shouldSkipDirName(name: []const u8) bool {
    return std.mem.eql(u8, name, ".zig-cache") or
        std.mem.eql(u8, name, "zig-out") or
        std.mem.eql(u8, name, "zig-pkg");
}

fn shouldCollectFile(name: []const u8) bool {
    return std.mem.endsWith(u8, name, ".zig");
}

const scan_roots = [_][]const u8{ "src", "bench", "tests" };

// ---------------------------------------------------------------------------
// Zig 0.15.2 filesystem glue (std.fs). Never referenced when compiling under
// 0.16 — see the comptime-pruned `pub const main` at the bottom of the file.
// ---------------------------------------------------------------------------

// Mutual recursion defeats Zig's inferred error set, so these two use
// `anyerror` explicitly. Not `pub fn`, so the kingdom's `anyerror` ban (which
// only fires on a public fn) does not apply.
fn walkDir15(
    allocator: Allocator,
    dir: std.fs.Dir,
    prefix: []const u8,
    out: *std.ArrayList([]const u8),
) anyerror!void {
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .directory and shouldSkipDirName(entry.name)) continue;
        switch (entry.kind) {
            .directory => try descendDir15(allocator, dir, prefix, entry.name, out),
            .file => try maybeAddFile(allocator, prefix, entry.name, out),
            else => {},
        }
    }
}

fn descendDir15(
    allocator: Allocator,
    parent: std.fs.Dir,
    prefix: []const u8,
    name: []const u8,
    out: *std.ArrayList([]const u8),
) anyerror!void {
    var sub = try parent.openDir(name, .{ .iterate = true });
    defer sub.close();

    const new_prefix = try std.fmt.allocPrint(allocator, "{s}{s}/", .{ prefix, name });
    try walkDir15(allocator, sub, new_prefix, out);
}

fn maybeAddFile(
    allocator: Allocator,
    prefix: []const u8,
    name: []const u8,
    out: *std.ArrayList([]const u8),
) !void {
    if (!shouldCollectFile(name)) return;
    const rel = try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, name });
    try out.append(allocator, rel);
}

fn collectTopLevel15(
    allocator: Allocator,
    root: std.fs.Dir,
    name: []const u8,
    out: *std.ArrayList([]const u8),
) !void {
    root.access(name, .{}) catch return;
    try out.append(allocator, try allocator.dupe(u8, name));
}

fn collectSubtree15(
    allocator: Allocator,
    root: std.fs.Dir,
    name: []const u8,
    out: *std.ArrayList([]const u8),
) !void {
    var dir = root.openDir(name, .{ .iterate = true }) catch return;
    defer dir.close();

    const prefix = try std.fmt.allocPrint(allocator, "{s}/", .{name});
    try walkDir15(allocator, dir, prefix, out);
}

fn collectFiles15(allocator: Allocator, root: std.fs.Dir) ![][]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer out.deinit(allocator);

    try collectTopLevel15(allocator, root, "build.zig", &out);
    for (scan_roots) |name| try collectSubtree15(allocator, root, name, &out);
    return out.toOwnedSlice(allocator);
}

fn loadBaseline15(allocator: Allocator, root: std.fs.Dir, path: []const u8) !Baseline {
    const content = root.readFileAlloc(allocator, path, max_file_bytes) catch |err| switch (err) {
        error.FileNotFound => return Baseline.init(allocator),
        else => return err,
    };
    return Baseline.parse(allocator, content);
}

fn main15() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const raw_args = try std.process.argsAlloc(gpa);
    const opts = parseArgs(raw_args[@min(1, raw_args.len)..]);

    var root_dir = try std.fs.cwd().openDir(opts.root, .{ .iterate = true });
    defer root_dir.close();

    const baseline = try loadBaseline15(gpa, root_dir, opts.baseline_path);
    const paths = try collectFiles15(gpa, root_dir);

    var findings: std.ArrayList(Finding) = .empty;
    var actual = std.StringHashMap(ActualLen).init(gpa);
    for (paths) |p| {
        const content = root_dir.readFileAlloc(gpa, p, max_file_bytes) catch continue;
        try lintFile(gpa, p, content, baseline, &actual, &findings);
    }
    try appendChecked(&findings, gpa, try reconcileBaseline(gpa, baseline, actual));

    const report = try formatFindings(gpa, findings.items);
    try std.fs.File.stdout().writeAll(report);
    if (anyFailing(findings.items)) std.posix.exit(1);
}

// ---------------------------------------------------------------------------
// Zig 0.16.0 filesystem glue (std.Io.Dir / std.Io.File). Never referenced
// when compiling under 0.15.2.
// ---------------------------------------------------------------------------

// Mutual recursion defeats Zig's inferred error set, so these two use
// `anyerror` explicitly. Not `pub fn`, so the kingdom's `anyerror` ban (which
// only fires on a public fn) does not apply.
fn walkDir16(
    allocator: Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    prefix: []const u8,
    out: *std.ArrayList([]const u8),
) anyerror!void {
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind == .directory and shouldSkipDirName(entry.name)) continue;
        switch (entry.kind) {
            .directory => try descendDir16(allocator, io, dir, prefix, entry.name, out),
            .file => try maybeAddFile(allocator, prefix, entry.name, out),
            else => {},
        }
    }
}

fn descendDir16(
    allocator: Allocator,
    io: std.Io,
    parent: std.Io.Dir,
    prefix: []const u8,
    name: []const u8,
    out: *std.ArrayList([]const u8),
) anyerror!void {
    var sub = try parent.openDir(io, name, .{ .iterate = true });
    defer sub.close(io);

    const new_prefix = try std.fmt.allocPrint(allocator, "{s}{s}/", .{ prefix, name });
    try walkDir16(allocator, io, sub, new_prefix, out);
}

fn collectTopLevel16(
    allocator: Allocator,
    io: std.Io,
    root: std.Io.Dir,
    name: []const u8,
    out: *std.ArrayList([]const u8),
) !void {
    root.access(io, name, .{}) catch return;
    try out.append(allocator, try allocator.dupe(u8, name));
}

fn collectSubtree16(
    allocator: Allocator,
    io: std.Io,
    root: std.Io.Dir,
    name: []const u8,
    out: *std.ArrayList([]const u8),
) !void {
    var dir = root.openDir(io, name, .{ .iterate = true }) catch return;
    defer dir.close(io);

    const prefix = try std.fmt.allocPrint(allocator, "{s}/", .{name});
    try walkDir16(allocator, io, dir, prefix, out);
}

fn collectFiles16(allocator: Allocator, io: std.Io, root: std.Io.Dir) ![][]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer out.deinit(allocator);

    try collectTopLevel16(allocator, io, root, "build.zig", &out);
    for (scan_roots) |name| try collectSubtree16(allocator, io, root, name, &out);
    return out.toOwnedSlice(allocator);
}

fn loadBaseline16(allocator: Allocator, io: std.Io, root: std.Io.Dir, path: []const u8) !Baseline {
    const limit: std.Io.Limit = .limited(max_file_bytes);
    const content = root.readFileAlloc(io, path, allocator, limit) catch |err| switch (err) {
        error.FileNotFound => return Baseline.init(allocator),
        else => return err,
    };
    return Baseline.parse(allocator, content);
}

fn collectArgs16(allocator: Allocator, args: std.process.Args) ![][]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer out.deinit(allocator);

    var it = try std.process.Args.Iterator.initAllocator(args, allocator);
    defer it.deinit();

    var first = true;
    while (it.next()) |arg| {
        if (first) {
            first = false;
        } else {
            try out.append(allocator, try allocator.dupe(u8, arg));
        }
    }
    return out.toOwnedSlice(allocator);
}

fn main16(init: std.process.Init) !void {
    const gpa = init.arena.allocator();
    const io = init.io;

    const raw_args = try collectArgs16(gpa, init.minimal.args);
    const opts = parseArgs(raw_args);

    var root_dir = try std.Io.Dir.cwd().openDir(io, opts.root, .{ .iterate = true });
    defer root_dir.close(io);

    const baseline = try loadBaseline16(gpa, io, root_dir, opts.baseline_path);
    const paths = try collectFiles16(gpa, io, root_dir);

    var findings: std.ArrayList(Finding) = .empty;
    var actual = std.StringHashMap(ActualLen).init(gpa);
    for (paths) |p| {
        const content = root_dir.readFileAlloc(io, p, gpa, .limited(max_file_bytes)) catch continue;
        try lintFile(gpa, p, content, baseline, &actual, &findings);
    }
    try appendChecked(&findings, gpa, try reconcileBaseline(gpa, baseline, actual));

    const report = try formatFindings(gpa, findings.items);
    try std.Io.File.stdout().writeStreamingAll(io, report);
    if (anyFailing(findings.items)) std.process.exit(1);
}

/// Comptime-selected: only the branch matching the running toolchain is ever
/// referenced, so the other version's filesystem API is never resolved.
pub const main = if (zig16) main16 else main15;

// ---------------------------------------------------------------------------
// Unit tests. All in-memory; no filesystem access, so `zig test tidy.zig`
// exercises every check on both toolchains identically.
// ---------------------------------------------------------------------------

fn freeFindings(allocator: Allocator, findings: []Finding) void {
    for (findings) |f| allocator.free(f.message);
    allocator.free(findings);
}

fn freeActualMap(allocator: Allocator, map: *std.StringHashMap(ActualLen)) void {
    var it = map.keyIterator();
    while (it.next()) |k| allocator.free(k.*);
    map.deinit();
}

/// Test-only wrapper: runs `checkLineLength` against an empty baseline (so
/// every over-length line fails, matching this file's pre-ratchet tests).
fn checkLineLengthT(gpa: Allocator, path: []const u8, lines: []const []const u8) ![]Finding {
    var baseline = Baseline.init(gpa);
    defer baseline.deinit(gpa);
    var actual = std.StringHashMap(ActualLen).init(gpa);
    defer freeActualMap(gpa, &actual);
    return checkLineLength(gpa, path, lines, baseline, &actual);
}

/// Test-only wrapper: runs `checkDocHeader` against an empty baseline.
fn checkDocHeaderT(gpa: Allocator, path: []const u8, lines: []const []const u8) ![]Finding {
    var baseline = Baseline.init(gpa);
    defer baseline.deinit(gpa);
    var actual = std.StringHashMap(ActualLen).init(gpa);
    defer freeActualMap(gpa, &actual);
    return checkDocHeader(gpa, path, lines, baseline, &actual);
}

/// Test-only wrapper: runs `checkBanList` against an empty baseline.
fn checkBanListT(gpa: Allocator, path: []const u8, lines: []const []const u8) ![]Finding {
    var baseline = Baseline.init(gpa);
    defer baseline.deinit(gpa);
    var actual = std.StringHashMap(ActualLen).init(gpa);
    defer freeActualMap(gpa, &actual);
    return checkBanList(gpa, path, lines, baseline, &actual);
}

test "extractFnName finds a named function opener" {
    try std.testing.expectEqualStrings("foo", extractFnName("pub fn foo(a: u32) void {").?);
    try std.testing.expectEqualStrings("bar", extractFnName("fn bar() void {").?);
    try std.testing.expect(extractFnName("const x = fnLike(1);") == null);
    try std.testing.expect(extractFnName("fn (a: u32) void {") == null);
}

test "braceDelta ignores braces in strings and comments" {
    try std.testing.expectEqual(@as(i32, 0), braceDelta("const s = \"{}\";"));
    try std.testing.expectEqual(@as(i32, 0), braceDelta("// a comment with { brace }"));
    try std.testing.expectEqual(@as(i32, 1), braceDelta("fn foo() void {"));
    try std.testing.expectEqual(@as(i32, -1), braceDelta("}"));
}

test "measureFunctionLines counts the inclusive span" {
    const lines = [_][]const u8{
        "fn foo() void {",
        "    doA();",
        "    doB();",
        "}",
    };
    try std.testing.expectEqual(@as(?usize, 4), measureFunctionLines(&lines, 0));
}

test "measureFunctionLines returns null when unterminated" {
    const lines = [_][]const u8{ "fn foo() void {", "    doA();" };
    try std.testing.expectEqual(@as(?usize, null), measureFunctionLines(&lines, 0));
}

test "splitLines trims a trailing newline and CRLF" {
    const lines = try splitLines(std.testing.allocator, "a\r\nb\nc\n");
    defer std.testing.allocator.free(lines);
    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqualStrings("a", lines[0]);
    try std.testing.expectEqualStrings("b", lines[1]);
    try std.testing.expectEqualStrings("c", lines[2]);
}

test "parseArgs reads --root and --baseline, defaults otherwise" {
    const defaults = parseArgs(&.{});
    try std.testing.expectEqualStrings(".", defaults.root);
    try std.testing.expectEqualStrings("./tidy_baseline.txt", defaults.baseline_path);

    const custom = parseArgs(&.{ "--root", "/tmp/x", "--baseline", "b.txt" });
    try std.testing.expectEqualStrings("/tmp/x", custom.root);
    try std.testing.expectEqualStrings("b.txt", custom.baseline_path);
}

test "checkLineLength counts Unicode code points, not bytes" {
    const gpa = std.testing.allocator;
    const long_ascii = "x" ** 101;
    const short_unicode = "é" ** 50; // 100 bytes, 50 code points: must pass.

    const f1 = try checkLineLengthT(gpa, "src/a.zig", &.{long_ascii});
    defer freeFindings(gpa, f1);
    try std.testing.expectEqual(@as(usize, 1), f1.len);

    const f2 = try checkLineLengthT(gpa, "src/a.zig", &.{short_unicode});
    defer freeFindings(gpa, f2);
    try std.testing.expectEqual(@as(usize, 0), f2.len);
}

test "checkDocHeader requires //! only under src/" {
    const gpa = std.testing.allocator;

    const missing = try checkDocHeaderT(gpa, "src/a.zig", &.{"const x = 1;"});
    defer freeFindings(gpa, missing);
    try std.testing.expectEqual(@as(usize, 1), missing.len);

    const outside = try checkDocHeaderT(gpa, "tests/a.zig", &.{"const x = 1;"});
    defer freeFindings(gpa, outside);
    try std.testing.expectEqual(@as(usize, 0), outside.len);

    const ok = try checkDocHeaderT(gpa, "src/a.zig", &.{"//! doc"});
    defer freeFindings(gpa, ok);
    try std.testing.expectEqual(@as(usize, 0), ok.len);
}

test "checkFileLength warns without failing" {
    const gpa = std.testing.allocator;
    var lines: [801][]const u8 = undefined;
    for (&lines) |*l| l.* = "x";

    const findings = try checkFileLength(gpa, "src/a.zig", &lines);
    defer freeFindings(gpa, findings);
    try std.testing.expectEqual(@as(usize, 1), findings.len);
    try std.testing.expectEqual(Severity.warn, findings[0].severity);
}

test "checkBanList flags a bare banned pattern with its replacement" {
    const gpa = std.testing.allocator;
    const findings = try checkBanListT(gpa, "src/a.zig", &.{"    // FIXME: handle this"});
    defer freeFindings(gpa, findings);
    try std.testing.expectEqual(@as(usize, 1), findings.len);
    try std.testing.expect(findings[0].replacement != null);
}

test "checkBanList allows catch unreachable only with a proof comment" {
    const gpa = std.testing.allocator;

    const bare = try checkBanListT(gpa, "src/a.zig", &.{"    x catch unreachable;"});
    defer freeFindings(gpa, bare);
    try std.testing.expectEqual(@as(usize, 1), bare.len);

    const proven = try checkBanListT(gpa, "src/a.zig", &.{
        "    // proof: x is always Foo here",
        "    x catch unreachable;",
    });
    defer freeFindings(gpa, proven);
    try std.testing.expectEqual(@as(usize, 0), proven.len);
}

test "checkBanList exempts @panic and std.debug.print from main.zig/bench/tests" {
    const gpa = std.testing.allocator;

    const in_src = try checkBanListT(gpa, "src/a.zig", &.{"    @panic(\"oops\");"});
    defer freeFindings(gpa, in_src);
    try std.testing.expectEqual(@as(usize, 1), in_src.len);

    const in_main = try checkBanListT(gpa, "src/main.zig", &.{"    @panic(\"oops\");"});
    defer freeFindings(gpa, in_main);
    try std.testing.expectEqual(@as(usize, 0), in_main.len);

    const in_bench = try checkBanListT(gpa, "bench/x.zig", &.{"    std.debug.print(\"x\", .{});"});
    defer freeFindings(gpa, in_bench);
    try std.testing.expectEqual(@as(usize, 0), in_bench.len);
}

test "checkBanList scopes std.time. and std.crypto.random to src/" {
    const gpa = std.testing.allocator;

    const time_line = "    const t = std.time.milliTimestamp();";

    const time_in_src = try checkBanListT(gpa, "src/a.zig", &.{time_line});
    defer freeFindings(gpa, time_in_src);
    try std.testing.expectEqual(@as(usize, 1), time_in_src.len);

    const time_in_main = try checkBanListT(gpa, "src/foo_main.zig", &.{time_line});
    defer freeFindings(gpa, time_in_main);
    try std.testing.expectEqual(@as(usize, 0), time_in_main.len);

    const rand_line = "    const r = std.crypto.random;";
    const rand_outside_src = try checkBanListT(gpa, "tests/a.zig", &.{rand_line});
    defer freeFindings(gpa, rand_outside_src);
    try std.testing.expectEqual(@as(usize, 0), rand_outside_src.len);
}

test "checkBanList flags anyerror only alongside pub fn on the same line" {
    const gpa = std.testing.allocator;

    const flagged = try checkBanListT(gpa, "src/a.zig", &.{"pub fn f() anyerror!void {"});
    defer freeFindings(gpa, flagged);
    try std.testing.expectEqual(@as(usize, 1), flagged.len);

    const not_flagged = try checkBanListT(gpa, "src/a.zig", &.{"fn f() anyerror!void {"});
    defer freeFindings(gpa, not_flagged);
    try std.testing.expectEqual(@as(usize, 0), not_flagged.len);
}

test "checkLineLength allows pre-existing violations up to the baseline count" {
    const gpa = std.testing.allocator;
    const long_line = "x" ** 101;
    const lines = [_][]const u8{ long_line, long_line, "short" };
    var actual = std.StringHashMap(ActualLen).init(gpa);
    defer freeActualMap(gpa, &actual);

    var over_baseline = try Baseline.parse(gpa, "src/a.zig:line-length:1\n");
    defer over_baseline.deinit(gpa);
    const failing = try checkLineLength(gpa, "src/a.zig", &lines, over_baseline, &actual);
    defer freeFindings(gpa, failing);
    try std.testing.expectEqual(@as(usize, 1), failing.len);

    var at_baseline = try Baseline.parse(gpa, "src/a.zig:line-length:2\n");
    defer at_baseline.deinit(gpa);
    const passing = try checkLineLength(gpa, "src/a.zig", &lines, at_baseline, &actual);
    defer freeFindings(gpa, passing);
    try std.testing.expectEqual(@as(usize, 0), passing.len);
    try std.testing.expectEqual(@as(usize, 2), actual.get("src/a.zig:line-length").?.len);
}

test "checkDocHeader passes a missing header covered by the baseline" {
    const gpa = std.testing.allocator;
    var actual = std.StringHashMap(ActualLen).init(gpa);
    defer freeActualMap(gpa, &actual);
    var baseline = try Baseline.parse(gpa, "src/a.zig:doc-header:1\n");
    defer baseline.deinit(gpa);

    const findings = try checkDocHeader(gpa, "src/a.zig", &.{"const x = 1;"}, baseline, &actual);
    defer freeFindings(gpa, findings);
    try std.testing.expectEqual(@as(usize, 0), findings.len);
}

test "checkBanList aggregates multiple hits into one ratcheted finding" {
    const gpa = std.testing.allocator;
    var actual = std.StringHashMap(ActualLen).init(gpa);
    defer freeActualMap(gpa, &actual);
    var baseline = try Baseline.parse(gpa, "src/a.zig:ban-list:2\n");
    defer baseline.deinit(gpa);
    const lines = [_][]const u8{ "x catch unreachable;", "y catch unreachable;" };

    const findings = try checkBanList(gpa, "src/a.zig", &lines, baseline, &actual);
    defer freeFindings(gpa, findings);
    try std.testing.expectEqual(@as(usize, 0), findings.len);
    try std.testing.expectEqual(@as(usize, 2), actual.get("src/a.zig:ban-list").?.len);
}

test "reconcileBaseline removes a rule-count entry only once it reaches zero" {
    const gpa = std.testing.allocator;
    var baseline = try Baseline.parse(gpa, "src/a.zig:line-length:3\n");
    defer baseline.deinit(gpa);
    var still_present = std.StringHashMap(ActualLen).init(gpa);
    defer still_present.deinit();
    try still_present.put("src/a.zig:line-length", .{ .line = 1, .len = 1 });

    const findings = try reconcileBaseline(gpa, baseline, still_present);
    defer freeFindings(gpa, findings);
    try std.testing.expectEqual(@as(usize, 0), findings.len);

    var zeroed = std.StringHashMap(ActualLen).init(gpa);
    defer zeroed.deinit();
    try zeroed.put("src/a.zig:line-length", .{ .line = 1, .len = 0 });

    const stale = try reconcileBaseline(gpa, baseline, zeroed);
    defer freeFindings(gpa, stale);
    try std.testing.expectEqual(@as(usize, 1), stale.len);
}

fn longFnLines(comptime body_lines: usize) [body_lines + 2][]const u8 {
    var lines: [body_lines + 2][]const u8 = undefined;
    lines[0] = "fn tooLong() void {";
    for (1..body_lines + 1) |i| lines[i] = "    doWork();";
    lines[body_lines + 1] = "}";
    return lines;
}

test "checkFunctionLength records the longest of two same-named functions" {
    const gpa = std.testing.allocator;
    const short = longFnLines(5); // "tooLong", 7 lines total, scanned first.
    const long = longFnLines(90); // same name, 92 lines, scanned second.
    var lines: [short.len + long.len][]const u8 = undefined;
    @memcpy(lines[0..short.len], &short);
    @memcpy(lines[short.len..], &long);
    var actual = std.StringHashMap(ActualLen).init(gpa);
    defer freeActualMap(gpa, &actual);
    var baseline = Baseline.init(gpa);
    defer baseline.deinit(gpa);

    const findings = try checkFunctionLength(gpa, "src/a.zig", &lines, baseline, &actual);
    defer freeFindings(gpa, findings);
    try std.testing.expectEqual(@as(usize, 92), actual.get("src/a.zig:tooLong").?.len);
}

test "checkFunctionLength fails an unbaselined long function" {
    const gpa = std.testing.allocator;
    const lines = longFnLines(70);
    var actual = std.StringHashMap(ActualLen).init(gpa);
    defer freeActualMap(gpa, &actual);
    var baseline = Baseline.init(gpa);
    defer baseline.deinit(gpa);

    const findings = try checkFunctionLength(gpa, "src/a.zig", &lines, baseline, &actual);
    defer freeFindings(gpa, findings);
    try std.testing.expectEqual(@as(usize, 1), findings.len);
    try std.testing.expectEqual(@as(usize, 72), actual.get("src/a.zig:tooLong").?.len);
}

test "checkFunctionLength passes a long function covered by the baseline" {
    const gpa = std.testing.allocator;
    const lines = longFnLines(70);
    var actual = std.StringHashMap(ActualLen).init(gpa);
    defer freeActualMap(gpa, &actual);
    var baseline = try Baseline.parse(gpa, "src/a.zig:tooLong:72\n");
    defer baseline.deinit(gpa);

    const findings = try checkFunctionLength(gpa, "src/a.zig", &lines, baseline, &actual);
    defer freeFindings(gpa, findings);
    try std.testing.expectEqual(@as(usize, 0), findings.len);
}

test "checkFunctionLength passes the second of two same-named baselined functions" {
    // Regression: a repeated function name (common for `deinit`/`waitForEvent` overloads
    // across sibling structs) frees the interned `key` on the second occurrence's
    // `getOrPut` before this same key was used for the baseline lookup, poisoning the
    // read under `std.testing.allocator` and making a covered function look unbaselined.
    const gpa = std.testing.allocator;
    const short = longFnLines(5); // "tooLong", 7 lines total, scanned first.
    const long = longFnLines(90); // same name, 92 lines, scanned second.
    var lines: [short.len + long.len][]const u8 = undefined;
    @memcpy(lines[0..short.len], &short);
    @memcpy(lines[short.len..], &long);
    var actual = std.StringHashMap(ActualLen).init(gpa);
    defer freeActualMap(gpa, &actual);
    var baseline = try Baseline.parse(gpa, "src/a.zig:tooLong:92\n");
    defer baseline.deinit(gpa);

    const findings = try checkFunctionLength(gpa, "src/a.zig", &lines, baseline, &actual);
    defer freeFindings(gpa, findings);
    try std.testing.expectEqual(@as(usize, 0), findings.len);
}

test "reconcileBaseline flags a shrunk entry" {
    const gpa = std.testing.allocator;
    var baseline = try Baseline.parse(gpa, "src/a.zig:foo:90\n");
    defer baseline.deinit(gpa);
    var actual = std.StringHashMap(ActualLen).init(gpa);
    defer actual.deinit();
    try actual.put("src/a.zig:foo", .{ .line = 3, .len = 40 });

    const findings = try reconcileBaseline(gpa, baseline, actual);
    defer freeFindings(gpa, findings);
    try std.testing.expectEqual(@as(usize, 1), findings.len);
    try std.testing.expectEqualStrings("stale-baseline", findings[0].rule);
}

test "reconcileBaseline flags a grown entry and an entry with no function" {
    const gpa = std.testing.allocator;
    var baseline = try Baseline.parse(gpa, "src/a.zig:foo:90\nsrc/a.zig:gone:80\n");
    defer baseline.deinit(gpa);
    var actual = std.StringHashMap(ActualLen).init(gpa);
    defer actual.deinit();
    try actual.put("src/a.zig:foo", .{ .line = 3, .len = 95 });

    const findings = try reconcileBaseline(gpa, baseline, actual);
    defer freeFindings(gpa, findings);
    try std.testing.expectEqual(@as(usize, 2), findings.len);
}

test "reconcileBaseline is silent when actual stays within the recorded ceiling" {
    const gpa = std.testing.allocator;
    var baseline = try Baseline.parse(gpa, "src/a.zig:foo:90\n");
    defer baseline.deinit(gpa);
    var actual = std.StringHashMap(ActualLen).init(gpa);
    defer actual.deinit();
    try actual.put("src/a.zig:foo", .{ .line = 3, .len = 85 });

    const findings = try reconcileBaseline(gpa, baseline, actual);
    defer freeFindings(gpa, findings);
    try std.testing.expectEqual(@as(usize, 0), findings.len);
}

test "formatFindings renders path:line: rule: message [replacement]" {
    const gpa = std.testing.allocator;
    const findings = [_]Finding{.{
        .path = "src/a.zig",
        .line = 3,
        .rule = "ban-list",
        .message = try gpa.dupe(u8, "banned pattern `dbg(`"),
        .replacement = "remove it",
    }};
    defer gpa.free(findings[0].message);

    const out = try formatFindings(gpa, &findings);
    defer gpa.free(out);
    const expected = "src/a.zig:3: ban-list: banned pattern `dbg(` [remove it]";
    try std.testing.expect(std.mem.indexOf(u8, out, expected) != null);
}
