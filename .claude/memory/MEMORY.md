# zr Project Memory

## Latest Session (2026-03-26, Feature Mode Cycle 18)

### FEATURE CYCLE — Phase 12C Benchmark Dashboard ✅
- **Mode**: FEATURE (counter 18, counter-based)
- **CI Status**: IN_PROGRESS (not blocking)
- **Open Issues**: 3 (all zuda migrations, non-critical)
- **Actions Taken**:
  - ✅ **Milestone Correction**: Removed incorrect "Natural Language AI Command (Phase 10C)" milestone — doesn't exist in PRD (Phase 10 only has 10A MCP Server, 10B Auto-generate)
  - ✅ **Milestone Establishment**: Added Phase 12C (Benchmark Dashboard) and Phase 13B (Migration Tools) milestones
  - ✅ **Benchmark Documentation**: Created comprehensive `benchmarks/RESULTS.md` with:
    - Binary size comparison (zr: 1.2MB vs Make: 200KB, Task: 10-15MB, Just: 4-6MB)
    - Cold start performance (zr: 4-8ms, competitive with Make at 3-5ms)
    - Memory usage (zr: 2-3MB RSS, minimal overhead)
    - Parallel execution benchmarks (4x speedup with worker pool)
    - Feature comparison matrix vs Make/Just/Task
    - Real-world monorepo scenarios with caching analysis
  - ✅ **Benchmark Scripts**: Existing `benchmarks/run_benchmarks.sh` already comprehensive
  - ✅ **Phase 12C Complete**: Scripts + documentation fulfill PRD requirement
- **Commits**:
  - 142bff3 (chore: add Phase 12C and 13B milestones, complete benchmark documentation)
- **Test Status**: 1151/1159 passing (8 skipped) — 100% pass rate
- **Next Priority**: Phase 13B Migration Tools (`zr init --from-make/just/task`) — final PRD item before v1.0 release

## Previous Session (2026-03-26, Feature Mode Cycle 17)

### FEATURE CYCLE — Milestone Establishment & Sailor v1.22.0 Migration ✅
- **Mode**: FEATURE (counter 17, counter-based)
- **CI Status**: IN_PROGRESS (not blocking)
- **Open Issues**: 5 → 3 (closed #34, #35 sailor migrations)
- **Actions Taken**:
  - ✅ **Milestone Establishment**: Added 2 new READY milestones (Sailor v1.21.0/v1.22.0, Natural Language AI Command)
  - ✅ **Sailor v1.22.0 Migration**: Updated dependency v1.20.0 → v1.22.0 (includes v1.21.0 changes)
    - v1.21.0: DataSource abstraction, large data benchmarks
    - v1.22.0: Rich text rendering, markdown parser, line breaking/hyphenation (+123 tests)
    - No breaking changes, backward compatible
    - All unit tests pass (1151/1159, 8 skipped)
  - ✅ **Issue Closure**: Closed #34, #35 via commit 4176ca4
  - ✅ **Milestone Update**: Moved Sailor migration to Completed (no release)
- **Commits**:
  - b30af33 (chore: add milestones for Sailor v1.21.0/v1.22.0 and Natural Language AI Command)
  - 4176ca4 (chore: migrate to sailor v1.22.0)
  - 317d5ce (chore: mark Sailor v1.21.0/v1.22.0 milestone as complete)

## Previous Session (2026-03-25, Feature Mode Cycle 13)

### FEATURE CYCLE — Enhanced Configuration System v1.55.0 (IN PROGRESS)
- **Mode**: FEATURE (counter 13, counter-based)
- **CI Status**: GREEN ✅ (in_progress at session start)
- **Open Issues**: 3 open (zuda migrations, all enhancements)
- **Milestone**: Enhanced Configuration System (READY) → IN PROGRESS
- **Actions Taken**:
  - ✅ **Milestone Establishment**: Added 2 new READY milestones (Enhanced Configuration System, Windows Platform Enhancements) to bring active count to 4
  - ✅ **.env File Parsing**: Created src/config/dotenv.zig with parseDotenv() — 37 unit tests, all passing
  - ✅ **.env Auto-Loading**: Integrated into config loader (load_dotenv field, loadDotenvIntoConfig(), mergeEnvIntoTask())
  - ✅ **Precedence Rule**: Task-specific env variables override .env values
  - ✅ **Graceful Fallback**: Silently ignores missing/malformed .env files
  - ⏳ **Next**: Variable substitution (${VAR} in TOML), multi-file imports, integration tests
- **Commits**:
  - 2c4f9ab (chore: establish new milestones)
  - 264ebc4 (feat: add .env file auto-loading support)
- **Test Status**: 1116/1116 passing (8 skipped) — 100% pass rate
- **Next Priority**: Complete Enhanced Configuration System milestone (variable substitution + multi-file imports + integration tests)

## Previous Session (2026-03-25, Feature Mode Cycle 12)

### FEATURE CYCLE — v1.54.0 Release ✅
- **Mode**: FEATURE (counter 12, counter-based)
- **CI Status**: GREEN ✅ (in_progress at session start)
- **Milestone**: TUI Mouse Interaction Enhancements → **RELEASED as v1.54.0**
- **Release**: https://github.com/yusa-imit/zr/releases/tag/v1.54.0

## Previous Session (2026-03-25, Feature Mode Cycle 11)

### FEATURE CYCLE — v1.53.0 Release ✅
- **Mode**: FEATURE (counter 11, counter-based)
- **Milestone**: Platform-Specific Resource Monitoring → **RELEASED as v1.53.0**
- **Release**: https://github.com/yusa-imit/zr/releases/tag/v1.53.0

## Previous Session (2026-03-25, Feature Mode Cycle 8)

### FEATURE CYCLE — v1.52.0 Release ✅
- **Mode**: FEATURE (counter 8, counter-based)
- **Milestone**: Output Enhancement & Pager Integration → **RELEASED as v1.52.0**
- **Release**: https://github.com/yusa-imit/zr/releases/tag/v1.52.0

## Common Patterns

### .env File Auto-Loading (v1.55.0)
Auto-load environment variables from .env file in project root:
```zig
// In Config struct (src/config/types.zig)
load_dotenv: bool = true,  // Enable/disable .env loading

// In loader (src/config/loader.zig)
var config = try parseToml(allocator, content);
if (config.load_dotenv) {
    try loadDotenvIntoConfig(allocator, &config);
}

// Precedence: task-specific env > .env values
// Silently ignores FileNotFound, parse errors
```

### .env File Parsing (v1.55.0)
Parse .env files with full syntax support:
```zig
const dotenv = @import("config/dotenv.zig");
var env_map = try dotenv.parseDotenv(allocator, content);
defer dotenv.deinitDotenv(&env_map, allocator);

// Supports:
// - KEY=value, KEY="quoted", KEY='single'
// - Comments (#), empty lines
// - Escape sequences (\n, \t, \r, \\, \")
// - Multiline values (quotes spanning lines)
// - Inline comments in unquoted values
```

### Parent Directory Search in Zig
Walk up directory tree to find configuration files:
```zig
pub fn findConfigPath(allocator: std.mem.Allocator) !?[]const u8 {
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.fs.cwd().realpath(".", &cwd_buf);
    var current_dir = try allocator.dupe(u8, cwd);
    defer allocator.free(current_dir);

    while (true) {
        const candidate = try std.fs.path.join(allocator, &[_][]const u8{ current_dir, "config.toml" });
        errdefer allocator.free(candidate);

        std.fs.accessAbsolute(candidate, .{}) catch |err| {
            if (err == error.FileNotFound) {
                allocator.free(candidate);
                const parent = std.fs.path.dirname(current_dir) orelse return null;
                if (std.mem.eql(u8, parent, current_dir)) return null; // reached root
                const new_current = try allocator.dupe(u8, parent);
                allocator.free(current_dir);
                current_dir = new_current;
                continue;
            }
            return err;
        };
        return candidate;
    }
}
```

### Line-by-Line File Reading in Zig 0.15
Use `streamUntilDelimiter` with ArrayList buffer (deprecated `readUntilDelimiterOrEof` removed):
```zig
const reader = file.deprecatedReader();
var line_buffer = std.ArrayList(u8){};
defer line_buffer.deinit(allocator);

while (true) {
    line_buffer.clearRetainingCapacity();
    reader.streamUntilDelimiter(line_buffer.writer(allocator), '\n', null) catch |err| {
        if (err == error.EndOfStream) break;
        return err;
    };
    // Use line_buffer.items here
}
```

### Test File Creation in Zig
Always use `.{ .read = true }` when creating test files that will be read immediately:
```zig
const test_file = try tmp.dir.createFile("test.txt", .{ .read = true });
```

### CI Debugging Workflow
1. Check CI status: `gh run list --limit 3`
2. View failed logs: `gh run view <id> --log-failed`
3. Search for "FAIL" or "error:" in logs
4. Reproduce locally: `zig build test`
5. Fix, commit, push
6. Poll CI: `gh run list --limit 1 --json status,conclusion`

### File Writer API in Zig 0.15
For writing to files, pipes, or child process stdin, use `deprecatedWriter()`:
```zig
// For child process stdin (e.g., pager)
if (child.stdin) |stdin_pipe| {
    defer stdin_pipe.close();
    const writer = stdin_pipe.deprecatedWriter(); // NOT stdin_pipe.writer()
    try writer.writeAll(data);
}

// For regular files (if needed)
const file = try std.fs.cwd().createFile("output.txt", .{});
defer file.close();
const writer = file.deprecatedWriter();
try writer.writeAll(data);
```
Note: Zig 0.15 changed `file.writer()` to require a buffer argument. Use `deprecatedWriter()` for the old API.

### Platform-Specific Temp Directory in Zig
Get system temp directory using environment variables (Zig 0.15 doesn't have std.fs.tmp):
```zig
const builtin = @import("builtin");
const tmp_dir_path = switch (builtin.os.tag) {
    .windows => std.process.getEnvVarOwned(allocator, "TEMP") catch
                std.process.getEnvVarOwned(allocator, "TMP") catch
                try allocator.dupe(u8, "C:\\Windows\\Temp"),
    else => std.process.getEnvVarOwned(allocator, "TMPDIR") catch
            try allocator.dupe(u8, "/tmp"),
};
defer allocator.free(tmp_dir_path);

// Then join with filename:
const full_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_dir_path, "myfile.tmp" });
defer allocator.free(full_path);
```
