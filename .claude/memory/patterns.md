# Verified Code Patterns — Essential Reference

Patterns critical for writing code in this project. Zig 0.15 and cross-platform focus.

## Zig 0.15 I/O & Process

**File writing**: `var list = std.ArrayList(u8){}; try list.writer(allocator).print(...); try file.writeAll(list.items);`

**stdout/stderr writer**:
```zig
var buf: [4096]u8 = undefined;
var writer = std.fs.File.stdout().writer(&buf);
// Always call .interface.flush() before std.process.exit()
```

**Process execution**:
```zig
var child = std.process.Child.init(&[_][]const u8{"sh", "-c", cmd}, allocator);
child.stdin_behavior = .Inherit;
child.stdout_behavior = .Pipe;  // To capture output
try child.spawn();
// Read pipes BEFORE wait()
var output = child.stdout.?.readToEndAlloc(allocator, 1_000_000) catch "";
const term = try child.wait();
const exit_code = switch (term) { .Exited => |c| c, else => 1 };
```

**Capture stdout incrementally** (for streaming):
```zig
var list: std.ArrayListUnmanaged(u8) = .{};
const buf_size = 4096;
var buf: [buf_size]u8 = undefined;
if (child.stdout) |stdout| {
    while (true) {
        const bytes_read = try stdout.read(&buf);
        if (bytes_read == 0) break;
        try list.appendSlice(allocator, buf[0..bytes_read]);
    }
}
```

**Read stdout BEFORE wait()**: `child.wait()` closes stdout. Always read pipe first.
**Child doesn't need deinit()**: No `defer child.deinit()` — use `spawn()` + `wait()`.

**Exit pattern**: Flush all writers before single `std.process.exit()` call in main.

## JSON Serialization & Parsing (Zig 0.15)

**Parse JSON string**:
```zig
var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
defer parsed.deinit();
const obj = parsed.value.object;
if (obj.get("field")) |value| {
    if (value == .string) {
        const str = value.string;  // []const u8
    } else if (value == .object) {
        var iter = value.object.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const val = entry.value_ptr.*;
        }
    }
}
```

**Manual JSON building** (no stringify API):
```zig
var json: std.ArrayListUnmanaged(u8) = .{};
var writer = json.writer(allocator);
try writer.writeAll("{\"key\":\"");
try writer.writeAll(value);  // Already a string slice
try writer.writeAll("\",\"num\":");
try writer.print("{d}", .{num});
try writer.writeAll("}");
```

**Note**: Escape special chars manually if needed (quotes, backslashes). For simple strings, direct write is OK.

## Memory Management

**ArrayList**: `var list = std.ArrayList(u8){}; defer list.deinit(allocator);` (unmanaged API)

**Partial alloc cleanup**:
```zig
var duped: usize = 0;
errdefer {
    for (slice[0..duped]) |s| allocator.free(s);
    allocator.free(slice);
}
for (items, 0..) |item, i| {
    slice[i] = try allocator.dupe(u8, item);
    duped += 1;
}
```

**HashMap double-free**: When key = value.name (same allocation), DON'T free key separately — `value.deinit()` frees it.

**Env pair slice** (Task.env field):
```zig
env: [][2][]const u8,  // owned
// In addTaskImpl: alloc, dupe both key [0] and value [1], handle partial cleanup
// In Task.deinit: loop pair, free [0] and [1], free env slice
```

## Cross-Platform

**Platform wrappers** (`src/util/platform.zig`): All POSIX calls via `platform.*` with comptime guards.

**Windows color**: MUST call `SetConsoleOutputCP(CP_UTF8)` BEFORE `SetConsoleMode` VT flag 0x0004 (fixes garbled codes).

**PID types**: Windows = `std.os.windows.HANDLE`, POSIX = `std.posix.pid_t` — use `if (builtin.os.tag == .windows)` switch.

**Extern C functions**: `@extern(*const fn (...) callconv(.c) RetType, .{ .name = "symbol" })` (`.c` lowercase in 0.15).

## TOML Parser State Machine

Multi-section parser: Flush pending state on EVERY section header change.

Key order: `[[...stages]]` branch BEFORE `[workflows.X]` (more specific first).

Reset pattern: `task_matrix_raw = null`, `task_cache = false`, etc. in EVERY reset section (easy to miss).

**Inline table parsing**:
```zig
if (std.mem.startsWith(u8, value, "{") and std.mem.endsWith(u8, value, "}")) {
    var pairs_it = std.mem.splitScalar(u8, inner[1..len-1], ',');
    while (pairs_it.next()) |pair| {
        const eq = std.mem.indexOf(...);
        const k = std.mem.trim(...);
        const v = std.mem.trim(...);
    }
}
```

## Scheduler & Worker Threads

**Worker context**:
```zig
const WorkerCtx = struct {
    allocator, task_name (owned), results, mutex, semaphore, failed
};
fn workerFn(ctx: WorkerCtx) void {
    defer ctx.semaphore.post();  // release slot
    defer allocator.free(ctx.task_name);
    // ...
    ctx.results_mutex.lock(); defer ctx.results_mutex.unlock();
}
```

**Semaphore pattern**: `Semaphore{ .permits = max_jobs }`, `wait()` before spawn, `post()` in defer.

**Retry loop**:
```zig
var delay_ms = task.retry_delay_ms;
while (!success and attempt < task.retry_max) : (attempt += 1) {
    if (delay_ms > 0) std.Thread.sleep(delay_ms * std.time.ns_per_ms);
    // retry...
    if (task.retry_backoff) delay_ms *= 2;
}
```

## Testing Patterns

**tmpDir test**:
```zig
var tmp = std.testing.tmpDir(.{});
defer tmp.cleanup();
const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
defer allocator.free(tmp_path);
// Use tmp.dir for filesystem ops
```

**Fixed-buffer writer** (Zig 0.15):
```zig
var buf: [512]u8 = undefined;
var writer = std.Io.Writer.fixed(&buf);
// ... call functions ...
const out = buf[0..writer.end];  // bytes written
```

**Mock config file**:
```zig
try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = toml_content });
const path = try std.fmt.allocPrint(allocator, "{s}/zr.toml", .{tmp_path});
defer allocator.free(path);
```

**Git tests**: Use `git init -b main` + `git config user.name/email` in temp repos.

**Platform-specific tests**: `if (comptime builtin.os.tag != .linux) return error.SkipZigTest;`

## Expression Evaluator (config/expr.zig)

Fail-open: unknown expressions return `true` (task runs).

Lookup order: task_env pairs → process env → "" (not found).

Operators: `&&`, `||` (short-circuit), `==`, `!=`.

Literals: `true`, `false`, `env.VAR`, `platform == "linux"`, `file.exists("path")`.

## Color Output (output/color.zig)

Detect TTY: `const use_color = color.isTty(std.fs.File.stdout());`

Use semantic helpers: `printSuccess()`, `printError()`, `printInfo()`, `printBold()`, `printDim()`.

NEVER embed ANSI codes directly — always use color module.

## Task Output & Logging

**OutputCapture modes**: `stream` (file), `buffer` (memory), `discard`.

**Checkpoint marker**: Task emits `CHECKPOINT: <json>` to stdout, scheduler saves to file.

**Resume protocol**: Load checkpoint, pass via `ZR_CHECKPOINT` env var.

## File Operations (Zig 0.15)

**Existence check** (labeled block):
```zig
const exists: bool = blk: {
    dir.access(path, .{}) catch |err| {
        if (err == error.FileNotFound) break :blk false;
        return err;
    };
    break :blk true;
};
```

**File append**: Use `fmt.bufPrint()` + `file.writeAll()`, NOT `file.writer(&buf).flush()` (unreliable).

**Testable filesystem**: Accept `std.fs.Dir` parameter instead of calling `std.fs.cwd()` directly.

## Retry & Circuit Breaker (exec/resource.zig)

**Circuit breaker states**: closed → open (threshold exceeded) → half-open (reset timeout) → closed.

**Failure rate tracking**: Count failures in window_ms, compare to failure_threshold.

**Per-task isolation**: Separate CircuitBreakerState per task name.

## Global Flags (main.zig)

Parse before command dispatch. Pass `max_jobs: u32`, `config_path: []const u8` to cmd* functions.

Quiet mode: Open `/dev/null`, wrap with `File.writer(&buf)`, use interface pointer (valid in stack frame).

## Remote Execution Task Config (Phase 1.1)

**Remote field types**:
```zig
remote: ?[]const u8 = null,        // "user@host:port", "ssh://...", "http://...", "https://..."
remote_cwd: ?[]const u8 = null,    // Working directory on remote system
remote_env: [][2][]const u8 = &.{}, // Key-value pairs separate from local env
```

**Task.deinit() cleanup**:
```zig
if (self.remote_cwd) |rc| allocator.free(rc);
for (self.remote_env) |pair| {
    allocator.free(pair[0]);
    allocator.free(pair[1]);
}
if (self.remote_env.len > 0) allocator.free(self.remote_env);
```

**Parser pattern for remote_env** (inline table):
```zig
// Input: remote_env = { ENV_KEY = "value", DEBUG = "true" }
// Extract inner content and split by comma (respecting nesting)
for (pairs) |pair| {
    const eq = std.mem.indexOf(u8, pair, "=");
    const k = std.mem.trim(u8, pair[0..eq], " \t\"");
    const v = std.mem.trim(u8, pair[eq+1..], " \t\"");
    env_array[i] = [_][]const u8{ try allocator.dupe(u8, k), try allocator.dupe(u8, v) };
}
```

**Test format** (TOML):
```toml
[tasks.remote-task]
cmd = "npm deploy"
remote = "user@prod:22"
remote_cwd = "/app"
remote_env = { ENV = "prod", DEBUG = "false" }
```

**Test assertions**:
- Check task.remote is non-null and matches expected string
- Check task.remote_cwd is non-null for configured tasks, null otherwise
- For remote_env, iterate pairs and verify key-value extraction
- Test that local env (env) and remote_env are independent
- Test optional fields work in isolation and combination

## Module Extraction

**Sub-module**: Import siblings with relative path `@import("sibling.zig")`. Re-export in parent for backward compatibility.

**Add to main comptime**: `_ = @import("submodule.zig");` for test inclusion.

**No circular deps**: Move shared types to new module, re-export from parent.

## Matrix Task Expansion (config/loader.zig)

Parse raw `task_matrix_raw: ?[]const u8` non-owning slice.

At flush: if `task_matrix_raw != null`, call `addMatrixTask()` not `addTaskImpl()`.

Variant name: `basename:key1=val1:key2=val2` (keys alphabetically sorted).

Meta-task: original name, all variants as dependencies.

Cartesian product (little-endian increment):
```zig
var di = n_dims;
while (di > 0) {
    di -= 1;
    combo[di] += 1;
    if (combo[di] < dims[di].values.len) break;
    combo[di] = 0;
}
```

## Plugin System

**DynLib loading** (Zig 0.15): `var lib = std.DynLib.open(path) catch return error.NotFound;`

**Extern C functions**: `@extern(*const fn(...) callconv(.c) ..., .{ .name = "..." })`

**Plugin metadata**: Simple flat key=value TOML parser (no sections).

**Git clone**: `git clone --depth=1 <url> <dest>`; check `.spawn() catch` for git-not-in-PATH.

**Registry install**: `registry:org/name@version` → `https://github.com/<org>/zr-plugin-<name>` (skip doubling `zr-plugin-`).

## Workspace Resolution

Test pattern with absolute paths (avoids cwd sensitivity):
```zig
const pattern = try std.fmt.allocPrint(allocator, "{s}/packages/*", .{tmp_path});
var patterns = [_][]const u8{pattern};
const ws = Workspace{ .members = patterns[0..], .ignore = &.{} };
```

Note: `&patterns` gives wrong type — use `patterns[0..]` to coerce to slice.

## TOML Syntax Highlighting Lexer

**Token types**: Table headers, keys, strings, numbers (int/float/hex/oct/bin), booleans, nulls, comments, whitespace, datetime, inline tables, arrays, operators (=, comma, dot).

**Lexer design** (`TomlLexer` struct):
```zig
pub const TomlLexer = struct {
    input: []const u8,
    pos: usize = 0,
    line: usize = 1,
    column: usize = 1,
    allocator: Allocator,
    tokens: std.ArrayList(Token),

    pub fn tokenize(self: *TomlLexer) !void {
        while (self.pos < self.input.len) {
            const ch = self.input[self.pos];
            // Dispatch: comments, whitespace, table headers, operators, strings, numbers, keywords/keys
        }
    }
};
```

**Line tracking**: Increment `line` on `\n`, reset `column` to 1. Advance both on other chars.

**String handling**: Distinguish single vs triple quotes. Triple quotes consume everything until closing triple. Single quotes: handle escape sequences only in `"..."`, not `'...'`.

**Number parsing**: Check prefix for `0x`/`0o`/`0b` → special branches. Then scan digits, optional `.` for float, optional `e`/`E` for exponent, optional `T`/`t`/` ` for ISO 8601 datetime.

**Table headers**: Check if at line start (only whitespace/newline before). Distinguish `[name]` (regular) vs `[[name]]` (array-of-tables) by peeking second char.

**Colorize pattern** (ANSI codes):
```zig
pub fn colorizeToken(token: Token) struct { prefix, suffix: []const u8 } {
    return switch (token.type) {
        .@"table_header" => .{ .prefix = "\x1b[1;33m", .suffix = "\x1b[0m" }, // bold yellow
        .@"key" => .{ .prefix = "\x1b[1;35m", .suffix = "\x1b[0m" }, // bold magenta
        .@"string" => .{ .prefix = "\x1b[1;32m", .suffix = "\x1b[0m" }, // bold green
        // ...
    };
}
```

**Integration**: `highlightToml(allocator, input)` → lexes, applies colors, returns owned string. Caller must free.

## zuda Migration Patterns

**Dependency access**: zuda v1.15.0 is declared in `build.zig.zon`. Access algorithms/containers via `@import("zuda")`.

**Module export structure**: zuda's root.zig exports FUNCTIONS, not nested structs.
- ✅ Correct: `zuda.algorithms.string.globMatch(pattern, str)`
- ❌ Wrong: `zuda.algorithms.string.globMatch.match(pattern, str)` — `globMatch` is already the function

**Wrapper pattern**: Keep local function signature for compatibility, delegate to zuda:
```zig
const zuda = @import("zuda");

pub fn match(pattern: []const u8, str: []const u8) bool {
    return zuda.algorithms.string.globMatch(pattern, str);
}
```

**Partial migration**: zuda provides algorithms (pattern matching, edit distance), NOT filesystem traversal. Keep local FS logic (find/findDirs), delegate only core algorithms.

**Test verification**: Run `zig build integration-test` (faster than full `zig build test`) to verify migration. Check for 0 failures.

## Parsing /proc Files (Linux System Metrics)

Pattern for extracting numeric values from Linux /proc format files (/proc/meminfo, /proc/[pid]/status, etc).

**Key insight**: /proc files use colon-separated format with optional "kB" units. Some fields use spaces, others tabs.

**Generic extractor for key:value pairs**:
```zig
fn extractValue(content: []const u8, key: []const u8) !?u64 {
    var lines = std.mem.tokenizeSequence(u8, content, "\n");
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, key)) {
            // Find colon separator
            if (std.mem.indexOfScalar(u8, line, ':')) |colon_pos| {
                const value_part = std.mem.trim(u8, line[colon_pos + 1 ..], " \t");
                // Strip "kB" suffix if present
                const numeric = std.mem.trim(u8, value_part, "kB \t");
                return try std.fmt.parseInt(u64, numeric, 10);
            }
        }
    }
    return null;
}
```

**Usage**:
```zig
// Extract MemTotal from /proc/meminfo
const mem_total_kb = try extractValue(meminfo_content, "MemTotal:");
// Returns null if not found, or ?u64 with value in KB

// Extract VmSize from /proc/[pid]/status
const vm_size_kb = try extractValue(status_content, "VmSize:");
// Remember to convert KB to bytes: vm_size_bytes = vm_size_kb * 1024
```

**Parsing /proc/[pid]/stat for CPU times** (space-separated, field 14-15 are utime/stime in jiffies):
```zig
fn extractCpuTimes(content: []const u8) !?struct { utime: u64, stime: u64 } {
    var fields = std.mem.tokenizeSequence(u8, content, " ");
    var field_count: usize = 0;
    var utime: u64 = 0;
    var stime: u64 = 0;

    while (fields.next()) |field| {
        if (field_count == 13) {  // Field 14 in 1-indexed = index 13
            utime = try std.fmt.parseInt(u64, field, 10);
        } else if (field_count == 14) {  // Field 15 in 1-indexed = index 14
            stime = try std.fmt.parseInt(u64, field, 10);
            break;
        }
        field_count += 1;
    }

    if (utime == 0 and stime == 0) return null;
    return .{ .utime = utime, .stime = stime };
}
```

**Testing note**: Test with mock /proc content as string literals. Use `try extractValue(content, "Key:")` pattern. Always test both presence and absence of fields, empty content, and malformed input.

## Integration Test Patterns for Composition Features (Mixins, Workspace Inheritance)

### Test Structure Pattern

All composition feature tests (8000-8019 for mixins, 6000-6014 for workspace) follow this pattern:

```zig
test "XXXX: descriptive feature name" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // 1. Create TOML config as string literal
    const config_toml =
        \\[section.subsection]
        \\field = value
        \\
    ;

    // 2. Write config to temp directory
    const config = try writeTmpConfig(allocator, tmp.dir, config_toml);
    defer allocator.free(config);

    // 3. Get temp path for zr execution
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // 4. Run zr command with config
    var result = try runZr(allocator, &.{ "--config", "zr.toml", "command_args" }, tmp_path);
    defer result.deinit();

    // 5. Assert exit code and output
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "expected_substring") != null);
}
```

### Mixin-Specific Patterns

**Single mixin test** (test 8000 pattern):
- Define `[mixins.NAME]` section with fields (env, deps, tags, etc.)
- Reference with `mixins = ["NAME"]` in task
- Verify inheritance via `zr list` and task execution output

**Multiple mixins test** (test 8001 pattern):
- Define two or more mixins with different fields
- Reference both: `mixins = ["mixin1", "mixin2"]`
- Verify composition order (left-to-right) via execution output

**Field merging test** (test 8002-8008 patterns):
- For env merging: Set same key in mixin and task with different values, verify task value wins
- For deps concatenation: Set deps in mixin and task, run task, verify both execute in order
- For tags union: Set tags in multiple mixins and task, verify all present in list output (no duplicates)
- For cmd override: Set cmd in mixin and task, verify task command is executed

**Error handling tests** (test 8004-8005):
- Circular mixins: `mixins.a.mixins = ["b"]`, `mixins.b.mixins = ["a"]` — expect non-zero exit
- Nonexistent mixin: Reference undefined mixin name — expect error message in stderr

**Nested mixins test** (test 8003, 8009):
- Create chain: `mixins.level1` → `mixins.level2` (includes level1) → `mixins.level3` (includes level2)
- Task uses level3, verify all three levels' fields are inherited
- Verify DAG resolution via execution output

### Assertion Patterns for Composition Tests

**Exit code**: `try std.testing.expectEqual(@as(u8, 0), result.exit_code);`

**String presence in output**: `try std.testing.expect(std.mem.indexOf(u8, result.stdout, "substring") != null);`

**String absence**: `try std.testing.expect(std.mem.indexOf(u8, result.stderr, "error_pattern") == null);`

**Order verification**: Use `indexOf()` twice and compare indices:
```zig
const pos1 = std.mem.indexOf(u8, result.stdout, "first") orelse return error.TestFailed;
const pos2 = std.mem.indexOf(u8, result.stdout, "second") orelse return error.TestFailed;
try std.testing.expect(pos1 < pos2);  // first runs before second
```

**JSON output verification**: For tests 8019-style:
- Run with `--json` flag
- Verify expected fields are present in output using `indexOf()` for key names
- Example: Check both "tag1" and "tag2" exist in output for union verification

### Integration with Existing Features

**Mixin + Workspace test** (test 8011):
- Set `[workspace]` and `[workspace.shared_tasks.NAME]`
- Define `[mixins.NAME]` in root
- Create member with task that references mixin
- Verify mixin is resolved from workspace root

**Mixin + Templates test** (test 8010):
- Define `[templates.NAME]` with placeholders
- Define mixin that has `template = "NAME"` field
- Verify template is applied when mixin is used

**Mixin + Hooks test** (test 8017):
- Define mixin with `[[mixin.hooks]]` entries
- Verify hooks are executed when task using mixin runs
- Check output contains before/after hook messages

### Key Differences from Unit Tests

- Integration tests use `runZr()` to spawn real binary
- TOML configs are string literals, not parsed manually
- Tests verify CLI output, not internal data structures
- Tests must pass even if mixin implementation is naive (no optimization required)
- Tests exercise full loading pipeline, not just mixin resolution

### Writing New Mixin Tests

1. Identify feature gap (e.g., "retry config in mixin")
2. Create minimal TOML that demonstrates feature
3. Run zr command that exercises the feature
4. Assert on exit code and output
5. Use `try std.testing.expect()` with meaningful assertions, never `try std.testing.expect(true)`
6. Keep test under 50 lines
7. Document what is being tested in test name (test "XXXX: clear description")
