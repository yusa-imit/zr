# Verified Code Patterns

Patterns confirmed to work well in this project. Update as patterns evolve.

## Zig Patterns

### Allocator Usage
- Use `std.testing.allocator` in tests for leak detection
- Use `std.heap.ArenaAllocator` for request-scoped work
- Pass allocator as first parameter to init functions
- Always provide `deinit()` for structs with owned memory

### Error Handling
- Define specific error sets per module
- Propagate errors with `try`
- Use `errdefer` for cleanup on error paths
- Wrap error details in Result structs for better error reporting

### Graph Module Patterns
- **DAG Structure**: Use `StringHashMap` for O(1) node lookup
- **Node Storage**: Store owned copies of strings to avoid lifetime issues
- **Edge Representation**: Each node stores its dependencies as ArrayList
- **Kahn's Algorithm**:
  - Calculate in-degrees first
  - Use queue for zero-degree nodes
  - Process nodes level by level
  - Remaining nodes with degree > 0 indicate cycle
- **Execution Levels**: Multi-pass algorithm to group parallel-executable tasks
  - Level 0 = no dependencies
  - Level N = depends only on levels < N
  - Each level can execute in parallel

### Testing Patterns
- Test simple cases first (linear chains)
- Test complex cases (parallel branches, diamonds)
- Test edge cases (self-cycles, empty graphs)
- Always test both success and failure paths
- Use `defer` for cleanup in tests

### Process Execution Pattern (Zig 0.15)
```zig
const argv = [_][]const u8{ "sh", "-c", cmd };
var child = std.process.Child.init(&argv, allocator);
child.stdin_behavior = .Inherit;
child.stdout_behavior = .Inherit;
child.stderr_behavior = .Inherit;
child.cwd = optional_cwd;
try child.spawn();
const term = try child.wait();
const exit_code: u8 = switch (term) {
    .Exited => |code| code,
    else => 1,
};
```
- Use `sh -c <cmd>` to support pipes, redirects, and shell builtins
- Always inherit stdio for real-time user output

### I/O Pattern (Zig 0.15)
```zig
var buf: [4096]u8 = undefined;
const stdout = std.fs.File.stdout();
var writer = stdout.writer(&buf);
// Must flush manually - std.process.exit bypasses defers!
writer.interface.flush() catch {};
try writer.interface.print("hello {s}\n", .{"world"});
try writer.interface.writeAll("plain text\n");
```
- `std.fs.File.stdout()` replaces `std.io.getStdOut()`
- `stdout.writer(&buf)` returns `File.Writer` with `.interface: std.Io.Writer`
- Call methods on `.interface` for `print`, `flush`, `writeAll`
- Never rely on defer for flushing if `std.process.exit` might be called

### Exit Code Pattern (Zig 0.15)
```zig
pub fn main() !void {
    // Setup writers...
    const result = innerRun(allocator, args, &writer, &err_writer);
    writer.interface.flush() catch {};      // always flush before exit
    err_writer.interface.flush() catch {};
    if (result) |code| {
        if (code != 0) std.process.exit(code);
    } else |err| return err;
}
fn innerRun(...) !u8 { ... return exit_code; }
```
- Never call `std.process.exit` from helper functions
- Always flush writers before the single exit point in main

### HashMap Key Ownership Pattern
```zig
// When using StringHashMap with owned keys, free keys in deinit:
pub fn deinit(self: *Self) void {
    var it = self.map.iterator();
    while (it.next()) |entry| {
        self.allocator.free(entry.key_ptr.*); // free the key
        entry.value_ptr.deinit(self.allocator); // free the value
    }
    self.map.deinit();
}
```

### Color Output Pattern (output/color.zig)
```zig
// Detect TTY for color enable/disable:
const use_color = color.isTty(std.fs.File.stdout());

// Use semantic helpers:
try color.printSuccess(w, use_color, "{s} completed\n", .{name});
try color.printError(ew, use_color, "Task '{s}' not found\n", .{name});
try color.printInfo(w, use_color, "{s}\n", .{name});
try color.printBold(w, use_color, "Header:\n", .{});
try color.printDim(w, use_color, "({d}ms)\n", .{ms});
```
- Always detect TTY at the top of main() and pass `use_color` through
- Never embed ANSI codes directly in strings; always use color module helpers
- Color module auto-disables when not a TTY (pipes, CI)

### Process Stdio Pattern
```zig
// Production (interactive): inherit_stdio = true (default)
process.run(alloc, .{ .cmd = cmd, .cwd = cwd, .env = null });

// Tests: inherit_stdio = false (prevents deadlock in background tasks)
process.run(alloc, .{ .cmd = cmd, .cwd = null, .env = null, .inherit_stdio = false });
```
- Tests MUST use `inherit_stdio = false` to avoid deadlock
- .Pipe for stdout/stderr is safe for small output (< ~64KB pipe buffer)

### Parallel Worker Thread Pattern
```zig
// Worker context — all pointers to shared state, task_name is owned by worker
const WorkerCtx = struct {
    allocator: std.mem.Allocator,
    task_name: []const u8,     // owned; freed in worker defer
    results: *std.ArrayList(T),
    results_mutex: *std.Thread.Mutex,
    semaphore: *std.Thread.Semaphore,  // limits concurrency
    failed: *std.atomic.Value(bool),   // cross-thread failure flag
};

fn workerFn(ctx: WorkerCtx) void {
    defer {
        ctx.semaphore.post();         // always release slot
        ctx.allocator.free(ctx.task_name);
    }
    // ... do work ...
    ctx.results_mutex.lock();
    defer ctx.results_mutex.unlock();
    ctx.results.append(...) catch {};
    if (failure) ctx.failed.store(true, .release);
}

// Spawning: semaphore.wait() before spawn, semaphore.post() in worker defer
// Joining: collect all threads, then join all before next level
```
- Use `std.Thread.Semaphore{ .permits = max_jobs }` to cap concurrency
- Use `.acquire`/`.release` ordering for atomic reads/writes
- Always join all threads in a level before proceeding to next level

### Process Timeout Pattern (Zig 0.15)
```zig
// Poll-based timeout watcher thread:
fn timeoutWatcher(ctx: TimeoutCtx) void {
    const slice_ms: u64 = 50;
    var elapsed_ms: u64 = 0;
    while (elapsed_ms < ctx.timeout_ms) {
        if (ctx.done.load(.acquire)) return; // exited normally
        std.Thread.sleep(slice_ms * std.time.ns_per_ms); // NOT std.time.sleep
        elapsed_ms += slice_ms;
    }
    if (ctx.done.load(.acquire)) return;
    std.posix.kill(ctx.pid, std.posix.SIG.KILL) catch {};
    ctx.timed_out.store(true, .release);
}
// After child.wait(): signal done, join watcher thread, check timed_out flag
// IMPORTANT: std.Thread.sleep(ns) in Zig 0.15; std.time.sleep does NOT exist
```

### File Append Pattern (Zig 0.15)
```zig
// For reliable file appending, use fmt.bufPrint + file.writeAll:
const file = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
defer file.close();
try file.seekFromEnd(0);
var line_buf: [1024]u8 = undefined;
const line = try std.fmt.bufPrint(&line_buf, "{d}\t{s}\n", .{ val1, val2 });
try file.writeAll(line);
// Do NOT use file.writer(&buf) + flush for appending — unreliable
```

### Partial Alloc+Dupe Loop Cleanup Pattern
```zig
// Track how many items were duped for safe partial cleanup:
const slice = try allocator.alloc([]const u8, items.len);
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

### Cycle Sentinel Pattern for Recursive Graph Traversal
```zig
// Insert a false sentinel before recursing to detect cycles:
try completed.put(name, false);  // sentinel: "visiting"
const ok = try recurse(name, ...);
try completed.put(name, ok);     // update to real result

// Check on entry:
if (completed.contains(name)) {
    const prev_ok = completed.get(name).?;
    if (!prev_ok) return false;  // cycle detected or prior failure
    continue;
}
```

### Parser Non-Owning Slice Pattern
```zig
// Use non-owning slices in parsers; only dupe when storing:
var current_task: ?[]const u8 = null;
// ...
current_task = trimmed[start..][0..end]; // no dupe - slice into content
// ...
try storeTask(allocator, current_task, ...); // storeTask does the dupe
```

### Env Pair Slice Pattern (Task.env field)
```zig
// Task struct field type:
env: [][2][]const u8,  // owned; each pair[0]=key, pair[1]=value

// In addTaskImpl: dupe with partial-cleanup safety:
const task_env = try allocator.alloc([2][]const u8, env.len);
var env_duped: usize = 0;
errdefer {
    for (task_env[0..env_duped]) |pair| {
        allocator.free(pair[0]);
        allocator.free(pair[1]);
    }
    allocator.free(task_env);
}
for (env, 0..) |pair, i| {
    task_env[i][0] = try allocator.dupe(u8, pair[0]);
    errdefer allocator.free(task_env[i][0]);
    task_env[i][1] = try allocator.dupe(u8, pair[1]);
    env_duped += 1;
}

// In Task.deinit:
for (self.env) |pair| {
    allocator.free(pair[0]);
    allocator.free(pair[1]);
}
allocator.free(self.env);

// In scheduler: convert empty slice to null for process.run:
.env = if (task.env.len > 0) task.env else null,

// process.run accepts: env: ?[]const [2][]const u8
```

### TOML Inline Table Parsing Pattern
```zig
// Parse: env = { KEY = "value", FOO = "bar" }
// After outer `value` extraction (key=value line), `value` is the raw rhs.
// The outer quote-strip (for string values) won't fire on `{...}` tables.
const inner = std.mem.trim(u8, value, " \t");
if (std.mem.startsWith(u8, inner, "{") and std.mem.endsWith(u8, inner, "}")) {
    const pairs_str = inner[1 .. inner.len - 1];
    var pairs_it = std.mem.splitScalar(u8, pairs_str, ',');
    while (pairs_it.next()) |pair_str| {
        const eq = std.mem.indexOf(u8, pair_str, "=") orelse continue;
        const k = std.mem.trim(u8, pair_str[0..eq], " \t\"");
        const v = std.mem.trim(u8, pair_str[eq + 1 ..], " \t\"");
        if (k.len > 0) try list.append(allocator, .{ k, v });
    }
}
```

### Retry Loop Pattern (scheduler.zig)
```zig
// In workerFn / runTaskSync — retry on failure up to retry_max times:
var proc_result = process.run(allocator, config) catch fallback;
if (!proc_result.success and task.retry_max > 0) {
    var delay_ms: u64 = task.retry_delay_ms;
    var attempt: u32 = 0;
    while (!proc_result.success and attempt < task.retry_max) : (attempt += 1) {
        if (delay_ms > 0) std.Thread.sleep(delay_ms * std.time.ns_per_ms);
        proc_result = process.run(allocator, config) catch fallback;
        if (task.retry_backoff and delay_ms > 0) delay_ms *= 2;
    }
}
// Use delay_ms = 0 in tests for speed (no actual sleep).
// Both parallel workers (WorkerCtx) and serial sync runners use the same pattern.
```

### Polling File Watcher Pattern (watch/watcher.zig)
```zig
// Init: snapshot mtimes; waitForChange: poll loop
var watch = try watcher.Watcher.init(allocator, paths, 500); // 500ms poll
defer watch.deinit();

const event = try watch.waitForChange(); // blocks until change
// event.path is owned by watcher's internal map — valid until next call

// recordMtime safety — always errdefer before put:
const owned = try allocator.dupe(u8, path);
errdefer allocator.free(owned);
try map.put(owned, mtime);  // errdefer runs if put OOMs
```
- Uses `std.fs.Dir.walk()` for recursive scan; `entry.path` is relative to walked dir root
- Skip dirs by basename: .git, node_modules, zig-out, .zig-cache
- Tests use `std.testing.tmpDir` + explicit `checkPath` (not `waitForChange`)
- `waitForChange` is an infinite loop — no clean shutdown on Ctrl+C (process exits naturally)

### Workflow Parsing Pattern (config/loader.zig)
```toml
# TOML format:
[workflows.release]
description = "Full release pipeline"

[[workflows.release.stages]]
name = "prepare"
tasks = ["clean", "install"]
parallel = true

[[workflows.release.stages]]
name = "build"
tasks = ["build"]
fail_fast = true
```
- State machine: flush pending stage before `[[...stages]]`, flush stage+workflow before `[workflows.X]` and `[tasks.X]`
- Stage tasks are non-owning slices during parse — duped when building Stage struct
- `addWorkflow` dupes everything; after call, free workflow_stages items (they were duped, not moved)
- `Config.deinit`: do NOT free key separately — `Workflow.deinit` frees `.name` = same allocation as map key
- `zr list` shows workflows section with stage count after task list

### Expression Evaluator Pattern (config/expr.zig)
```zig
// evalCondition is fail-open: unknown expressions return true (task runs).
// Lookup order: task_env pairs first, then process env, then "" (not found).
// getEnvVarOwned returns owned slice — free it; use defer for safety.

const env_value = try lookupEnv(allocator, var_name, task_env);
defer if (env_value) |v| allocator.free(v);
const value_str = if (env_value) |v| v else "";
```
- Supported: `true`/`false`, `env.VAR`, `env.VAR == "val"`, `env.VAR != 'val'`
- EvalError = error{OutOfMemory} — only OOM is returned; parse errors are fail-open
- Tests use task_env pairs to avoid process env pollution (no setEnvVar in tests)
- `getEnvVarOwned` errors other than OutOfMemory (e.g. InvalidWtf8) treated as not-found

### HashMap Key == Value.name Double-Free Pattern
```zig
// When the HashMap key and a struct field point to the same allocation:
// Config.workflows uses wf_name as both key and Workflow.name.
// In deinit, do NOT free entry.key_ptr.* separately —
// Workflow.deinit already frees self.name (= same pointer as key).
var wit = self.workflows.iterator();
while (wit.next()) |entry| {
    // Do NOT: self.allocator.free(entry.key_ptr.*);
    entry.value_ptr.deinit(self.allocator); // frees .name = key allocation
}
self.workflows.deinit();
// Tasks use the same pattern: Task.deinit frees task.name (= key pointer).
```
- This matches the existing task HashMap pattern (key freed via task.name in Task.deinit)
- Contrast: if you need keys independent from value fields, dupe the key separately and free key_ptr.* explicitly

### Testable Filesystem Function Pattern
```zig
// Accept std.fs.Dir instead of calling std.fs.cwd() directly:
fn cmdInit(dir: std.fs.Dir, w: *std.Io.Writer, ...) !u8 {
    dir.access(CONFIG_FILE, .{}) catch |err| { ... };
    const file = try dir.createFile(CONFIG_FILE, .{});
}
// Call site: cmdInit(std.fs.cwd(), ...)
// Test:      cmdInit(tmp.dir, ...)  — uses std.testing.tmpDir(.{})
```
- Any function that touches the filesystem should accept Dir not use cwd() directly
- Enables unit testing without changing the process working directory

### Filesystem Existence Check Pattern (Zig 0.15)
```zig
// Extract boolean from access() result using labeled block:
const exists: bool = blk: {
    dir.access(path, .{}) catch |err| {
        if (err == error.FileNotFound) break :blk false;
        // handle other errors
        return error.SomethingElse;
    };
    break :blk true;
};
// Never put success path inside catch block — use labeled block instead
```

### Multi-Section TOML Parser State Machine Pattern
```zig
// When parsing TOML with multiple top-level section types ([tasks.X], [workflows.X],
// [[workflows.X.stages]]), each section header must flush ALL pending state from
// prior sections:
//
// [tasks.X] arrival:
//   - flush pending stage -> workflow_stages
//   - flush pending workflow -> config.addWorkflow + clear workflow_stages
//   - flush pending task -> addTaskImpl
//   - reset all task state
//
// [workflows.X] arrival:
//   - flush pending stage -> workflow_stages
//   - flush pending workflow -> config.addWorkflow + clear workflow_stages
//   - flush pending TASK -> addTaskImpl + reset task state  ← easy to miss!
//   - set current_workflow
//
// [[workflows.X.stages]] arrival:
//   - flush pending stage -> workflow_stages
//   - reset stage state
//
// End of file:
//   - flush final stage, final workflow, final task
//
// Order of if-else branches matters:
//   [[...stages]] MUST come before [workflows.X] (more specific before less specific)
```

### Global Flag Parsing Pattern (main.zig)
```zig
// Declare all flag variables before the scan loop:
var max_jobs: u32 = 0;
var no_color: bool = false;
var quiet: bool = false;
var verbose: bool = false;
var config_path: []const u8 = CONFIG_FILE;

// After the loop, compute derived values:
const effective_color = use_color and !no_color;

// For quiet mode: open /dev/null as null sink (Unix only; falls back silently):
var quiet_file_opt: ?std.fs.File = null;
defer if (quiet_file_opt) |f| f.close();
var quiet_buf: [64]u8 = undefined;
var quiet_writer_storage: ?std.fs.File.Writer = null;
const effective_w: *std.Io.Writer = blk: {
    if (quiet) {
        if (std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only })) |qf| {
            quiet_file_opt = qf;
            quiet_writer_storage = qf.writer(&quiet_buf);
            break :blk &quiet_writer_storage.?.interface;
        } else |_| {}
    }
    break :blk w;
};
```
- All cmd* functions receive `max_jobs: u32` and `config_path: []const u8` so callers can override
- `loadConfig` accepts `config_path` instead of using the `CONFIG_FILE` constant directly
- `scheduler.run()` calls pass `.max_jobs = max_jobs` via `SchedulerConfig`
- Tests for flag parsing call `run()` directly with synthetic `fake_args` slices

### Per-Task Semaphore Pattern (max_concurrent)
```zig
// In run(): create lazily, destroy in defer after all threads joined
var task_semaphores = std.StringHashMap(*std.Thread.Semaphore).init(allocator);
defer {
    var ts_it = task_semaphores.iterator();
    while (ts_it.next()) |entry| allocator.destroy(entry.value_ptr.*);
    task_semaphores.deinit();
}

// In dispatch loop — ACQUIRE GLOBAL FIRST to avoid hold-and-wait deadlock:
semaphore.wait();  // global slot first
var task_sem_ptr: ?*std.Thread.Semaphore = null;
if (task.max_concurrent > 0) {
    if (task_semaphores.get(task_name)) |existing| {
        task_sem_ptr = existing;
    } else {
        const new_sem = try allocator.create(std.Thread.Semaphore);
        errdefer allocator.destroy(new_sem);  // CRITICAL: prevents leak if put() OOMs
        new_sem.* = std.Thread.Semaphore{ .permits = task.max_concurrent };
        try task_semaphores.put(task_name, new_sem);
        task_sem_ptr = new_sem;
    }
    task_sem_ptr.?.wait();  // per-task slot after global
}

// In workerFn defer: release per-task first, then global
defer {
    if (ctx.task_semaphore) |ts| ts.post();
    ctx.semaphore.post();
    ctx.allocator.free(ctx.task_name);
}
```
- Keys are non-owning slices into config.tasks map keys (safe since config is not mutated during run)
- Pre-reserve threads list before spawn: `try threads.ensureTotalCapacity(allocator, level.items.len)`
  then use `threads.appendAssumeCapacity(thread)` — prevents live-thread use-after-free on OOM

### Null-Writer Pattern for --quiet (Zig 0.15, Unix)
```zig
// Open /dev/null as write-only; wrap with File.writer(&buf)
// The interface pointer (&quiet_writer_storage.?.interface) is valid as long as
// quiet_writer_storage and quiet_buf are in scope (they live in run() stack frame).
// quiet_file_opt holds the file so it can be closed via defer.
```

### Workspace TOML Section Pattern
- New `[workspace]` section in TOML state machine needs `in_workspace = false` in ALL other section branches
  (including [[workflows.*]], [workflows.*], [profiles.*], [profiles.*.tasks.*], [tasks.*])
- Workspace flush uses `if (in_workspace or ws_members.items.len > 0)` but `or ws_members...` is redundant
  (ws_members only populated while in_workspace=true) — acceptable but `if (in_workspace)` is cleaner

### JSON Array Separator in Loops with Continue
- Do NOT use loop index `i > 0` as JSON comma separator when `continue` may skip items before the emit point
- Use a separate counter (`json_emitted: usize = 0`) and check `json_emitted > 0` at the emit point
- Increment `json_emitted` exactly where you write the JSON object, including error-fallback paths

### Dry-Run + JSON Output Conflict
- When a command supports both `--dry-run` and `--format json`, dry-run output is text that can't nest in JSON
- Use `const effective_json = json_output and !dry_run;` to disable JSON framing during dry runs

### Matrix Task Expansion Pattern (config/loader.zig)
```toml
# TOML syntax:
[tasks.test]
cmd = "cargo test --target ${matrix.arch}"
matrix = { arch = ["x86_64", "aarch64"], os = ["linux", "macos"] }
```
- `matrix` key is stored as raw string `task_matrix_raw: ?[]const u8` (non-owning slice into content)
- At flush time: if `task_matrix_raw != null`, call `addMatrixTask` instead of `addTaskImpl`
- `parseMatrixTable`: bracket-depth tracking scanner to correctly handle `[...]` values inside `{...}` tables
- `interpolateMatrixVars`: replaces `${matrix.KEY}` in cmd/cwd/description/env values using `std.mem.replaceOwned`
- `addMatrixTask`: sorts dims alphabetically, computes Cartesian product, calls `addTaskImpl` for each variant
- Variant name format: `basename:key1=val1:key2=val2` (keys sorted alphabetically for determinism)
- Meta-task: original name, cmd = `echo "Matrix task: NAME"`, deps = all variant names
- `task_matrix_raw = null` must be added to EVERY reset section — easy to miss
- Cartesian product counter: little-endian increment (last dim increments fastest)
```zig
// After emitting variant, advance combo (little-endian):
var di = n_dims;
while (di > 0) {
    di -= 1;
    combo[di] += 1;
    if (combo[di] < dims.items[di].values.len) break;
    combo[di] = 0;
}
```

### Task Output Cache Pattern (cache/store.zig)
```toml
# TOML syntax:
[tasks.build]
cmd = "make release"
cache = true   # skip if same cmd+env ran successfully before
```
- `CacheStore.init(allocator)` creates `~/.zr/cache/` dir; returns error on permission failure
- Key = `Wyhash64(cmd + env-pairs)` formatted as 16 hex chars (`{x:0>16}`)
- Hit = `~/.zr/cache/<key>.ok` file exists (empty marker file, atomic on POSIX)
- `recordHit(key)` creates the marker; `invalidate(key)` deletes it; `clearAll()` removes all `*.ok`
- In scheduler: `WorkerCtx` holds `cache: bool` + `cache_key: ?[]u8` (owned, freed in defer)
- Cache key computed AFTER semaphore acquisition (after the early-break paths) to avoid allocation leaks
- On thread spawn failure: free `cache_key` explicitly before `break`
- Cache miss → normal execution; cache hit → record `skipped=true` result and return early
- `task_cache = false` must be added to EVERY reset section in loader.zig (same pattern as `task_matrix_raw`)

## DynLib Plugin Loading (Zig 0.15)
```zig
var lib = std.DynLib.open(lib_path) catch return LoadError.LibraryNotFound;
errdefer lib.close();
const hook = lib.lookup(*const fn () callconv(.c) void, "export_name");
// hook is ?FnType — null if symbol not exported (always test before calling)
```

## Plugin TOML Parsing Pattern
- Section `[plugins.NAME]` parsed same as other top-level sections
- Must flush pending task/workflow/profile when entering plugin section
- Must also flush pending plugin when entering [tasks.] section
- `plugin_source = null` means plugin has no source → skip in flush (ignored)
- Inline table `config = { k = "v" }` reuses the standard pair-split pattern

## ArrayListUnmanaged (Zig 0.15 ArrayList pattern)
```zig
var list: std.ArrayListUnmanaged(T) = .empty;
try list.append(allocator, item);
list.deinit(allocator);
```
Use `.empty` for zero-initialization. `init(allocator)` does NOT exist in Zig 0.15.

## Plugin Install/Remove Pattern (filesystem management)
```zig
// Shallow directory copy:
var src_dir = try std.fs.openDirAbsolute(src_path, .{ .iterate = true });
defer src_dir.close();
std.fs.makeDirAbsolute(dest_dir) catch return error;
var dest = try std.fs.openDirAbsolute(dest_dir, .{});
defer dest.close();
var it = src_dir.iterate();
while (try it.next()) |entry| {
    if (entry.kind != .file) continue;
    // copy file: open src, createFile dest, read/write loop
}
```
- `std.fs.deleteTreeAbsolute(path)` for recursive removal; maps `error.FileNotFound` to custom error
- `std.fs.accessAbsolute(path, .{})` in labeled block to extract existence bool

## Plugin Metadata (plugin.toml) Pattern
- Simple flat key=value TOML parser (no sections, no arrays needed for metadata)
- Strip quotes: check `raw[0] == '"' and raw[len-1] == '"'` → slice `[1..len-1]`
- `readPluginMeta()` returns `?PluginMeta` (null when file not found)
- Caller must call `meta.deinit()` on the returned struct

## Plugin Subcommand Args Indexing
- args[0] = "zr", args[1] = "plugin", args[2] = subcommand, args[3] = first argument
- Check `args.len < 4` before accessing `args[3]`
- For optional second arg (like plugin name override in install): check `args.len >= 5`, use `args[4]`
- For required two-arg subcommands (like `update <name> <path>`): check `args.len < 5`

## Plugin Update Pattern (updateLocalPlugin)
- Delete-then-reinstall: `deleteTreeAbsolute` + delegate to `installLocalPlugin`
- Verify install exists first (accessAbsolute), return `error.PluginNotFound` if absent
- Then verify source exists, return `InstallError.SourceNotFound` if absent
- Ignore `error.FileNotFound` in deleteTree (idempotent cleanup)
- Caller owns the returned dest path slice

### Git plugin install pattern
- Detect git URLs by prefix: `std.mem.startsWith(u8, src, "https://")` etc., check https/http/git:///git@ 
- Run `git clone --depth=1 <url> <dest>` via `std.process.Child.init(&argv, allocator)` + `.spawn()` + `.wait()`
- Check `.spawn() catch return GitNotFound` to handle git-not-in-PATH
- Check `.wait()` `term == .Exited` and `code != 0` → `CloneFailed`
- `stderr_behavior = .Ignore` to suppress git output during install
- Name derivation: `lastIndexOfScalar(u8, url, '/')` + strip `.git` suffix with `endsWith`

### Registry plugin install pattern
- Parse `registry:org/name@version` source: strip `registry:` prefix, then `parseRegistryRef()`
- `parseRegistryRef()`: split on `/` for org, then split on `@` for version; all slices point into source (no alloc)
- URL resolution: org present → `https://github.com/<org>/zr-plugin-<name>`; no org → use `default_registry_base`
- Skip `zr-plugin-` prefix doubling: `if (std.mem.startsWith(u8, ref.name, "zr-plugin-"))`
- Add `--branch <version>` to git clone argv when version is non-empty (ArrayListUnmanaged build)
- Store `registry_ref = "org/name@version"` in plugin.toml (idempotent, same pattern as git_url)
- `PluginRegistry.loadAll()` for git/registry: check `~/.zr/plugins/<name>` exists; if yes, create synthetic local PluginConfig pointing there; if no, print info message
- **Plugin search pattern**: `searchInstalledPlugins()` calls `listInstalledPlugins()` then `readPluginMeta()` per dir; case-insensitive match via `std.ascii.toLower` into stack buffers; `SearchResult` owns duped strings, freed via `deinit()`; always free `meta_copy` via `var meta_copy = meta_opt; if (meta_copy) |*m| m.deinit()` pattern (avoids mutable capture of optional)
- **Mutable optional deinit pattern**: `var copy = optional_val; if (copy) |*item| item.deinit();` — needed because Zig doesn't allow `if (opt) |*ptr|` on immutable captures from `const` optionals

### Built-in plugin pattern
- `extern fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;` — POSIX setenv (std.posix.setenv doesn't exist in Zig 0.15)
- `std.fmt.allocPrint` requires comptime format string — use fixed format `"{s}: task '{s}' finished (exit {d})"`, not runtime template
- BuiltinHandle.BuiltinKind enum maps source string → handler; `loadBuiltin()` factory returns `?BuiltinHandle`
- `PluginRegistry` has both `plugins: ArrayList(Plugin)` (native) and `builtins: ArrayList(BuiltinHandle)` (built-in); `count()` returns their sum
- `SourceKind.builtin` in loader.zig parsed from `builtin:` prefix in TOML source string
- Git subprocess pattern for built-in plugins: `Child.init(argv, allocator)`, `.stdout_behavior = .Pipe`, collect via `pipe.read(&buf)` loop, check `.Exited` term
- curl subprocess for webhooks: `-s -X POST -H "Content-Type: application/json" -d <payload> <url>`

### In-memory Writer for Tests (Zig 0.15)
```zig
// Create a fixed-buffer writer for test output capture:
var buf: [512]u8 = undefined;
var writer = std.Io.Writer.fixed(&buf);
// ... call functions that take *std.Io.Writer ...
const out = buf[0..writer.end];  // bytes written so far
try std.testing.expect(std.mem.indexOf(u8, out, "expected") != null);
```
- `std.Io.Writer.fixed(&buf)` is the Zig 0.15 replacement for deprecated `std.io.fixedBufferStream`
- `writer.end` tracks bytes written (same as old `fbs.pos`)
- `buf[0..writer.end]` gives the written slice (same as old `fbs.getWritten()`)
- Do NOT use `std.Io.Writer.fromStream()` — does not exist in Zig 0.15
- For output to real stdout in tests: `std.fs.File.stdout().writer(&buf)` → `.interface`

### Progress Bar Pattern (output/progress.zig)
```zig
// Usage in a caller that runs tasks:
var bar = progress.ProgressBar.init(err_writer, use_color, task_count);
for (tasks) |task| {
    run(task);
    bar.tick(task.name);
}
bar.finish();
try progress.printSummary(w, use_color, passed, failed, skipped, elapsed_ms);
```
- Writer should be stderr (not stdout) when task output goes to stdout
- `tick(label)` advances by 1 and re-renders; `finish()` sets 100% and adds newline
- `printSummary()` is standalone — call after ScheduleResult is available
- Only shows ANSI codes when `use_color = true` (pass same flag as rest of CLI)
