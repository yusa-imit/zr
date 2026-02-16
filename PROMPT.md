# zr Development Cycle Prompt

> This prompt is executed by an automated cron job. Claude Code runs this as a fully autonomous development session.

---

## Context

You are working on **zr** (zig-runner), a universal task runner & workflow manager CLI written in Zig 0.15.2.

Before doing anything, read these files to restore full project context:

1. `CLAUDE.md` — Project orchestration rules, coding standards, team patterns
2. `docs/PRD.md` — Full product requirements (source of truth)
3. `.claude/memory/project-context.md` — Current phase, checklist, progress
4. `.claude/memory/architecture.md` — Architecture decisions
5. `.claude/memory/decisions.md` — Past technical decision log
6. `.claude/memory/debugging.md` — Known issues and solutions
7. `.claude/memory/patterns.md` — Verified code patterns
8. `.claude/memory/zig-0.15-migration.md` — Zig 0.15 breaking changes (critical)

---

## Execution Protocol

Execute the following phases in strict order. Do NOT skip phases.

### Phase 1: Status Assessment

Run `/status` to understand the current project state:

- Check the current git branch (`v0.0.x` development branch expected)
- Run `git log --oneline -10` to see recent work
- Check which source files exist under `src/`
- If `build.zig` exists, run `zig build test` to verify current health
- Read `.claude/memory/project-context.md` for the Phase 1 checklist
- Identify the **next uncompleted item** from the checklist

Output a brief status summary before proceeding.

### Phase 2: Planning

Based on the status assessment, identify the highest-priority uncompleted work item from the Phase 1 roadmap:

1. **TOML Config Parser** — `src/config/loader.zig`, schema validation, env interpolation
2. **Task Definition & DAG** — `src/graph/` (DAG, Kahn's algorithm, topo sort)
3. **Parallel Execution Engine** — `src/exec/` (worker pool, process spawning, timeout)
4. **Basic CLI** — `src/cli/` (`run`, `list`, `graph` commands, arg parsing, color output)
5. **Cross-compilation CI** — `.github/workflows/` (6 target builds, automated testing)

**Rules for picking work**:
- If `build.zig` doesn't exist yet, start there (project bootstrap)
- If tests are failing, fix them before adding new features
- Follow dependency order: Config -> Graph -> Exec -> CLI
- Pick ONE focused work item per cycle. Do not attempt the entire roadmap at once.
- If the previous session left incomplete work, finish it first

Enter plan mode. Design the implementation approach:
- Which files to create/modify
- Module interfaces and key types
- Test strategy
- Any architectural decisions needed

Approve your own plan and proceed (autonomous mode).

### Phase 3: Implementation

Follow the Autonomous Development Protocol from `CLAUDE.md`:

**For complex features (3+ files), spawn a team**:
```
Leader (you, orchestrator)
  zig-developer   — Implementation (sonnet)
  test-writer     — Tests (sonnet)
  code-reviewer   — Review (sonnet)
```

**For simpler changes (1-2 files), implement directly.**

Implementation rules:
- Follow Zig conventions: camelCase functions, PascalCase types, SCREAMING_SNAKE constants
- Use Zig 0.15.2 APIs (check `.claude/memory/zig-0.15-migration.md` for breaking changes)
- Every public function must have tests in the same file
- Keep files under 500 lines
- Error messages must follow the pattern: `✗ [Context]: [What happened]\n  Hint: [Actionable suggestion]`
- No over-engineering. Only implement what's needed for the current work item.

### Phase 4: Verification

Run the full verification suite:

```bash
zig build           # Must compile cleanly
zig build test      # All tests must pass
```

If anything fails:
1. Analyze the error output
2. Fix the issue
3. Re-run verification
4. Repeat until green

Do NOT proceed to the next phase if tests are failing.

### Phase 5: Code Review

Self-review the changes by running `/review`:

- Check correctness against PRD requirements
- Check for memory leaks, undefined behavior, error handling gaps
- Verify all new functions have tests
- Check for unnecessary allocations or O(n^2) patterns
- Ensure Zig naming conventions are followed

If issues are found, fix them and re-verify (go back to Phase 4).

### Phase 6: Commit

Commit the changes following the project convention:

```
<type>: <subject>

<body explaining what and why>

Co-Authored-By: Claude <noreply@anthropic.com>
```

- Use appropriate type: `feat`, `fix`, `refactor`, `test`, `chore`
- Commit incrementally (one logical change per commit)
- Stage specific files, never use `git add -A`

### Phase 7: Memory Update

Update `.claude/memory/` files with anything learned this session:

- **project-context.md**: Update the Phase 1 checklist (check off completed items)
- **architecture.md**: Record any new architectural decisions
- **decisions.md**: Log any technical decisions made (with context and rationale)
- **debugging.md**: Record any bugs encountered and how they were fixed
- **patterns.md**: Record any verified Zig patterns that worked well

Commit memory updates separately: `chore: update session memory`

### Phase 8: Session Summary

Output a structured summary:

```
## Session Summary

### Completed
- [What was accomplished this cycle]

### Files Changed
- [List of files created/modified]

### Tests
- [Test count, pass/fail status]

### Next Priority
- [What the next cycle should work on]

### Issues / Blockers
- [Any problems encountered or unresolved issues]
```

---

## Safety Rules

- **Never force push** or run destructive git commands
- **Never modify `main` branch** directly — all work on `v0.0.x` or feature branches
- **Stop if stuck**: If the same error persists after 3 fix attempts, document the issue in `.claude/memory/debugging.md` and move on
- **Respect CI**: If the CI pipeline exists and the build structure changes, ensure `ci.yml` stays compatible
- **No scope creep**: Only implement what's in the current Phase 1 checklist. Do not start Phase 2+ work.
- **Team cleanup**: If a team was spawned, always shut it down before session end (`shutdown_request` -> `TeamDelete`)

---

## Time Budget

This prompt is designed for a single focused development session. Target:
- 1 meaningful feature or module per cycle
- All tests passing at session end
- Clean git history with descriptive commits
- Updated memory for the next session
