const std = @import("std");
const color = @import("../output/color.zig");

pub const BASH_COMPLETION =
    \\_zr_completion() {
    \\    local cur="${COMP_WORDS[COMP_CWORD]}"
    \\    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    \\    local commands="run watch workflow list graph history workspace init completion"
    \\    local options="--help --profile --dry-run --jobs --no-color --quiet --verbose --config --format -h -p -n -j -q -v -f"
    \\
    \\    case "$prev" in
    \\        run|watch)
    \\            # Complete task names from zr.toml
    \\            local tasks
    \\            tasks=$(zr list 2>/dev/null | awk 'NR>1 && /^  / {print $1}')
    \\            COMPREPLY=($(compgen -W "$tasks" -- "$cur"))
    \\            return ;;
    \\        workflow)
    \\            # Complete workflow names from zr list
    \\            local workflows
    \\            workflows=$(zr list 2>/dev/null | awk '/^Workflows:/,0 {if (/^  /) print $1}')
    \\            COMPREPLY=($(compgen -W "$workflows" -- "$cur"))
    \\            return ;;
    \\        workspace)
    \\            COMPREPLY=($(compgen -W "list run" -- "$cur"))
    \\            return ;;
    \\        completion)
    \\            COMPREPLY=($(compgen -W "bash zsh fish" -- "$cur"))
    \\            return ;;
    \\        --profile|-p)
    \\            return ;;
    \\        --jobs|-j)
    \\            return ;;
    \\        --config)
    \\            COMPREPLY=($(compgen -f -- "$cur"))
    \\            return ;;
    \\        --format|-f)
    \\            COMPREPLY=($(compgen -W "text json" -- "$cur"))
    \\            return ;;
    \\    esac
    \\
    \\    if [[ "$cur" == -* ]]; then
    \\        COMPREPLY=($(compgen -W "$options" -- "$cur"))
    \\    else
    \\        COMPREPLY=($(compgen -W "$commands" -- "$cur"))
    \\    fi
    \\}
    \\
    \\complete -F _zr_completion zr
    \\
;

pub const ZSH_COMPLETION =
    \\#compdef zr
    \\
    \\_zr() {
    \\    local state
    \\    local -a commands options
    \\    commands=(
    \\        'run:Run a task and its dependencies'
    \\        'watch:Watch files and auto-run task on changes'
    \\        'workflow:Run a workflow by name'
    \\        'list:List all available tasks'
    \\        'graph:Show dependency tree'
    \\        'history:Show recent run history'
    \\        'init:Scaffold a new zr.toml'
    \\        'completion:Print shell completion script'
    \\        'workspace:Manage workspace members (list|run)'
    \\    )
    \\    options=(
    \\        '--help[Show help]'
    \\        '-h[Show help]'
    \\        '--profile[Activate named profile]:profile name'
    \\        '-p[Activate named profile]:profile name'
    \\        '--dry-run[Show plan without executing]'
    \\        '-n[Show plan without executing]'
    \\        '--jobs[Max parallel tasks]:count'
    \\        '-j[Max parallel tasks]:count'
    \\        '--no-color[Disable color output]'
    \\        '--quiet[Suppress non-error output]'
    \\        '-q[Suppress non-error output]'
    \\        '--verbose[Verbose output]'
    \\        '-v[Verbose output]'
    \\        '--config[Config file path]:file:_files'
    \\        '--format[Output format]:format:(text json)'
    \\        '-f[Output format]:format:(text json)'
    \\    )
    \\    _arguments -C \
    \\        $options \
    \\        '1: :->command' \
    \\        '*: :->args' && return
    \\    case $state in
    \\        command)
    \\            _describe 'command' commands ;;
    \\        args)
    \\            case $words[2] in
    \\                run|watch)
    \\                    local -a tasks
    \\                    tasks=(${(f)"$(zr list 2>/dev/null | awk 'NR>1 && /^  / {print $1}')"})
    \\                    _describe 'task' tasks ;;
    \\                workflow)
    \\                    local -a workflows
    \\                    workflows=(${(f)"$(zr list 2>/dev/null | awk '/^Workflows:/,0 {if (/^  /) print $1}')"})
    \\                    _describe 'workflow' workflows ;;
    \\                completion)
    \\                    _values 'shell' bash zsh fish ;;
    \\                workspace)
    \\                    _values 'subcommand' list run ;;
    \\            esac ;;
    \\    esac
    \\}
    \\
    \\_zr "$@"
    \\
;

pub const FISH_COMPLETION =
    \\# Fish completion for zr
    \\
    \\function __zr_tasks
    \\    zr list 2>/dev/null | awk 'NR>1 && /^  / {print $1}'
    \\end
    \\
    \\function __zr_workflows
    \\    zr list 2>/dev/null | awk '/^Workflows:/,0 {if (/^  /) print $1}'
    \\end
    \\
    \\# Subcommands
    \\complete -c zr -f -n '__fish_use_subcommand' -a run        -d 'Run a task'
    \\complete -c zr -f -n '__fish_use_subcommand' -a watch      -d 'Watch and auto-run task'
    \\complete -c zr -f -n '__fish_use_subcommand' -a workflow   -d 'Run a workflow'
    \\complete -c zr -f -n '__fish_use_subcommand' -a list       -d 'List tasks'
    \\complete -c zr -f -n '__fish_use_subcommand' -a graph      -d 'Show dependency tree'
    \\complete -c zr -f -n '__fish_use_subcommand' -a history    -d 'Show run history'
    \\complete -c zr -f -n '__fish_use_subcommand' -a init       -d 'Scaffold zr.toml'
    \\complete -c zr -f -n '__fish_use_subcommand' -a completion -d 'Print completion script'
    \\complete -c zr -f -n '__fish_use_subcommand' -a workspace  -d 'Workspace commands (list|run)'
    \\complete -c zr -f -n '__fish_seen_subcommand_from workspace' -a 'list run'
    \\
    \\# Task name completions for run/watch
    \\complete -c zr -f -n '__fish_seen_subcommand_from run watch' -a '(__zr_tasks)'
    \\
    \\# Workflow name completions for workflow
    \\complete -c zr -f -n '__fish_seen_subcommand_from workflow' -a '(__zr_workflows)'
    \\
    \\# Shell completions for completion
    \\complete -c zr -f -n '__fish_seen_subcommand_from completion' -a 'bash zsh fish'
    \\
    \\# Global options
    \\complete -c zr -l help       -s h -d 'Show help'
    \\complete -c zr -l profile    -s p -d 'Activate named profile' -r
    \\complete -c zr -l dry-run    -s n -d 'Show plan without executing'
    \\complete -c zr -l jobs       -s j -d 'Max parallel tasks' -r
    \\complete -c zr -l no-color         -d 'Disable color output'
    \\complete -c zr -l quiet      -s q -d 'Suppress non-error output'
    \\complete -c zr -l verbose    -s v -d 'Verbose output'
    \\complete -c zr -l config           -d 'Config file path' -r -F
    \\complete -c zr -l format    -s f -d 'Output format' -r -a 'text json'
    \\
;

pub fn cmdCompletion(
    shell: []const u8,
    w: *std.Io.Writer,
    err_writer: *std.Io.Writer,
    use_color: bool,
) !u8 {
    if (std.mem.eql(u8, shell, "bash")) {
        try w.writeAll(BASH_COMPLETION);
        return 0;
    } else if (std.mem.eql(u8, shell, "zsh")) {
        try w.writeAll(ZSH_COMPLETION);
        return 0;
    } else if (std.mem.eql(u8, shell, "fish")) {
        try w.writeAll(FISH_COMPLETION);
        return 0;
    } else if (shell.len == 0) {
        try color.printError(err_writer, use_color,
            "completion: missing shell name\n\n  Hint: zr completion <bash|zsh|fish>\n", .{});
        return 1;
    } else {
        try color.printError(err_writer, use_color,
            "completion: unknown shell '{s}'\n\n  Hint: supported shells: bash, zsh, fish\n",
            .{shell});
        return 1;
    }
}

test "completion scripts are non-empty and contain key markers" {
    try std.testing.expect(BASH_COMPLETION.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "_zr_completion") != null);
    try std.testing.expect(ZSH_COMPLETION.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "#compdef zr") != null);
    try std.testing.expect(FISH_COMPLETION.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "complete -c zr") != null);
}

test "completion scripts include new global flags" {
    // BASH should list the new flags in the options variable.
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "--jobs") != null);
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "--no-color") != null);
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "--quiet") != null);
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "--verbose") != null);
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "--config") != null);
    // ZSH should describe each new flag.
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "--jobs") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "--no-color") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "--quiet") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "--verbose") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "--config") != null);
    // Fish should have complete entries for each new flag.
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "jobs") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "no-color") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "quiet") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "verbose") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "config") != null);
}

test "completion scripts include --format flag" {
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "--format") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "--format") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "format") != null);
}

test "completion scripts include workspace command" {
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "workspace") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "workspace") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "workspace") != null);
}
