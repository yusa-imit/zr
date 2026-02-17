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

### Parser Non-Owning Slice Pattern
```zig
// Use non-owning slices in parsers; only dupe when storing:
var current_task: ?[]const u8 = null;
// ...
current_task = trimmed[start..][0..end]; // no dupe - slice into content
// ...
try storeTask(allocator, current_task, ...); // storeTask does the dupe
```
