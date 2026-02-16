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
