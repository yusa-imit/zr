const std = @import("std");
const helpers = @import("helpers.zig");

// ---------------------------------------------------------------------------
// Integration tests for Interactive Task Builder TUI (`zr add task --interactive`)
// ---------------------------------------------------------------------------
//
// These tests verify the form-based TUI for building tasks without manually
// editing TOML. Tests should FAIL initially (Red phase) since the feature
// is not yet implemented.
//
// Requirements (from milestone "Interactive Task Builder TUI"):
// 1. Form-based TUI with sailor Form widget (text input, select, checkbox fields)
// 2. Field validation with instant feedback (required fields, valid expressions, existing deps)
// 3. Inline contextual help (hover/F1 for field descriptions, examples)
// 4. Live TOML preview pane showing generated config
// 5. Dependency picker with autocomplete from existing tasks
// 6. Save to zr.toml with syntax-highlighted diff preview
// 7. Template selection (common task patterns: build, test, deploy, docker, git)
// ---------------------------------------------------------------------------

const BASIC_TOML =
    \\[tasks.build]
    \\cmd = "zig build"
    \\
    \\[tasks.test]
    \\cmd = "zig build test"
    \\deps = ["build"]
    \\
    \\[tasks.deploy]
    \\cmd = "echo 'Deploying...'"
    \\deps = ["test"]
    \\
;

// ---------------------------------------------------------------------------
// Test 1: Command registration and basic invocation
// ---------------------------------------------------------------------------

test "1000: add task --interactive command is recognized" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_TOML });

    // Run zr add task --interactive (will fail in non-TTY, but should recognize command)
    var result = try helpers.runZr(allocator, &.{ "add", "task", "--interactive" }, tmp_path);
    defer result.deinit();

    // Should NOT show "unknown option" error — command should be recognized
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unknown option") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unrecognized") == null);
}

test "1001: add workflow --interactive command is recognized" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_TOML });

    var result = try helpers.runZr(allocator, &.{ "add", "workflow", "--interactive" }, tmp_path);
    defer result.deinit();

    // Should NOT show "unknown option" error
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "unknown option") == null);
}

// ---------------------------------------------------------------------------
// Test 2: Non-TTY environment fallback
// ---------------------------------------------------------------------------

test "1002: interactive mode shows graceful fallback in non-TTY" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = BASIC_TOML });

    var result = try helpers.runZr(allocator, &.{ "add", "task", "--interactive" }, tmp_path);
    defer result.deinit();

    // Should NOT crash or hang in non-TTY environment
    // Should show a fallback message or gracefully exit
    const stdout_lower = try std.ascii.allocLowerString(allocator, result.stdout);
    defer allocator.free(stdout_lower);

    const stderr_lower = try std.ascii.allocLowerString(allocator, result.stderr);
    defer allocator.free(stderr_lower);

    // EXPECTED TO FAIL: No TTY fallback message implemented yet
    const has_fallback_msg = std.mem.indexOf(u8, stdout_lower, "interactive") != null or
        std.mem.indexOf(u8, stdout_lower, "terminal") != null or
        std.mem.indexOf(u8, stderr_lower, "interactive") != null or
        std.mem.indexOf(u8, stderr_lower, "terminal") != null;

    try std.testing.expect(has_fallback_msg);
}

// ---------------------------------------------------------------------------
// Test 3: Error recovery and edge cases
// ---------------------------------------------------------------------------

test "1035: form handles missing zr.toml gracefully" {
    // Expected: If zr.toml doesn't exist, show error and suggest 'zr init'.
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    // No zr.toml created

    var result = try helpers.runZr(allocator, &.{ "add", "task", "--interactive" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    const has_hint = std.mem.indexOf(u8, result.stderr, "zr init") != null or
        std.mem.indexOf(u8, result.stdout, "zr init") != null;
    try std.testing.expect(has_hint);
}

test "1036: form handles corrupted zr.toml gracefully" {
    // Expected: If config parse fails, show error with fix suggestions.
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    try tmp.dir.writeFile(.{ .sub_path = "zr.toml", .data = "[tasks.build\ncmd = invalid" });

    var result = try helpers.runZr(allocator, &.{ "add", "task", "--interactive" }, tmp_path);
    defer result.deinit();

    try std.testing.expect(result.exit_code != 0);
    try std.testing.expect(result.stderr.len > 0);
}

// ---------------------------------------------------------------------------
// Placeholder tests for future implementation
// (These skip until the interactive form module is created)
// ---------------------------------------------------------------------------

test "1003: form validates task name is required" {
    // Expected: Form should reject empty task name
    // Requires: src/cli/add_interactive.zig with FormState.validate()
    return error.SkipZigTest;
}

test "1004: form validates task name uniqueness" {
    // Expected: Form should reject task names that already exist in config
    // Requires: FormState validator that loads and checks existing tasks
    return error.SkipZigTest;
}

test "1005: form validates command field when provided" {
    // Expected: cmd field validation (non-empty when provided, trimmed)
    // Requires: FieldValidator.validateCommand()
    return error.SkipZigTest;
}

test "1006: form validates expression syntax in condition field" {
    // Expected: condition field should validate expression syntax
    // Requires: FieldValidator.validateExpression() using existing expression engine
    return error.SkipZigTest;
}

test "1007: form validates dependency names exist in config" {
    // Expected: deps field should validate against existing task names
    // Requires: DependencyPicker.validate() with task name lookup
    return error.SkipZigTest;
}

test "1008: form generates correct TOML preview for minimal task" {
    // Expected: Preview pane shows generated TOML as user types
    // Requires: TomlPreview.generate() method
    return error.SkipZigTest;
}

test "1009: form generates correct TOML preview for task with all fields" {
    // Expected: Preview shows all fields correctly formatted
    // Requires: TomlPreview.generate() with full Task struct support
    return error.SkipZigTest;
}

test "1010: TOML preview escapes special characters correctly" {
    // Expected: Preview correctly escapes quotes, backslashes, newlines
    // Requires: TomlPreview.escapeString() (reuse existing escapeTomlString from add.zig)
    return error.SkipZigTest;
}

test "1011: TOML preview updates in real-time as user types" {
    // Expected: Preview pane updates on every keystroke (with debounce)
    // Requires: Form field onChange event handlers
    return error.SkipZigTest;
}

test "1012: dependency picker shows list of existing tasks" {
    // Expected: Autocomplete dropdown with existing task names
    // Requires: DependencyPicker widget with task name loading
    return error.SkipZigTest;
}

test "1013: dependency picker supports multi-select" {
    // Expected: User can select multiple dependencies from list
    // Requires: Multi-select UI component (checkbox list or tag interface)
    return error.SkipZigTest;
}

test "1014: dependency picker prevents circular dependencies" {
    // Expected: Real-time cycle detection when adding dependencies
    // Requires: Integration with existing DAG cycle detection
    return error.SkipZigTest;
}

test "1015: template picker shows common task patterns" {
    // Expected: Dropdown with predefined templates (build, test, deploy, docker, git)
    // Requires: TemplateEngine with template definitions
    return error.SkipZigTest;
}

test "1016: selecting template pre-fills form fields" {
    // Expected: Template selection populates form with template values
    // Requires: TemplateEngine.apply() method
    return error.SkipZigTest;
}

test "1017: template supports variable substitution" {
    // Expected: Templates can use {{variable}} syntax (e.g., {{name}}, {{tag}})
    // Requires: TemplateEngine.substitute() method
    return error.SkipZigTest;
}

test "1018: user can customize template after selection" {
    // Expected: All fields remain editable after template application
    // Requires: Form state management that allows post-template edits
    return error.SkipZigTest;
}

test "1019: save appends task to zr.toml file" {
    // Expected: Save button writes TOML entry to config file
    // Requires: FormState.save() method with file append logic
    return error.SkipZigTest;
}

test "1020: save shows diff preview before writing" {
    // Expected: Confirmation dialog shows TOML diff with syntax highlighting
    // Requires: DiffPreview widget with TOML syntax highlighter
    return error.SkipZigTest;
}

test "1021: save validates config after write" {
    // Expected: Re-parse zr.toml after save to ensure validity
    // Requires: Post-save validation using existing parser
    return error.SkipZigTest;
}

test "1022: save handles write errors gracefully" {
    // Expected: File system errors (permission denied, disk full) preserve form state
    // Requires: Error handling in FormState.save() with user-friendly messages
    return error.SkipZigTest;
}

test "1023: save creates backup before modifying config" {
    // Expected: zr.toml.bak created before writing
    // Requires: Backup logic in FormState.save()
    return error.SkipZigTest;
}

test "1024: F1 key shows help for focused field" {
    // Expected: Context-sensitive help popup on F1 press
    // Requires: Keyboard event handler with field-specific help text
    return error.SkipZigTest;
}

test "1025: help shows examples for expression fields" {
    // Expected: Expression fields show syntax examples (env.DEBUG, git.dirty, etc.)
    // Requires: Help system with expression documentation
    return error.SkipZigTest;
}

test "1026: help shows available fields and their types" {
    // Expected: Help includes field reference (name, type, required/optional, default)
    // Requires: Generated documentation from Task struct
    return error.SkipZigTest;
}

test "1027: Tab key navigates between form fields" {
    // Expected: Tab moves focus forward, Shift+Tab backward
    // Requires: Keyboard navigation in Form widget
    return error.SkipZigTest;
}

test "1028: Ctrl+S saves without showing diff preview" {
    // Expected: Ctrl+S quick-saves without confirmation dialog
    // Requires: Keyboard shortcut handler
    return error.SkipZigTest;
}

test "1029: Esc key cancels and returns to CLI" {
    // Expected: Esc shows "Discard changes?" confirmation if form is dirty
    // Requires: Form state tracking and cancel handler
    return error.SkipZigTest;
}

test "1030: Ctrl+P toggles TOML preview pane visibility" {
    // Expected: Ctrl+P shows/hides preview pane
    // Requires: Toggle handler and layout manager
    return error.SkipZigTest;
}

test "1031: form supports array fields for deps" {
    // Expected: Array widget for adding/removing dependencies
    // Requires: ArrayField widget with add/remove buttons
    return error.SkipZigTest;
}

test "1032: form supports key-value fields for env vars" {
    // Expected: Table widget for KEY=VALUE pairs
    // Requires: KeyValueField widget with validation
    return error.SkipZigTest;
}

test "1033: form supports boolean fields as checkboxes" {
    // Expected: Checkboxes for allow_failure, retry_backoff, etc.
    // Requires: Checkbox widget (sailor provides this)
    return error.SkipZigTest;
}

test "1034: form supports numeric fields with validation" {
    // Expected: Numeric inputs reject non-numbers (timeout_ms, retry_max)
    // Requires: NumericField widget with unit conversion support
    return error.SkipZigTest;
}

test "1037: form preserves state on terminal resize" {
    // Expected: Terminal resize doesn't lose form state
    // Requires: Resize event handler in TUI
    return error.SkipZigTest;
}

test "1038: form handles UTF-8 input correctly" {
    // Expected: Form supports Unicode in description, cmd fields
    // Requires: UTF-8 validation in text input widgets
    return error.SkipZigTest;
}

test "1039: workflow builder supports stage configuration" {
    // Expected: Workflow form with stage editor (add/remove/reorder stages)
    // Requires: zr add workflow --interactive with stage list widget
    return error.SkipZigTest;
}

test "1040: workflow builder validates stage task references" {
    // Expected: Stage tasks must reference existing tasks
    // Requires: Validation logic in workflow builder
    return error.SkipZigTest;
}

// ---------------------------------------------------------------------------
// Unit tests for individual components
// (To be added to src/cli/add_interactive.zig once created)
// ---------------------------------------------------------------------------
//
// Future unit tests (not integration tests):
// - FormState.init creates empty form
// - FormState.setField updates field value
// - FormState.validate returns errors for invalid state
// - FormState.toToml generates valid TOML string
// - TemplateEngine.apply substitutes variables
// - FieldValidator.validateTaskName rejects empty strings
// - FieldValidator.validateExpression parses condition syntax
// - DependencyPicker.autocomplete filters by prefix
// - TomlPreview.generate escapes special chars
// - TomlPreview.diff shows additions with + markers
