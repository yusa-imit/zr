# Architecture Decisions

## Module Dependency Flow

```
CLI → Config → Graph → Exec → Plugin
              ↘ Output (shared)
```

- Config engine is independent; no dependency on execution
- Graph engine takes parsed config, produces execution plan
- Exec engine takes execution plan, manages processes
- Output module is shared across all layers for terminal rendering

## Key Design Choices

### TOML + Expression Engine (decided in PRD)
- Config format: TOML for readability
- Expression engine for conditions, matrix, retry logic
- Keeps config declarative while supporting dynamic behavior

### Worker Pool (std.Thread)
- Using OS threads via std.Thread (not async, which is experimental in Zig)
- Default worker count = logical CPU cores
- Per-task concurrency limits via semaphores

### DAG for Dependencies
- Kahn's Algorithm for cycle detection
- Topological sort for execution order
- Critical path calculation for bottleneck identification
