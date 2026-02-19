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
- **Solution**: Use C extern directly: `extern fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;`
- **Prevention**: Check std.posix docs; setenv is a C standard library function not wrapped by Zig

## std.fmt.allocPrint requires comptime format string
- **Problem**: `std.fmt.allocPrint(allocator, runtime_string, .{args...})` → compile error: argument to comptime parameter must be comptime-known
- **Solution**: Use a fixed comptime format string; embed the configurable part as a runtime argument, not as the format itself
- **Example**: `std.fmt.allocPrint(allocator, "{s}: task '{s}' finished (exit {d})", .{prefix, task, code})` where prefix is runtime
