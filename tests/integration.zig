const std = @import("std");

comptime {
    _ = @import("helpers.zig");
    _ = @import("affected_test.zig");
    _ = @import("alias_test.zig");
    _ = @import("analytics_test.zig");
    _ = @import("bench_test.zig");
    _ = @import("cache_test.zig");
    _ = @import("conformance_test.zig");
    _ = @import("context_test.zig");
    _ = @import("env_test.zig");
    _ = @import("estimate_test.zig");
    _ = @import("export_test.zig");
    _ = @import("graph_test.zig");
    _ = @import("history_test.zig");
    _ = @import("init_test.zig");
    _ = @import("list_test.zig");
    _ = @import("misc_test.zig");
    _ = @import("plugin_test.zig");
    _ = @import("repo_test.zig");
    _ = @import("run_test.zig");
    _ = @import("schedule_test.zig");
    _ = @import("show_test.zig");
    _ = @import("tools_test.zig");
    _ = @import("validate_test.zig");
    _ = @import("workflow_test.zig");
    _ = @import("workspace_test.zig");
}
