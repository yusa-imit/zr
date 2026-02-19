Show the current status of the zr project.

Gather and display:

1. **Git Status**:
   - Current branch
   - Uncommitted changes count
   - Last commit message and date
   - Ahead/behind remote

2. **Build Status**:
   - Run `zig build` and report success/failure
   - Binary size if exists

3. **Test Status**:
   - Run `zig build test` and report pass/fail count

4. **Project Progress**:
   - Read `docs/PRD.md` Phase 1 checklist
   - Check which source files exist vs expected structure
   - Report completion percentage

5. **Memory Summary**:
   - Read `.claude/memory/` files
   - Report key recent decisions and known issues

Format output as a clear dashboard.
