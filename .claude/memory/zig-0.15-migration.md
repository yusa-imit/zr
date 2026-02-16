# Zig 0.15.x Breaking Changes (from 0.14)

Critical API changes that all agents must follow when writing Zig code.

## Build System

- `addExecutable` now requires a module created via `b.createModule()`
- `addStaticLibrary()` removed → use `addLibrary(.{ .linkage = .static, ... })`
- Modules must have explicit target and optimization settings

## ArrayList → Unmanaged

```zig
// OLD (0.14)
var list = std.ArrayList(u8).init(allocator);
defer list.deinit();
try list.append(42);

// NEW (0.15)
var list: std.ArrayListUnmanaged(u8) = .{};
defer list.deinit(allocator);
try list.append(allocator, 42);
```

**Every mutation method now takes `allocator` as first argument.**

## I/O System

```zig
// OLD (0.14)
const stdout = std.io.getStdOut().writer();
try stdout.print("hello\n", .{});

// NEW (0.15)
var buf: [4096]u8 = undefined;
const stdout = std.io.getStdOut().writer(&buf);
defer stdout.flush() catch {};
try stdout.interface.print("hello\n", .{});
```

**Must flush before exit. Must use `.interface` property.**

## Type Reflection

- All `std.builtin.Type` tags are lowercase: `.int`, `.float`, `.pointer`
- Reserved words need escaping: `.@"struct"`, `.@"enum"`, `.@"union"`

## Renamed Modules

| Old (0.14) | New (0.15) |
|------------|------------|
| `std.rand` | `std.Random` |
| `std.TailQueue` | `std.DoublyLinkedList` |
| `std.zig.CrossTarget` | `std.Target.Query` |

## Page Size

```zig
// OLD: comptime constant
const page_size = std.mem.page_size;

// NEW: runtime function
const page_size = std.heap.pageSize();
```

## Signal Handling

- Use `.c` calling convention (lowercase) for signal handlers
- `posix.sigaction()` returns void
- Use `std.mem.zeroes(posix.sigset_t)` instead of removed `empty_sigset`
