## Schedule Remove Command Bug (2026-02-25, commit 61f0c26)
**Symptom**: `schedule remove` command returned exit code 255 (crash), integration tests 83 and 176 failing
**Root cause**:
- Line 205: `var entry = schedules.get(name).?;` returns a COPY of the hashmap entry
- Line 206: `entry.deinit(allocator);` frees memory from the COPY, not the original entry in hashmap
- Line 207: `_ = schedules.remove(name);` removes entry from hashmap without calling deinit on the original
- Result: Original entry's allocated strings are never freed (memory leak) + potential use-after-free crash

**Fix**: Use `getPtr()` instead of `get()` to get a pointer to the actual hashmap entry:
```zig
if (schedules.getPtr(name)) |entry_ptr| {
    entry_ptr.deinit(allocator);
    _ = schedules.remove(name);
}
```

**Lesson**: HashMap.get() returns a VALUE (copy), not a pointer. For structs with allocated fields, ALWAYS use getPtr() to get a pointer before calling deinit().

---

## Schedule Command Bugs (2026-02-24, commit e3b8d1d)
**Symptom**: Schedule commands had memory leaks AND schedule persistence didn't work
**Root causes**:
1. Memory leak: ScheduleEntry fields were allocated with `allocator.dupe()` but never freed when HashMap.deinit() was called
2. JSON persistence broken: `loadSchedules()` had placeholder code that always returned empty map

**Fix**:
1. Created `deinitSchedules()` helper that iterates HashMap values and calls entry.deinit() before HashMap.deinit()
2. Implemented proper line-by-line JSON parsing with state machine for entry name/fields
3. Critical bug in parser: initial logic skipped lines containing "}" in early check, preventing entry assembly logic from ever running — fixed by checking for "}" FIRST, assembling entry, then continuing

**Lesson**: StringHashMap.deinit() only frees the HashMap structure, not the values. Always iterate and free complex values manually.

---

# Debugging Insights

Record solutions to tricky bugs here. Future agents will check this before debugging.

## Format
```
### [Issue Title]
- Symptom: what was observed
- Cause: root cause
- Fix: what resolved it
- Prevention: how to avoid in future
```

---

### [openclaw CLI not in PATH]
- Symptom: `openclaw` command not found (exit 127)
- Cause: openclaw is installed via fnm/npm but not symlinked to PATH
- Fix: Use full path: `/Users/fn/.local/share/fnm/node-versions/v22.17.1/installation/bin/openclaw`
- Prevention: Always use full path for openclaw in autonomous sessions

### [std.ArrayList is now unmanaged in Zig 0.15.2]
- Symptom: `struct 'array_list.Aligned' has no member named 'init'` compiler error
- Cause: In 0.15.2, `std.ArrayList(T)` maps to `array_list.Aligned(T, null)` which is unmanaged
- Fix: Replace `std.ArrayList(T).init(allocator)` with `std.ArrayList(T){}`, and pass allocator to all mutation methods: `.deinit(allocator)`, `.append(allocator, item)`, `.appendSlice(allocator, items)`
- Note: `clearRetainingCapacity()` still takes no allocator; `pop()` now returns `?T`

### [Kahn's algorithm direction was inverted in graph modules]
- Symptom: topoSort test "simple linear chain" fails - `a_idx < b_idx` assertion
- Cause: In-degree was counting "how many nodes depend on this node" (reverse), should count "how many deps does this node have"
- Fix: Initialize `in_degree[node] = node.dependencies.items.len` instead of counting incoming references. When processing a node, iterate all nodes to find those whose deps include current, and decrement their in-degrees.
- Prevention: In the edge model `X -> Y means X depends on Y`, nodes with 0 deps (leaf tasks) should have in-degree 0 and run first.

### [Memory leaks in loader.zig parseToml]
- Symptom: GPA reports leaks for current_task, task_cmd, task_cwd, task_desc dupes
- Cause: parseToml was duping temp strings that addTask would also dupe, creating double-owned copies; old current_task was overwritten without freeing
- Fix: Use non-owning slices into `content` buffer for all temp vars; only addTask does the duplication
- Prevention: In parsers, delay allocation until the data is actually stored into a persistent structure

### [Memory leaks in dag.zig - StringHashMap key not freed on deinit]
- Symptom: GPA reports leaks from `addNode` for the key string
- Cause: `deinit` freed values (`node.deinit`) but not the map keys (separately allocated strings from `allocator.dupe(u8, name)`)
- Fix: In `deinit`, free `entry.key_ptr.*` before freeing the value
- Prevention: When using StringHashMap with owned keys, always free both key and value in deinit

### [.Inherit stdio in process tests causes deadlock in background tasks]
- Symptom: `zig build test` hangs indefinitely when run as a background task (e.g., in CI or background Bash)
- Cause: Child processes with `.Inherit` stdio inherit the background task's stdin/stdout/stderr pipes; the test harness and child process deadlock waiting on each other
- Fix: Add `inherit_stdio: bool = true` to ProcessConfig; tests use `inherit_stdio: false` (`.Pipe` for stdout/stderr); production uses `inherit_stdio: true`
- Prevention: Never use `.Inherit` stdio in test contexts; use `.Pipe` for stdout/stderr in tests (safe for small output < 64KB pipe buffer)

### [Integration tests hang with addRunArtifact() in build.zig]
- Symptom: `zig build integration-test` hangs indefinitely, no test output
- Cause: `addRunArtifact()` uses `--listen=-` protocol where test binary communicates with build system over stdin/stdout pipe; integration tests spawn `zr` binary as child process which also captures stdout/stderr, corrupting the protocol and causing deadlock
- Fix: Use `std.Build.Step.Run.create()` for integration tests (same as unit tests) to bypass `--listen=-` mode
- Prevention: ALWAYS use `Run.create()` for tests that spawn child processes or capture stdout/stderr (6666d24)

### [ArrayList.deinit does NOT zero items slice - errdefer double-free]
- Symptom: Segfault at 0xaaaaaaaaaaaaaaaa in errdefer loop after deinit
- Cause: After `list.deinit(allocator)`, the `items` field still points to freed memory with non-zero len — Zig fills freed memory with 0xaa in debug builds. Errdefer that iterates `items` then accesses freed memory.
- Fix: Immediately after deinit, reset to empty: `list = .{};` so errdefer sees len=0
- Prevention: Whenever manually calling deinit before function return, always reset the variable to `= .{}`

### [File.writer(&buf) unreliable for file appending]
- Symptom: History store tests: appended records not found on readback (only 1 of 2 records loaded)
- Cause: `file.writer(&buf)` with `fw.interface.flush()` did not reliably flush all data to the file when used for appending with `seekFromEnd`
- Fix: Use `std.fmt.bufPrint(&line_buf, ...)` then `file.writeAll(line)` for direct, unbuffered writes to the file
- Prevention: For file append operations, prefer `fmt.bufPrint` + `file.writeAll` over buffered File.writer

### [std.time.sleep removed in Zig 0.15 — use std.Thread.sleep]
- Symptom: `root source file struct 'time' has no member named 'sleep'` compiler error
- Cause: `std.time.sleep(ns)` was renamed/removed in Zig 0.15
- Fix: Use `std.Thread.sleep(ns)` instead
- Prevention: Always use `std.Thread.sleep(nanoseconds)` for sleep in Zig 0.15

### [deps_serial tasks must NOT be in the DAG for level-based scheduling]
- Symptom: deps_serial tasks ran twice — once via serial chain and once via DAG level runner
- Cause: collectDeps traversed deps_serial edges, putting those tasks in the needed set; DAG scheduler then also ran them at their natural level
- Fix: collectDeps only traverses `deps` (parallel edges); `deps_serial` tasks run exclusively via runSerialChain on-demand
- Prevention: Keep DAG-scheduled tasks and serial-chain tasks as disjoint sets

### [runSerialChain concurrent access to results list — data race]
- Symptom: Not immediately visible but identified in code review
- Cause: runSerialChain runs on main thread; worker threads also append to results under results_mutex; main thread had no lock
- Fix: runTaskSync accepts and holds results_mutex before any append
- Prevention: Any shared mutable state accessed from multiple threads must be protected

### [Partial inner-slice leak in multi-level alloc+dupe loops]
- Symptom: GPA would report leaks if dupe fails mid-loop in addTaskImpl
- Cause: errdefer only freed outer slice, not already-duped inner strings
- Fix: Track duped count (`deps_duped`, `serial_duped`) and free `slice[0..count]` in errdefer
- Prevention: In loops where each iteration allocates, track count for safe partial cleanup

### [Inverted control flow when using access() to check file existence]
- Symptom: Code review flagged: happy path buried inside catch block is confusing
- Cause: `access() catch |err| { if err != FileNotFound { ... } ... return 0; }; return 1;` — the success path lives inside error handler
- Fix: Use labeled block to extract a `exists: bool`, then branch explicitly:
  ```zig
  const exists: bool = blk: {
      dir.access(file, .{}) catch |err| {
          if (err == error.FileNotFound) break :blk false;
          // handle other errors
          return 1;
      };
      break :blk true;
  };
  if (exists) { /* refuse */ return 1; }
  // happy path
  ```
- Prevention: Never put the success path inside a catch block; use labeled blocks to extract booleans

### [Optional field pointer is fragile — use plain var for stable &field reference]
- Symptom: Code review flagged: `&optional_var.?.interface` — the `.?` unwrap may produce a copy, making the pointer point into a temporary
- Cause: `var x: ?SomeStruct = null; x = value; break :blk &x.?.someField;` — the `.?` dereference may return a copy of the inner value, not a stable reference
- Fix: Use a plain (non-optional) variable: `var plain: SomeStruct = undefined; plain = value; break :blk &plain.someField;`
- Prevention: Never take `&optional.?.field` — always unwrap to a plain var first, then take address of that

### [std.process.exit bypasses defers - buffered writers not flushed]
- Symptom: Error messages written to err_writer never appeared in stderr
- Cause: `std.process.exit()` terminates without running defers; buffered writer was never flushed
- Fix: Refactor to return exit codes from inner functions, flush all writers in main() before calling exit, never call std.process.exit from helper functions
- Prevention: Always flush buffered writers before process termination; use return-based exit code propagation instead of direct exit calls

## std.posix.setenv does not exist (Zig 0.15)
- **Problem**: `std.posix.setenv(key_z, val_z, 1)` → compile error: no member setenv
- **Solution**: Use `@extern` with comptime platform guard:
  ```zig
  fn posixSetenv(name_z: [*:0]const u8, val_z: [*:0]const u8, overwrite: bool) void {
      if (comptime native_os == .windows) return;
      const c_setenv = @extern(*const fn ([*:0]const u8, [*:0]const u8, c_int) callconv(.c) c_int, .{ .name = "setenv" });
      _ = c_setenv(name_z, val_z, if (overwrite) 1 else 0);
  }
  ```
- **Caveat**: `@extern` does NOT trigger automatic libc linking — must set `.link_libc = true` in build.zig
- **Prevention**: Check std.posix docs; setenv is a C standard library function not wrapped by Zig

## Windows cross-compile: undefined POSIX symbols
- **Symptom**: `std.posix.kill`, `std.posix.SIG.KILL`, `std.posix.getenv` → compile error on Windows targets
- **Cause**: `std.posix` namespace doesn't exist for Windows builds
- **Fix**: Centralize ALL POSIX-only calls in `src/util/platform.zig` with `if (comptime native_os == .windows) return;` guards
- **Prevention**: Never use `std.posix.*` directly in module code; always use `platform.zig` wrappers

## link_libc breaks Windows cross-compile
- **Symptom**: `unable to provide libc for target 'aarch64-windows-msvc'`
- **Cause**: `link_libc = true` applies to all targets; Zig doesn't bundle MSVC libc
- **Fix**: Conditional: `.link_libc = if (target.result.os.tag != .windows) true else null`
- **Prevention**: Always condition link_libc on target OS when cross-compiling for Windows

## std.fmt.allocPrint requires comptime format string
- **Problem**: `std.fmt.allocPrint(allocator, runtime_string, .{args...})` → compile error: argument to comptime parameter must be comptime-known
- **Solution**: Use a fixed comptime format string; embed the configurable part as a runtime argument, not as the format itself
- **Example**: `std.fmt.allocPrint(allocator, "{s}: task '{s}' finished (exit {d})", .{prefix, task, code})` where prefix is runtime

## Hard Resource Limits: Create-Before-Spawn + Apply-After Pattern
- **Problem**: Chicken-and-egg for resource limits — Linux cgroups need PID after spawn, Windows Job Objects need to be created before spawn and assigned after
- **Solution**: Two-phase lifecycle:
  1. `createHardLimits()` BEFORE `child.spawn()` — Linux creates cgroup dir and writes limits to control files; Windows creates Job Object with limits configured
  2. `child.spawn()` — process starts
  3. `applyHardLimits(&handle, child.id)` AFTER spawn — Linux writes PID to cgroup.procs; Windows calls AssignProcessToJobObject
- **Graceful fallback**: If any step fails (permissions, unsupported kernel), return no-op handle (cgroup_path=null or job_handle=null) and rely on soft limits via polling thread
- **Platform type difference**: `child.id` is `std.posix.pid_t` on Linux/macOS, but `std.os.windows.HANDLE` on Windows — use conditional `if (builtin.os.tag == .windows)` for type signature
- **Cleanup**: `defer handle.deinit()` after creation — Linux deletes cgroup dir; Windows closes job handle; macOS no-op

## ResourceMonitor Soft Limit Enforcement (Complementary to Hard Limits)
- **Problem**: Hard limits (cgroups/Job Objects) may fail due to permissions or be unavailable (macOS); need fallback enforcement
- **Solution**: ResourceMonitor.checkLimits() actively kills processes exceeding memory limits via killProcess()
- **Implementation**:
  - Add killProcess() in resource.zig with platform-specific handling (SIGKILL on POSIX, TerminateProcess on Windows)
  - checkLimits() calls killProcess(self.pid) when memory limit exceeded, returns true to signal termination
  - PID type varies by platform: `std.posix.pid_t` on POSIX, `std.os.windows.HANDLE` on Windows
- **Integration**: Called from resource watcher thread in process.zig when hard limits unavailable or disabled
- **Prevention**: Always provide fallback soft limits when kernel-level enforcement may be unavailable

## `zig build test` Hang — Stdout Protocol Corruption (2026-02-24, commit 55cb581)
- **Symptom**: `zig build test` hangs indefinitely; running test binary directly works fine (605/605 complete)
- **Cause**: Zig 0.15's build system runs tests with `--listen=-` (server protocol over stdin/stdout pipe). Test code that writes to `std.fs.File.stdout()` (help text, CLI output) corrupts the protocol → pipe deadlock. Both sides block: build system waiting for protocol messages, test binary blocked on full pipe buffer.
- **Fix**: In `build.zig`, replace `addRunArtifact(exe_tests)` with `Run.create()` + `addArtifactArg()` to bypass `enableTestRunnerMode()` which adds `--listen=-`. Also redirected test writers in main.zig to `/dev/null`.
  ```zig
  // DON'T: const run = b.addRunArtifact(exe_tests);  // adds --listen=-
  // DO:
  const run = std.Build.Step.Run.create(b, "run unit tests");
  run.addArtifactArg(exe_tests);
  run.has_side_effects = true;
  ```
- **Prevention**: NEVER use `std.fs.File.stdout()` in test code. Use `/dev/null` or buffer writers. If adding new test steps in build.zig, use `Run.create()` instead of `addRunArtifact()` for test binaries that produce stdout output.

## CI Infinite Trigger Loop (2026-02-24, commit 8cb5c08)
- **Symptom**: 6+ CI runs in_progress simultaneously, some hanging 1+ hour
- **Cause**: `ci.yml` had `on: push: branches: ["**"]` + automated cron agent pushing every hour + test hang = infinite queue
- **Fix**: Restrict to `branches: [main]`, add `paths-ignore` for `.claude/memory/**`, `docs/**`, `*.md`, add `concurrency` group with `cancel-in-progress: true`
- **Prevention**: Always use specific branch triggers; add paths-ignore for non-code files; use concurrency groups

## Double-Free Segfault in Test Code (2026-02-24, commit 55cb581)
- **Symptom**: Segfault at `allocator.free(runs)` in bench/runner.zig test
- **Cause**: `calculateStats()` stores the `runs` slice in returned struct; `stats.deinit()` frees it. Test also had `defer allocator.free(runs)` → double free
- **Fix**: Remove `defer allocator.free(runs)` from test — `stats.deinit()` owns the memory
- **Prevention**: If a function takes ownership of allocated memory (stores it in a struct that frees on deinit), the caller must NOT also free it

## Bus Error Freeing String Literals (2026-02-24, commit 55cb581)
- **Symptom**: Bus error in conformance/types.zig deinit when freeing HashMap keys
- **Cause**: Test inserted string literals into HashMap; deinit called `allocator.free(entry.key_ptr.*)` on non-heap memory
- **Fix**: Use `allocator.dupe()` to copy string literals before inserting into allocator-owned HashMap
- **Prevention**: Never insert string literals into containers whose deinit frees entries; always dupe first

## Threading TaskControl Through Scheduler and CLI Layers
- **Problem**: Interactive run creates TaskControl for keyboard input, but it wasn't connected to the actual task execution
- **Solution**: Add optional task_control parameter to SchedulerConfig and thread it through to process.run
- **Implementation**:
  1. Add `task_control: ?*control.TaskControl = null` to SchedulerConfig
  2. Add `task_control: ?*control.TaskControl` to WorkerCtx (non-optional — receives from config)
  3. Update cmdRun signature to accept `task_control: ?*control.TaskControl` parameter
  4. Update all cmdRun call sites: pass `null` for non-interactive, pass `ctrl` in interactive_run
  5. Thread task_control from SchedulerConfig → WorkerCtx → process.ProcessConfig
- **Testing**: Update all test calls to cmdRun to include `null` parameter
- **Prevention**: When adding new fields to scheduler/process config, consider the full path from CLI → scheduler → worker → process
