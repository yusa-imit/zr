# Cycle 148 — Feature Mode: Task Up-to-Date Detection & Incremental Builds (75% Complete)

## Mode
FEATURE (counter 148, counter % 5 != 0)

## CI Status
GREEN (no failures on main)

## Open Issues
7 open (5 zuda migrations, 1 sailor v2.1.0, 1 zuda DAG), 0 bug reports

## Milestone
Task Up-to-Date Detection & Incremental Builds (IN PROGRESS 0% → 75%)

## Work Completed

### Phase 1: Schema Changes ✅
- Added `sources: [][]const u8` and `generates: [][]const u8` fields to Task struct
- Updated Task.deinit() to free both arrays and their contents
- Modified parser.zig to parse sources/generates from TOML (single string or array syntax)
- Updated addTaskImpl() signature with 2 new parameters
- Fixed 15+ call sites across types.zig, matrix.zig, parser.zig

### Phase 2: Up-to-Date Checker Module ✅
- Created src/exec/uptodate.zig (130 LOC)
  - isUpToDate() function: checks if generates exist and are newer than sources
  - expandGlobs() for pattern expansion using util/glob.zig
  - fileExists() and getFileMtime() helpers
  - 4 unit tests (all passing)

### Phase 3: Scheduler Integration ✅
- Added force_run field to SchedulerConfig (default false)
- Added sources, generates, force_run to WorkerCtx
- Integrated up-to-date check in workerFn before task execution
- Tasks skip when up-to-date (logs "Task 'name' is up-to-date, skipping")

### Phase 4: CLI Flags (Partial) ✅
- Added --force flag to global_flags in main.zig
- Updated cmdRun signature to accept force_run parameter
- Updated 10+ call sites: run.zig, interactive_run.zig, setup.zig, tui.zig, mcp/handlers.zig, matrix.zig
- --force flag disables up-to-date checks

### Integration Tests ✅
- Created tests/uptodate_test.zig (666 LOC, 12 tests)
  - Basic mtime comparison
  - Multiple sources/generates
  - Missing generates
  - Glob patterns
  - --force flag
  - --dry-run preview
  - Dependencies (up-to-date and stale)
  - No sources/generates (backward compatibility)
  - Empty generates
  - list --status

## Files Modified
- src/config/types.zig (Task.sources/generates, addTaskImpl signature)
- src/config/parser.zig (parse sources/generates arrays)
- src/exec/uptodate.zig (NEW: mtime checker + tests)
- src/exec/scheduler.zig (force_run, up-to-date integration)
- src/main.zig (--force flag)
- src/cli/run.zig, interactive_run.zig, setup.zig, tui.zig (cmdRun calls)
- src/mcp/handlers.zig, src/config/matrix.zig (cmdRun calls)
- tests/uptodate_test.zig (NEW: integration tests)
- tests/integration.zig (added uptodate_test import)

## Commits
1. 249180f: feat: add sources/generates fields and up-to-date checker (Phase 1-2)
2. 6eeb24b: feat: integrate up-to-date detection into scheduler and add --force flag (Phase 3-4)

## Test Status
1430/1438 unit tests passing (8 skipped, 0 failed)
Integration tests: 12 new tests (will pass gradually as features complete)

## Remaining Work (25%)
1. Enhance --dry-run to show up-to-date status ("Would skip: <task> (up-to-date)")
2. Add --status flag to list command (✓ up-to-date, ✗ stale, ? never-run)
3. Implement dependency propagation (stale dep → force dependent rebuild)
4. Add documentation (docs/guides/incremental-builds.md, configuration.md updates)

## Next Cycle
Continue with Phase 4-5 completion or switch to next READY milestone (Task Parameters & Dynamic Task Generation)

## Key Technical Decisions
- mtime-based comparison (i128 timestamps)
- Glob expansion via util/glob.zig (supports **, *, ?)
- force_run: bool in SchedulerConfig (clean separation of concerns)
- Backward compatibility: tasks without sources/generates always run
- Up-to-date check happens in workerFn before execution (single point of control)
