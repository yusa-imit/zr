# Mixin Feature Implementation Checklist

**Status**: Tests Ready (20 passing tests will validate implementation)
**Test IDs**: 8000-8019
**Test File**: `/Users/fn/codespace/zr/tests/mixin_test.zig`
**Implementation Guide**: `/Users/fn/codespace/zr/.claude/test-requirements-mixins.md`

## Phase 1: Type Definitions (src/config/types.zig)

### Task Struct Changes
- [ ] Locate `pub const Task = struct {` (around line 906)
- [ ] Add field: `mixins: [][]const u8 = &.{},` after existing slice fields (e.g., after `hooks`)
- [ ] Update `Task.deinit()` to free mixin strings:
  ```zig
  for (self.mixins) |mixin_name| allocator.free(mixin_name);
  allocator.free(self.mixins);
  ```

### Mixin Data Structure
Option A (Recommended): Mixin as simplified Task
```zig
pub const Mixin = struct {
    // Same fields as Task, but subset:
    // env, deps, deps_serial, deps_optional, deps_if
    // tags, timeout_ms, retry_*, hooks, template, params
    // NOTE: No 'mixins' field in Mixin itself (avoid infinite recursion)
};
```

Option B: Store raw TOML table for lazy resolution
```zig
pub const Mixin = struct {
    name: []const u8,
    raw_fields: std.StringHashMap([]const u8), // Raw TOML values
};
```

### Config Struct Changes
- [ ] Add: `mixins: std.StringHashMap(Mixin) = undefined,`
- [ ] Update Config.init() to initialize mixins HashMap
- [ ] Update Config.deinit() to clean up mixins

## Phase 2: Parser Implementation (src/config/parser.zig)

### Locate TOML Parsing Section
- [ ] Find where `[tasks.NAME]` sections are parsed
- [ ] Add parallel section for `[mixins.NAME]` parsing

### Parsing Logic
- [ ] Extract mixin section name from `[mixins.NAME]`
- [ ] Parse mixin fields (same as task fields except no `mixins` field itself)
- [ ] For each field type:
  - [ ] `env = [["KEY", "value"]]` → parse as array of pairs
  - [ ] `deps = ["name1", "name2"]` → parse as string array
  - [ ] `tags = ["tag1"]` → parse as string array
  - [ ] `cmd = "..."` → parse as single string
  - [ ] `timeout_ms = 1000` → parse as integer
  - [ ] `hooks = [...]` → delegate to existing hook parser
  - [ ] `template = "name"` → parse as string
- [ ] Store parsed mixin in `config.mixins` HashMap

### Error Handling
- [ ] Reject `mixins` field inside a `[mixins.NAME]` section (prevent direct recursion)
- [ ] Validate all referenced task names in deps exist (or mark as optional)

## Phase 3: Mixin Resolution (src/config/loader.zig)

### Create Mixin Resolution Function
```zig
fn resolveMixins(allocator: std.mem.Allocator, config: *Config) !void {
    // For each task with mixins field:
    //   1. Validate all mixin names exist
    //   2. Build dependency graph (nested mixins)
    //   3. Detect cycles
    //   4. Apply composition
}
```

### Cycle Detection
```zig
fn detectMixinCycles(allocator: std.mem.Allocator,
                      config: *Config,
                      start_mixin: []const u8) !bool {
    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();

    return try visitMixin(config, start_mixin, &visited);
}

fn visitMixin(config: *Config, name: []const u8,
              visited: *std.StringHashMap(void)) !bool {
    if (visited.contains(name)) return true; // Cycle found
    try visited.put(name, {});

    const mixin = config.mixins.get(name) orelse return false;
    if (mixin.nested_mixins) |nested| {
        for (nested) |nested_name| {
            if (try visitMixin(config, nested_name, visited)) return true;
        }
    }
    return false;
}
```

### Field Composition Function
```zig
fn applyMixin(allocator: std.mem.Allocator,
              task: *Task,
              mixin: *const Mixin) !void {
    // For each field in mixin:

    // env: merge
    try mergeEnv(allocator, &task.env, mixin.env);

    // deps: concatenate
    try appendDeps(allocator, &task.deps, mixin.deps);
    try appendDeps(allocator, &task.deps_serial, mixin.deps_serial);
    try appendDeps(allocator, &task.deps_optional, mixin.deps_optional);
    try appendConditionalDeps(allocator, &task.deps_if, mixin.deps_if);

    // tags: union
    try unionTags(allocator, &task.tags, mixin.tags);

    // hooks: concatenate
    try appendHooks(allocator, &task.hooks, mixin.hooks);

    // Override fields (if set in mixin and not in task):
    if (task.cmd.len == 0 and mixin.cmd.len > 0) {
        task.cmd = try allocator.dupe(u8, mixin.cmd);
    }
    // ... similar for timeout_ms, retry_*, etc.
}
```

### Integration Point in loadFromFileInternal()
```zig
fn loadFromFileInternal(allocator: std.mem.Allocator, path: []const u8, ...) !Config {
    // ... existing code ...

    var config = try parseToml(allocator, content);
    errdefer config.deinit();

    // NEW: Apply mixin composition AFTER parsing, BEFORE workspace inheritance
    try resolveMixins(allocator, &config);

    // THEN: Apply workspace inheritance
    try inheritWorkspaceSharedTasks(allocator, &config);

    // ... rest of loading ...
}
```

## Phase 4: Error Messages

### Add Descriptive Errors
- [ ] Circular mixin: "Circular mixin reference detected: {cycles}"
- [ ] Undefined mixin: "Mixin '{name}' referenced by task '{task}' not found"
- [ ] Invalid field in mixin: "Field '{field}' not allowed in mixin definition"

## Phase 5: Testing & Validation

### Pre-submission Testing
```bash
# Run all integration tests
zig build integration-test

# Expected: 8000-8019 all PASS
```

### Test Breakdown
| Test ID | Should Pass | What Validates |
|---------|-------------|-----------------|
| 8000 | ✅ | Single mixin inheritance |
| 8001 | ✅ | Multiple mixins |
| 8002 | ✅ | Override semantics |
| 8003 | ✅ | 2-level nesting |
| 8004 | ✅ (expects error) | Cycle detection |
| 8005 | ✅ (expects error) | Undefined mixin error |
| 8006-8008 | ✅ | Field merging |
| 8009 | ✅ | 3-level nesting |
| 8010 | ✅ | Template interaction |
| 8011 | ✅ | Workspace integration |
| 8012 | ✅ | Empty mixin |
| 8013 | ✅ | All fields |
| 8014 | ✅ | Reusability |
| 8015 | ✅ | Order |
| 8016-8019 | ✅ | Advanced features |

### Unit Test Helpers
Consider adding unit tests in loader.zig for:
- `mergeEnv()` function
- `appendDeps()` function
- `unionTags()` function
- Cycle detection function
- But focus first on making integration tests pass

## Phase 6: Documentation Updates

- [ ] docs/guides/configuration.md
  - Add "Task Mixins" section
  - Document [mixins.NAME] syntax
  - Show examples: single mixin, multiple, nested
  - Explain field merging rules
  - Show real-world use case (e.g., CI mixin)

## Estimated Effort

- Phase 1 (Types): 30 minutes
- Phase 2 (Parser): 1-2 hours
- Phase 3 (Loader): 2-3 hours
- Phase 4 (Errors): 30 minutes
- Phase 5 (Testing): 30 minutes
- Phase 6 (Docs): 30 minutes
- **Total**: 5-7 hours

## Debugging Tips

### If tests fail:
1. Check test name carefully (8000-8019)
2. Run single test: `zig build integration-test -- test-name`
3. Verify TOML parsing: Check parser handles `[mixins.NAME]`
4. Verify field merging: Use std.debug.print() to trace merging
5. Check allocation: Verify Task.deinit() called for cleanup
6. Verify cycle detection: Test with circular mixins manually

### Common Issues
- **Parser doesn't find mixin section**: Check section name format `[mixins.NAME]`
- **Mixin fields ignored**: Verify applyMixin() covers all fields
- **Cycle detection hangs**: Ensure visited set is properly managed
- **Memory leaks**: Check Task.deinit() and Mixin.deinit() logic
- **Override not working**: Verify override field logic (task value wins)

## Validation Checklist

Before claiming success:
- [ ] All 20 tests pass (8000-8019 OK)
- [ ] `zig build test` still passes (no regressions)
- [ ] `zig build` produces valid binary
- [ ] Circular mixins rejected with error
- [ ] Undefined mixins rejected with error
- [ ] Nested mixins resolved correctly to 3+ levels
- [ ] Field merging follows spec (env merge, deps concat, tags union, override)
- [ ] Mixins work with templates and workspace inheritance
- [ ] No memory leaks (test with std.testing.allocator)
- [ ] Documentation added to guides/configuration.md

## Related Files

**Must Modify**:
- `/Users/fn/codespace/zr/src/config/types.zig`
- `/Users/fn/codespace/zr/src/config/parser.zig`
- `/Users/fn/codespace/zr/src/config/loader.zig`

**Reference**:
- `/Users/fn/codespace/zr/tests/mixin_test.zig` (tests)
- `/Users/fn/codespace/zr/.claude/test-requirements-mixins.md` (spec)
- `/Users/fn/codespace/zr/tests/workspace_inheritance_test.zig` (similar feature)

## Success Metrics

```
✅ Feature is DONE when:
- All 20 tests pass
- Tests verifying cycles/errors pass (exit non-zero, meaningful output)
- Docs are complete
- No regressions in existing tests
```

## Next Steps (for next developer)

1. Create backup: `git stash`
2. Start with Phase 1 (types.zig)
3. Run `zig build` after each phase
4. After each phase, run `zig build integration-test` to check progress
5. Commit incrementally (per-phase)
6. When all tests pass, commit final docs
7. Create PR with complete implementation
