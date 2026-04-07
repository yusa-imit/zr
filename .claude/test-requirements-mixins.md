# Mixin Feature Test Requirements (v1.67.0)

## Test Overview

20 comprehensive integration tests (8000-8019) are ready for implementation of the Advanced Task Composition & Mixins feature.

**Location**: `/Users/fn/codespace/zr/tests/mixin_test.zig`

**Status**: Tests compile and are ready. They will fail until implementation is complete.

## Feature Specification (from tests)

### Configuration Format

**Mixin Definition**:
```toml
[mixins.common_env]
env = [["BUILD_TYPE", "debug"], ["LOG_LEVEL", "info"]]
deps = ["build"]
tags = ["core"]
```

**Task Mixin Usage**:
```toml
[tasks.test]
cmd = "echo 'testing'"
description = "Run tests"
mixins = ["common_env"]
```

**Nested Mixins**:
```toml
[mixins.level1]
tags = ["level1"]

[mixins.level2]
mixins = ["level1"]
tags = ["level2"]
```

### Field Merging Semantics (from tests)

| Field | Strategy | Behavior |
|-------|----------|----------|
| `env` | Merge | Task-level values override mixin values for same keys; new keys added |
| `deps` | Concatenate | Mixin deps run first, then task deps |
| `deps_serial` | Concatenate | Concatenated in order (mixin first) |
| `deps_optional` | Concatenate | All optional deps combined |
| `deps_if` | Concatenate | All conditional deps combined |
| `tags` | Union | Combine all tags, no duplicates |
| `cmd` | Override | Task value wins (last one wins) |
| `cwd` | Override | Task value wins |
| `description` | Override | Task value wins |
| `timeout_ms` | Override | Task value wins |
| `retry_max` | Override | Task value wins |
| `retry_delay_ms` | Override | Task value wins |
| `retry_backoff_multiplier` | Override | Task value wins |
| `retry_jitter` | Override | Task value wins |
| `max_backoff_ms` | Override | Task value wins |
| `hooks` | Concatenate | Mixin hooks execute first |
| `template` | Override | Task value wins |

### Multiple Mixins

When a task specifies `mixins = ["mixin1", "mixin2"]`:
1. Process left-to-right
2. Apply mixin1, then mixin2 (later mixins override earlier ones for override fields)
3. Apply task-level values (override all mixins)
4. For concatenative fields, all values are combined in order

### Error Handling

**Circular Mixin Detection**:
- If `mixins.a.mixins = ["b"]` and `mixins.b.mixins = ["a"]`, return error
- Should use DAG validation to detect cycles
- Error message should contain word "cycl" or "Cycl"

**Nonexistent Mixin**:
- Task references undefined mixin name
- Exit code should be non-zero
- Should fail gracefully

### Implementation Checklist

#### 1. Config Type Changes
- [ ] Add `mixins: [][]const u8 = &.{}` field to Task struct (or similar field name)
- [ ] Create Mixin struct/type for mixin definitions (or parse inline)
- [ ] Update Task.deinit() to free mixin references if using owned strings

#### 2. Parser Changes (src/config/parser.zig)
- [ ] Add parsing for `[mixins.NAME]` sections
- [ ] Parse `mixins = ["name1", "name2"]` field in tasks
- [ ] Each mixin section can contain any task field except `mixins` itself
- [ ] Store parsed mixins in Config struct

#### 3. Loader Changes (src/config/loader.zig)
- [ ] Add mixin resolution function with DAG cycle detection
- [ ] Before applying workspace inheritance, resolve task mixins
- [ ] Merge mixin fields into task using strategies above
- [ ] Apply field overrides: task level > mixin level
- [ ] Handle nested mixins (transitive closure)

#### 4. Validation
- [ ] Detect circular mixin references and return error
- [ ] Validate all referenced mixins exist
- [ ] Cycle detection can use visited set or DFS

#### 5. Integration Points
- [ ] Mixins load before workspace inheritance (loadFromFileInternal pipeline)
- [ ] Mixin resolution happens in same place as workspace inheritance
- [ ] No CLI changes required (feature is TOML-only)
- [ ] `zr list` command should show composed tasks normally

#### 6. Test Compatibility
- [ ] Tests use `zr list` to verify mixin inheritance
- [ ] Tests use `zr <task>` to verify execution with inherited fields
- [ ] Tests verify JSON output includes composed fields
- [ ] Tests verify environment variables are inherited (task env vars are available in process)
- [ ] Tests verify dependency execution order

## Test IDs & Coverage

| Range | Purpose | Count |
|-------|---------|-------|
| 8000-8001 | Basic inheritance & composition | 2 |
| 8002-8008 | Field merging semantics | 7 |
| 8003-8009 | Nesting & complex scenarios | 3 |
| 8004-8005 | Error handling | 2 |
| 8010-8011 | Integration with existing features | 2 |
| 8012-8013 | Edge cases | 2 |
| 8014-8015 | Reusability & order | 2 |
| 8016-8019 | Advanced features & output | 4 |

## Running Tests

```bash
# Compile and run all integration tests (including new mixin tests)
zig build integration-test

# Run only mixin tests (if test runner supports filtering)
zig build integration-test -- 8000 8001 8002 ...

# Run unit + integration tests
zig build test && zig build integration-test
```

## Test Entry Points

All tests in `mixin_test.zig` follow this pattern:

1. Create temporary directory with `std.testing.tmpDir()`
2. Write TOML config with mixins and tasks
3. Run `zr list` or `zr <task>` via `runZr()` helper
4. Assert on exit code and stdout/stderr

**Helper functions** (from `tests/helpers.zig`):
- `writeTmpConfig(allocator, dir, toml_string)` → config file path
- `runZr(allocator, args_slice, cwd)` → ZrResult { exit_code, stdout, stderr }

## Key Implementation Notes

### Mixin Application Order

When task has `mixins = ["mixin1", "mixin2"]`:
```
Final Field = applyMixin(task, applyMixin(mixin2, applyMixin(mixin1, empty)))
```

### Env Merging Example
```toml
[mixins.m1]
env = [["A", "m1_a"], ["B", "m1_b"]]

[mixins.m2]
env = [["B", "m2_b"], ["C", "m2_c"]]

[tasks.test]
env = [["A", "task_a"], ["D", "task_d"]]
mixins = ["m1", "m2"]

# Result: env = { A: "task_a", B: "m2_b", C: "m2_c", D: "task_d" }
```

### Deps Concatenation Example
```toml
[mixins.m1]
deps = ["build"]

[mixins.m2]
deps = ["format"]

[tasks.test]
deps = ["lint"]
mixins = ["m1", "m2"]

# Result: deps = ["build", "format", "lint"]
# Execution order: build → format → lint → test
```

### Tags Union Example
```toml
[mixins.m1]
tags = ["ci", "build"]

[mixins.m2]
tags = ["test", "build"]

[tasks.test]
tags = ["smoke", "ci"]
mixins = ["m1", "m2"]

# Result: tags = ["ci", "build", "test", "smoke"] (no duplicates)
```

## Troubleshooting

If tests fail during implementation:

1. **Config parsing errors**: Check TOML syntax in test fixtures
2. **Missing mixin field**: Verify Task struct has `mixins` field
3. **Merge order wrong**: Double-check field merging strategies table above
4. **Cycle detection not working**: Ensure DAG validation runs before applying mixins
5. **Workspace integration failing**: Mixins should be resolved before workspace inheritance

## Success Criteria

All 20 tests pass:
```
8000: basic single mixin inheritance...OK
8001: multiple mixins composition...OK
8002: task overrides mixin values...OK
[... 8003-8019 all OK ...]
20/20 tests passed
```

## References

- Workspace inheritance tests (6000-6014): `/Users/fn/codespace/zr/tests/workspace_inheritance_test.zig`
- Integration test patterns: `/Users/fn/codespace/zr/.claude/memory/patterns.md`
- Config types: `/Users/fn/codespace/zr/src/config/types.zig`
- Config parser: `/Users/fn/codespace/zr/src/config/parser.zig`
- Config loader: `/Users/fn/codespace/zr/src/config/loader.zig`
- Milestones: `/Users/fn/codespace/zr/docs/milestones.md`
