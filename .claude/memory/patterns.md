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
try child.spawn();
const term = try child.wait();
const exit_code = switch (term) { .Exited => |c| c, else => 1 };
```

**Read stdout BEFORE wait()**: `child.wait()` closes stdout. Always read pipe first.

**Exit pattern**: Flush all writers before single `std.process.exit()` call in main.

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
