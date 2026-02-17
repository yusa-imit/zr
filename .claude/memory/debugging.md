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

### [openclaw CLI not available]
- Symptom: `openclaw` command not found when trying to send Discord notifications
- Cause: openclaw CLI is not installed or not in PATH
- Fix: Document in session summary output instead of sending Discord message
- Prevention: Check for openclaw availability before autonomous cycles, or use alternative notification method

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

### [std.process.exit bypasses defers - buffered writers not flushed]
- Symptom: Error messages written to err_writer never appeared in stderr
- Cause: `std.process.exit()` terminates without running defers; buffered writer was never flushed
- Fix: Refactor to return exit codes from inner functions, flush all writers in main() before calling exit, never call std.process.exit from helper functions
- Prevention: Always flush buffered writers before process termination; use return-based exit code propagation instead of direct exit calls
