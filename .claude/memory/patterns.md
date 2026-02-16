# Verified Code Patterns

Patterns confirmed to work well in this project. Update as patterns evolve.

## Zig Patterns

(To be populated as implementation progresses)

### Allocator Usage
- Use `std.testing.allocator` in tests for leak detection
- Use `std.heap.ArenaAllocator` for request-scoped work
- Pass allocator as first parameter to init functions

### Error Handling
- Define specific error sets per module
- Propagate errors with `try`
- Use `errdefer` for cleanup on error paths
