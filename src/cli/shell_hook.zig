const std = @import("std");
const color = @import("../output/color.zig");

/// Shell type enumeration
pub const ShellType = enum {
    bash,
    zsh,
    fish,
};

/// Parse shell type from string
pub fn parseShellType(shell_str: []const u8) ?ShellType {
    if (std.mem.eql(u8, shell_str, "bash")) {
        return ShellType.bash;
    } else if (std.mem.eql(u8, shell_str, "zsh")) {
        return ShellType.zsh;
    } else if (std.mem.eql(u8, shell_str, "fish")) {
        return ShellType.fish;
    }
    return null;
}

/// Generate bash shell hook code
pub fn generateBashHook(_: std.mem.Allocator, w: anytype) !void {
    const hook_code =
        \\# zr shell hook for bash
        \\# Automatically load environment variables when entering directories with zr.toml
        \\
        \\_zr_load_hook() {
        \\    local current_dir="$PWD"
        \\    local zr_hook_dir="${ZR_HOOK_CACHE_DIR:-.zr_hooks}"
        \\
        \\    # Find zr.toml in current or parent directories
        \\    while [[ "$current_dir" != "/" ]]; do
        \\        if [[ -f "$current_dir/zr.toml" ]]; then
        \\            # Load environment for this directory
        \\            local hook_file="$zr_hook_dir/$(echo -n "$current_dir" | md5sum | cut -d' ' -f1).sh"
        \\            if [[ -f "$hook_file" ]]; then
        \\                source "$hook_file"
        \\            fi
        \\            return
        \\        fi
        \\        current_dir="$(dirname "$current_dir")"
        \\    done
        \\}
        \\
        \\# Install the hook on PROMPT_COMMAND
        \\PROMPT_COMMAND="_zr_load_hook:${PROMPT_COMMAND:-:}"
        \\
    ;
    try w.writeAll(hook_code);
}

/// Generate zsh shell hook code
pub fn generateZshHook(_: std.mem.Allocator, w: anytype) !void {
    const hook_code =
        \\# zr shell hook for zsh
        \\# Automatically load environment variables when entering directories with zr.toml
        \\
        \\_zr_load_hook() {
        \\    local current_dir="$PWD"
        \\    local zr_hook_dir="${ZR_HOOK_CACHE_DIR:-.zr_hooks}"
        \\
        \\    # Find zr.toml in current or parent directories
        \\    while [[ "$current_dir" != "/" ]]; do
        \\        if [[ -f "$current_dir/zr.toml" ]]; then
        \\            # Load environment for this directory
        \\            local hook_file="$zr_hook_dir/$(echo -n "$current_dir" | md5sum | cut -d' ' -f1).sh"
        \\            if [[ -f "$hook_file" ]]; then
        \\                source "$hook_file"
        \\            fi
        \\            return
        \\        fi
        \\        current_dir="$(dirname "$current_dir")"
        \\    done
        \\}
        \\
        \\# Install the hook on chpwd
        \\autoload -Uz add-zsh-hook
        \\add-zsh-hook chpwd _zr_load_hook
        \\
        \\# Run once on shell startup
        \\_zr_load_hook
        \\
    ;
    try w.writeAll(hook_code);
}

/// Generate fish shell hook code
pub fn generateFishHook(_: std.mem.Allocator, w: anytype) !void {
    const hook_code =
        \\# zr shell hook for fish
        \\# Automatically load environment variables when entering directories with zr.toml
        \\
        \\function _zr_load_hook --description "Load zr environment on directory change"
        \\    set -l current_dir $PWD
        \\    set -l zr_hook_dir (set -q ZR_HOOK_CACHE_DIR; and echo $ZR_HOOK_CACHE_DIR; or echo .zr_hooks)
        \\
        \\    # Find zr.toml in current or parent directories
        \\    while test "$current_dir" != "/"
        \\        if test -f "$current_dir/zr.toml"
        \\            # Load environment for this directory
        \\            set -l hook_file "$zr_hook_dir/"(echo -n "$current_dir" | md5sum | cut -d' ' -f1)".sh"
        \\            if test -f "$hook_file"
        \\                source "$hook_file"
        \\            end
        \\            return
        \\        end
        \\        set current_dir (dirname "$current_dir")
        \\    end
        \\end
        \\
        \\# Install the hook on directory change
        \\function fish_postexec --on-variable PWD
        \\    _zr_load_hook
        \\end
        \\
        \\# Run once on shell startup
        \\_zr_load_hook
        \\
    ;
    try w.writeAll(hook_code);
}

/// Handle `zr shell-hook <shell>` command — output shell hook code
pub fn cmdShellHook(
    allocator: std.mem.Allocator,
    shell_name: []const u8,
    w: anytype,
    err_writer: anytype,
    use_color: bool,
) !u8 {
    if (shell_name.len == 0) {
        try color.printError(err_writer, use_color,
            "shell-hook: shell type required\n\n  Usage: zr shell-hook <shell>\n  Supported shells: bash, zsh, fish\n",
            .{});
        return 1;
    }

    const shell_type = parseShellType(shell_name) orelse {
        try color.printError(err_writer, use_color,
            "shell-hook: unknown shell '{s}'\n\n  Supported shells: bash, zsh, fish\n",
            .{shell_name});
        return 1;
    };

    switch (shell_type) {
        .bash => try generateBashHook(allocator, w),
        .zsh => try generateZshHook(allocator, w),
        .fish => try generateFishHook(allocator, w),
    }

    return 0;
}

// ── UNIT TESTS ────────────────────────────────────────────────────────────

test "shell_hook: parseShellType recognizes bash" {
    const shell_type = parseShellType("bash");
    try std.testing.expect(shell_type != null);
    try std.testing.expectEqual(ShellType.bash, shell_type.?);
}

test "shell_hook: parseShellType recognizes zsh" {
    const shell_type = parseShellType("zsh");
    try std.testing.expect(shell_type != null);
    try std.testing.expectEqual(ShellType.zsh, shell_type.?);
}

test "shell_hook: parseShellType recognizes fish" {
    const shell_type = parseShellType("fish");
    try std.testing.expect(shell_type != null);
    try std.testing.expectEqual(ShellType.fish, shell_type.?);
}

test "shell_hook: parseShellType rejects unknown shell" {
    const shell_type = parseShellType("powershell");
    try std.testing.expect(shell_type == null);
}

test "shell_hook: parseShellType rejects empty string" {
    const shell_type = parseShellType("");
    try std.testing.expect(shell_type == null);
}

test "shell_hook: parseShellType is case-sensitive" {
    const shell_type = parseShellType("BASH");
    try std.testing.expect(shell_type == null);
}

test "shell_hook: generateBashHook produces non-empty output" {
    const allocator = std.testing.allocator;
    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try generateBashHook(allocator, output.writer(allocator));
    try std.testing.expect(output.items.len > 0);
}

test "shell_hook: generateBashHook contains bash-specific syntax" {
    const allocator = std.testing.allocator;
    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try generateBashHook(allocator, output.writer(allocator));
    const code = output.items;

    // Check for bash-specific keywords
    try std.testing.expect(std.mem.indexOf(u8, code, "PROMPT_COMMAND") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "_zr_load_hook") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "[[ ") != null or std.mem.indexOf(u8, code, "bash") != null);
}

test "shell_hook: generateZshHook produces non-empty output" {
    const allocator = std.testing.allocator;
    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try generateZshHook(allocator, output.writer(allocator));
    try std.testing.expect(output.items.len > 0);
}

test "shell_hook: generateZshHook contains zsh-specific syntax" {
    const allocator = std.testing.allocator;
    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try generateZshHook(allocator, output.writer(allocator));
    const code = output.items;

    // Check for zsh-specific keywords
    try std.testing.expect(std.mem.indexOf(u8, code, "autoload") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "add-zsh-hook") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "chpwd") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "_zr_load_hook") != null);
}

test "shell_hook: generateFishHook produces non-empty output" {
    const allocator = std.testing.allocator;
    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try generateFishHook(allocator, output.writer(allocator));
    try std.testing.expect(output.items.len > 0);
}

test "shell_hook: generateFishHook contains fish-specific syntax" {
    const allocator = std.testing.allocator;
    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try generateFishHook(allocator, output.writer(allocator));
    const code = output.items;

    // Check for fish-specific keywords
    try std.testing.expect(std.mem.indexOf(u8, code, "function") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "fish_postexec") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "_zr_load_hook") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "set -l") != null or std.mem.indexOf(u8, code, "set -q") != null);
}

test "shell_hook: all shells reference ZR_HOOK_CACHE_DIR environment variable" {
    const allocator = std.testing.allocator;

    var bash_output = std.ArrayList(u8){};
    defer bash_output.deinit(allocator);
    try generateBashHook(allocator, bash_output.writer(allocator));
    try std.testing.expect(std.mem.indexOf(u8, bash_output.items, "ZR_HOOK_CACHE_DIR") != null);

    var zsh_output = std.ArrayList(u8){};
    defer zsh_output.deinit(allocator);
    try generateZshHook(allocator, zsh_output.writer(allocator));
    try std.testing.expect(std.mem.indexOf(u8, zsh_output.items, "ZR_HOOK_CACHE_DIR") != null);

    var fish_output = std.ArrayList(u8){};
    defer fish_output.deinit(allocator);
    try generateFishHook(allocator, fish_output.writer(allocator));
    try std.testing.expect(std.mem.indexOf(u8, fish_output.items, "ZR_HOOK_CACHE_DIR") != null);
}

test "shell_hook: all shells look for zr.toml" {
    const allocator = std.testing.allocator;

    var bash_output = std.ArrayList(u8){};
    defer bash_output.deinit(allocator);
    try generateBashHook(allocator, bash_output.writer(allocator));
    try std.testing.expect(std.mem.indexOf(u8, bash_output.items, "zr.toml") != null);

    var zsh_output = std.ArrayList(u8){};
    defer zsh_output.deinit(allocator);
    try generateZshHook(allocator, zsh_output.writer(allocator));
    try std.testing.expect(std.mem.indexOf(u8, zsh_output.items, "zr.toml") != null);

    var fish_output = std.ArrayList(u8){};
    defer fish_output.deinit(allocator);
    try generateFishHook(allocator, fish_output.writer(allocator));
    try std.testing.expect(std.mem.indexOf(u8, fish_output.items, "zr.toml") != null);
}

test "shell_hook: bash hook traverses parent directories" {
    const allocator = std.testing.allocator;
    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try generateBashHook(allocator, output.writer(allocator));
    const code = output.items;

    // Check for loop that traverses directories
    try std.testing.expect(std.mem.indexOf(u8, code, "while") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "dirname") != null or std.mem.indexOf(u8, code, "$(dirname") != null);
}

test "shell_hook: zsh hook traverses parent directories" {
    const allocator = std.testing.allocator;
    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try generateZshHook(allocator, output.writer(allocator));
    const code = output.items;

    // Check for loop that traverses directories
    try std.testing.expect(std.mem.indexOf(u8, code, "while") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "dirname") != null or std.mem.indexOf(u8, code, "$(dirname") != null);
}

test "shell_hook: fish hook traverses parent directories" {
    const allocator = std.testing.allocator;
    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try generateFishHook(allocator, output.writer(allocator));
    const code = output.items;

    // Check for loop that traverses directories
    try std.testing.expect(std.mem.indexOf(u8, code, "while") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "dirname") != null);
}

test "shell_hook: bash hook installs via PROMPT_COMMAND" {
    const allocator = std.testing.allocator;
    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try generateBashHook(allocator, output.writer(allocator));
    const code = output.items;

    // Verify bash installs the hook using PROMPT_COMMAND mechanism
    try std.testing.expect(std.mem.indexOf(u8, code, "PROMPT_COMMAND") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "_zr_load_hook") != null);
}

test "shell_hook: zsh hook uses add-zsh-hook" {
    const allocator = std.testing.allocator;
    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try generateZshHook(allocator, output.writer(allocator));
    const code = output.items;

    // Verify zsh uses add-zsh-hook for chpwd
    try std.testing.expect(std.mem.indexOf(u8, code, "add-zsh-hook") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "chpwd") != null);
}

test "shell_hook: fish hook uses fish_postexec" {
    const allocator = std.testing.allocator;
    var output = std.ArrayList(u8){};
    defer output.deinit(allocator);

    try generateFishHook(allocator, output.writer(allocator));
    const code = output.items;

    // Verify fish uses fish_postexec for PWD changes
    try std.testing.expect(std.mem.indexOf(u8, code, "fish_postexec") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "PWD") != null);
}
