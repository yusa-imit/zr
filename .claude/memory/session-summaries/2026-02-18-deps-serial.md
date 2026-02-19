# Session Summary — 2026-02-18 deps_serial

## Completed
- Implemented `deps_serial` field for sequential dependency execution (PRD §5.2.2)
- Fixed 3 critical memory safety bugs found in code review:
  1. Partial inner-string leak in `addTaskImpl` (errdefer count tracking)
  2. Data race: `runTaskSync` now holds `results_mutex` when appending
  3. Infinite recursion on `deps_serial` cycles (false sentinel before recursion)

## Files Changed
- `src/config/loader.zig` — Task gains `deps_serial` field; parser handles `deps_serial` key
- `src/exec/scheduler.zig` — `runSerialChain`, `runTaskSync` helpers; `collectDeps` excludes serial tasks from DAG

## Tests
- 48/48 tests passing (added 3 new tests for deps_serial)

## Next Priority
- Expression engine (`src/config/expression.zig`) — lexer + parser + evaluator for condition fields
- OR watch mode (`src/watch/`) — inotify/kqueue watcher + debounce
- OR retry logic — `retry = { max = 3, delay = "5s" }` field in Task

## Key Decisions
- deps_serial tasks are NOT in the DAG; they run exclusively via `runSerialChain` inline
- Cycle detection uses false sentinel pattern (see patterns.md)
