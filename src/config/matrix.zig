const std = @import("std");
const types = @import("types.zig");

const Config = types.Config;
const MatrixDim = types.MatrixDim;
const addTaskImpl = types.addTaskImpl;

/// Parse a TOML inline table of arrays: { key1 = ["v1", "v2"], key2 = ["a", "b"] }
/// Appends MatrixDim entries (with owned memory) to dims_out.
fn parseMatrixTable(allocator: std.mem.Allocator, raw: []const u8, dims_out: *std.ArrayList(MatrixDim)) !void {
    const inner_full = std.mem.trim(u8, raw, " \t");
    if (!std.mem.startsWith(u8, inner_full, "{") or !std.mem.endsWith(u8, inner_full, "}")) return;
    const inner = inner_full[1 .. inner_full.len - 1];

    var i: usize = 0;
    while (i < inner.len) {
        // Skip whitespace and commas between key=value pairs
        while (i < inner.len and (inner[i] == ' ' or inner[i] == '\t' or inner[i] == ',')) i += 1;
        if (i >= inner.len) break;

        // Read key until '='
        const key_start = i;
        while (i < inner.len and inner[i] != '=') i += 1;
        const key = std.mem.trim(u8, inner[key_start..i], " \t\"");
        if (i >= inner.len or key.len == 0) break;
        i += 1; // skip '='

        // Skip whitespace before '['
        while (i < inner.len and (inner[i] == ' ' or inner[i] == '\t')) i += 1;
        if (i >= inner.len or inner[i] != '[') break;
        i += 1; // skip '['

        // Find matching ']', tracking bracket depth and string quotes
        const arr_start = i;
        var depth: usize = 1;
        var in_str: bool = false;
        while (i < inner.len and depth > 0) {
            const ch = inner[i];
            if (ch == '"' and (i == 0 or inner[i - 1] != '\\')) in_str = !in_str;
            if (!in_str) {
                if (ch == '[') depth += 1 else if (ch == ']') depth -= 1;
            }
            if (depth > 0) i += 1;
        }
        const arr_content = inner[arr_start..i];
        i += 1; // skip ']'

        // Parse comma-separated quoted values inside the array
        var values: std.ArrayListUnmanaged([]const u8) = .{};
        errdefer {
            for (values.items) |v| allocator.free(v);
            values.deinit(allocator);
        }
        var val_it = std.mem.splitScalar(u8, arr_content, ',');
        while (val_it.next()) |item| {
            const trimmed_item = std.mem.trim(u8, item, " \t\"");
            if (trimmed_item.len > 0) {
                try values.append(allocator, try allocator.dupe(u8, trimmed_item));
            }
        }
        if (values.items.len == 0) {
            values.deinit(allocator);
            continue;
        }

        const duped_key = try allocator.dupe(u8, key);
        errdefer allocator.free(duped_key);
        try dims_out.append(allocator, MatrixDim{
            .key = duped_key,
            .values = try values.toOwnedSlice(allocator),
        });
    }
}

/// Replace all occurrences of ${matrix.KEY} in template with the value
/// at dims[i].values[combo[i]] for each dimension i.
fn interpolateMatrixVars(allocator: std.mem.Allocator, template: []const u8, dims: []const MatrixDim, combo: []const usize) ![]const u8 {
    var result = try allocator.dupe(u8, template);
    errdefer allocator.free(result);
    for (dims, 0..) |dim, i| {
        const val = dim.values[combo[i]];
        const placeholder = try std.fmt.allocPrint(allocator, "${{matrix.{s}}}", .{dim.key});
        defer allocator.free(placeholder);
        const new_result = try std.mem.replaceOwned(u8, allocator, result, placeholder, val);
        allocator.free(result);
        result = new_result;
    }
    return result;
}

/// Expand a matrix task into variant tasks and a meta-task.
/// Computes the Cartesian product of all matrix dimensions, creates one variant
/// task per combination (with ${matrix.KEY} substituted), and adds a meta-task
/// with the original name that deps on all variants.
pub fn addMatrixTask(
    config: *Config,
    allocator: std.mem.Allocator,
    name: []const u8,
    cmd: []const u8,
    cwd: ?[]const u8,
    description: ?[]const u8,
    deps: []const []const u8,
    deps_serial: []const []const u8,
    env: []const [2][]const u8,
    timeout_ms: ?u64,
    allow_failure: bool,
    retry_max: u32,
    retry_delay_ms: u64,
    retry_backoff: bool,
    condition: ?[]const u8,
    max_concurrent: u32,
    cache: bool,
    max_cpu: ?u32,
    max_memory: ?u64,
    matrix_raw: []const u8,
) !void {
    // Parse the matrix inline table into dims
    var dims: std.ArrayListUnmanaged(MatrixDim) = .{};
    defer {
        for (dims.items) |*d| d.deinit(allocator);
        dims.deinit(allocator);
    }
    try parseMatrixTable(allocator, matrix_raw, &dims);

    if (dims.items.len == 0) {
        // No matrix dims parsed; fall back to plain task
        return addTaskImpl(config, allocator, name, cmd, cwd, description, deps, deps_serial, env, timeout_ms, allow_failure, retry_max, retry_delay_ms, retry_backoff, condition, max_concurrent, cache, max_cpu, max_memory, &[_][]const u8{});
    }

    // Build sorted key list for deterministic variant name ordering
    // Sort dims by key alphabetically
    const n_dims = dims.items.len;
    // Simple insertion sort (n_dims is typically very small)
    for (1..n_dims) |si| {
        var j = si;
        while (j > 0 and std.mem.lessThan(u8, dims.items[j].key, dims.items[j - 1].key)) : (j -= 1) {
            const tmp = dims.items[j];
            dims.items[j] = dims.items[j - 1];
            dims.items[j - 1] = tmp;
        }
    }

    // Compute total combinations = product of all dim value counts
    var total: usize = 1;
    for (dims.items) |dim| total *= dim.values.len;

    // combo[i] = current index into dims[i].values
    const combo = try allocator.alloc(usize, n_dims);
    defer allocator.free(combo);
    @memset(combo, 0);

    // Collect variant names for the meta-task's deps
    var variant_names: std.ArrayListUnmanaged([]const u8) = .{};
    defer {
        for (variant_names.items) |vn| allocator.free(vn);
        variant_names.deinit(allocator);
    }

    var variant_idx: usize = 0;
    while (variant_idx < total) : (variant_idx += 1) {
        // Build variant name: basename:key1=val1:key2=val2 (keys sorted)
        var vname_buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer vname_buf.deinit(allocator);
        try vname_buf.appendSlice(allocator, name);
        for (dims.items, 0..) |dim, di| {
            try vname_buf.append(allocator, ':');
            try vname_buf.appendSlice(allocator, dim.key);
            try vname_buf.append(allocator, '=');
            try vname_buf.appendSlice(allocator, dim.values[combo[di]]);
        }
        const vname = try vname_buf.toOwnedSlice(allocator);
        errdefer allocator.free(vname);

        // Interpolate cmd, cwd, description, env values
        const v_cmd = try interpolateMatrixVars(allocator, cmd, dims.items, combo);
        errdefer allocator.free(v_cmd);

        const v_cwd: ?[]const u8 = if (cwd) |c| try interpolateMatrixVars(allocator, c, dims.items, combo) else null;
        errdefer if (v_cwd) |c| allocator.free(c);

        const v_desc: ?[]const u8 = if (description) |d| try interpolateMatrixVars(allocator, d, dims.items, combo) else null;
        errdefer if (v_desc) |d| allocator.free(d);

        // Interpolate env values
        var v_env_list: std.ArrayListUnmanaged([2][]const u8) = .{};
        defer {
            for (v_env_list.items) |pair| {
                allocator.free(pair[0]);
                allocator.free(pair[1]);
            }
            v_env_list.deinit(allocator);
        }
        for (env) |pair| {
            const ek = try allocator.dupe(u8, pair[0]);
            errdefer allocator.free(ek);
            const ev = try interpolateMatrixVars(allocator, pair[1], dims.items, combo);
            errdefer allocator.free(ev);
            try v_env_list.append(allocator, .{ ek, ev });
        }

        // Add the variant task (addTaskImpl dupes everything, so our locals can be freed)
        try addTaskImpl(config, allocator, vname, v_cmd, v_cwd, v_desc, deps, deps_serial, v_env_list.items, timeout_ms, allow_failure, retry_max, retry_delay_ms, retry_backoff, condition, max_concurrent, cache, max_cpu, max_memory, &[_][]const u8{});

        // Free our allocations (addTaskImpl duped them)
        allocator.free(v_cmd);
        if (v_cwd) |c| allocator.free(c);
        if (v_desc) |d| allocator.free(d);
        for (v_env_list.items) |pair| {
            allocator.free(pair[0]);
            allocator.free(pair[1]);
        }
        v_env_list.clearRetainingCapacity(); // prevent double-free in defer

        // Track variant name (keep ownership; addTaskImpl duped its own copy)
        try variant_names.append(allocator, vname);
        // vname is now owned by variant_names; remove from errdefer scope by re-assigning
        // (the errdefer on vname fires only if an error occurs before this line)

        // Advance combo (little-endian: last dim increments fastest)
        var di = n_dims;
        while (di > 0) {
            di -= 1;
            combo[di] += 1;
            if (combo[di] < dims.items[di].values.len) break;
            combo[di] = 0;
        }
    }

    // Create meta-task: same name as original, no cmd (use echo), deps = all variants
    const meta_cmd = try std.fmt.allocPrint(allocator, "echo \"Matrix task: {s}\"", .{name});
    defer allocator.free(meta_cmd);

    try addTaskImpl(config, allocator, name, meta_cmd, null, description, variant_names.items, &[_][]const u8{}, &[_][2][]const u8{}, null, false, 0, 0, false, null, 0, false, null, null, &[_][]const u8{});
}

test "matrix: simple expansion single dimension" {
    const allocator = std.testing.allocator;
    const loader = @import("loader.zig");
    const toml_content =
        \\[tasks.test]
        \\cmd = "cargo test --target ${matrix.arch}"
        \\matrix = { arch = ["x86_64", "aarch64"] }
    ;
    var config = try loader.parseToml(allocator, toml_content);
    defer config.deinit();

    // Should have: meta-task "test" + 2 variants
    try std.testing.expectEqual(@as(usize, 3), config.tasks.count());

    // Meta-task exists
    const meta = config.tasks.get("test").?;
    try std.testing.expectEqual(@as(usize, 2), meta.deps.len);

    // Variants exist with correct names
    try std.testing.expect(config.tasks.get("test:arch=x86_64") != null);
    try std.testing.expect(config.tasks.get("test:arch=aarch64") != null);

    // Variant cmd has substituted value
    const v1 = config.tasks.get("test:arch=x86_64").?;
    try std.testing.expectEqualStrings("cargo test --target x86_64", v1.cmd);
    const v2 = config.tasks.get("test:arch=aarch64").?;
    try std.testing.expectEqualStrings("cargo test --target aarch64", v2.cmd);
}

test "matrix: cartesian product 2x2" {
    const allocator = std.testing.allocator;
    const loader = @import("loader.zig");
    const toml_content =
        \\[tasks.test]
        \\cmd = "test ${matrix.arch} ${matrix.os}"
        \\matrix = { arch = ["x86_64", "aarch64"], os = ["linux", "macos"] }
    ;
    var config = try loader.parseToml(allocator, toml_content);
    defer config.deinit();

    // 4 variants + 1 meta-task = 5 total
    try std.testing.expectEqual(@as(usize, 5), config.tasks.count());

    const meta = config.tasks.get("test").?;
    try std.testing.expectEqual(@as(usize, 4), meta.deps.len);

    // All variant combinations must exist
    try std.testing.expect(config.tasks.get("test:arch=x86_64:os=linux") != null);
    try std.testing.expect(config.tasks.get("test:arch=x86_64:os=macos") != null);
    try std.testing.expect(config.tasks.get("test:arch=aarch64:os=linux") != null);
    try std.testing.expect(config.tasks.get("test:arch=aarch64:os=macos") != null);

    // Check cmd substitution
    const v = config.tasks.get("test:arch=x86_64:os=linux").?;
    try std.testing.expectEqualStrings("test x86_64 linux", v.cmd);
}

test "matrix: keys sorted alphabetically in variant name" {
    const allocator = std.testing.allocator;
    const loader = @import("loader.zig");
    // Define dimensions in reverse alphabetical order: os before arch
    const toml_content =
        \\[tasks.build]
        \\cmd = "build"
        \\matrix = { os = ["linux"], arch = ["x86_64"] }
    ;
    var config = try loader.parseToml(allocator, toml_content);
    defer config.deinit();

    // Keys sorted alphabetically: arch < os, so name is build:arch=x86_64:os=linux
    try std.testing.expect(config.tasks.get("build:arch=x86_64:os=linux") != null);
}

test "matrix: meta-task has no-op cmd" {
    const allocator = std.testing.allocator;
    const loader = @import("loader.zig");
    const toml_content =
        \\[tasks.lint]
        \\cmd = "lint ${matrix.target}"
        \\matrix = { target = ["js", "ts"] }
    ;
    var config = try loader.parseToml(allocator, toml_content);
    defer config.deinit();

    const meta = config.tasks.get("lint").?;
    // Meta cmd starts with "echo"
    try std.testing.expect(std.mem.startsWith(u8, meta.cmd, "echo"));
    // Variants have substituted cmds
    const v1 = config.tasks.get("lint:target=js").?;
    try std.testing.expectEqualStrings("lint js", v1.cmd);
}
