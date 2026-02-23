const std = @import("std");
const color = @import("../output/color.zig");

pub const BASH_COMPLETION =
    \\_zr_completion() {
    \\    local cur="${COMP_WORDS[COMP_CWORD]}"
    \\    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    \\    local commands="run watch workflow list graph history workspace affected cache clean plugin interactive live interactive-run irun init setup validate lint conformance completion tools repo codeowners version publish analytics context bench doctor env export upgrade"
    \\    local options="--help --version --profile --dry-run --jobs --no-color --quiet --verbose --config --format --monitor --affected -h -p -n -j -q -v -f -m"
    \\
    \\    case "$prev" in
    \\        run|watch|live|affected|bench|interactive-run|irun)
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
    \\            COMPREPLY=($(compgen -W "list run sync" -- "$cur"))
    \\            return ;;
    \\        plugin)
    \\            COMPREPLY=($(compgen -W "list search install remove update info builtins create" -- "$cur"))
    \\            return ;;
    \\        tools)
    \\            COMPREPLY=($(compgen -W "list install outdated" -- "$cur"))
    \\            return ;;
    \\        repo)
    \\            COMPREPLY=($(compgen -W "sync status graph run" -- "$cur"))
    \\            return ;;
    \\        cache)
    \\            COMPREPLY=($(compgen -W "clear status" -- "$cur"))
    \\            return ;;
    \\        codeowners)
    \\            COMPREPLY=($(compgen -W "generate" -- "$cur"))
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
    \\        'graph:Visualize workspace dependency graph'
    \\        'history:Show recent run history'
    \\        'workspace:Manage workspace members (list|run|sync)'
    \\        'affected:Run task on affected workspace members'
    \\        'cache:Manage task cache (clear|status)'
    \\        'clean:Clean zr data (cache, history, toolchains, plugins)'
    \\        'plugin:Manage plugins (list|search|install|remove|update|info|builtins|create)'
    \\        'interactive:Launch interactive TUI task picker'
    \\        'live:Run task with live TUI log streaming'
    \\        'interactive-run:Run task with cancel/retry controls'
    \\        'irun:Alias for interactive-run'
    \\        'init:Scaffold a new zr.toml'
    \\        'setup:Set up project (install tools, run setup tasks)'
    \\        'validate:Validate zr.toml configuration file'
    \\        'lint:Validate architecture constraints'
    \\        'conformance:Check code conformance against rules'
    \\        'completion:Print shell completion script'
    \\        'tools:Manage toolchains (list|install|outdated)'
    \\        'repo:Multi-repo orchestration (sync|status|graph|run)'
    \\        'codeowners:Generate CODEOWNERS file from workspace'
    \\        'version:Show or bump package version'
    \\        'publish:Publish a new version'
    \\        'analytics:Generate build analysis reports'
    \\        'context:Generate AI-friendly project metadata'
    \\        'bench:Benchmark task performance'
    \\        'doctor:Diagnose environment and toolchain setup'
    \\        'env:Display environment variables for tasks'
    \\        'export:Export env vars in shell-sourceable format'
    \\        'upgrade:Upgrade zr to the latest version'
    \\    )
    \\    options=(
    \\        '--help[Show help]'
    \\        '-h[Show help]'
    \\        '--version[Show version information]'
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
    \\        '--monitor[Display live resource usage]'
    \\        '-m[Display live resource usage]'
    \\        '--affected[Run only affected workspace members]:ref'
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
    \\                run|watch|live|affected|bench|interactive-run|irun)
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
    \\                    _values 'subcommand' list run sync ;;
    \\                plugin)
    \\                    _values 'subcommand' list search install remove update info builtins create ;;
    \\                tools)
    \\                    _values 'subcommand' list install outdated ;;
    \\                repo)
    \\                    _values 'subcommand' sync status graph run ;;
    \\                cache)
    \\                    _values 'subcommand' clear status ;;
    \\                codeowners)
    \\                    _values 'subcommand' generate ;;
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
    \\complete -c zr -f -n '__fish_use_subcommand' -a run        -d 'Run a task and its dependencies'
    \\complete -c zr -f -n '__fish_use_subcommand' -a watch      -d 'Watch files and auto-run task'
    \\complete -c zr -f -n '__fish_use_subcommand' -a workflow   -d 'Run a workflow by name'
    \\complete -c zr -f -n '__fish_use_subcommand' -a list       -d 'List all available tasks'
    \\complete -c zr -f -n '__fish_use_subcommand' -a graph      -d 'Visualize workspace dependency graph'
    \\complete -c zr -f -n '__fish_use_subcommand' -a history    -d 'Show recent run history'
    \\complete -c zr -f -n '__fish_use_subcommand' -a workspace  -d 'Manage workspace members'
    \\complete -c zr -f -n '__fish_use_subcommand' -a affected   -d 'Run task on affected members'
    \\complete -c zr -f -n '__fish_use_subcommand' -a cache      -d 'Manage task cache'
    \\complete -c zr -f -n '__fish_use_subcommand' -a clean      -d 'Clean zr data'
    \\complete -c zr -f -n '__fish_use_subcommand' -a plugin     -d 'Manage plugins'
    \\complete -c zr -f -n '__fish_use_subcommand' -a interactive -d 'Interactive TUI task picker'
    \\complete -c zr -f -n '__fish_use_subcommand' -a i          -d 'Alias for interactive'
    \\complete -c zr -f -n '__fish_use_subcommand' -a live       -d 'Run task with live log streaming'
    \\complete -c zr -f -n '__fish_use_subcommand' -a interactive-run -d 'Run with cancel/retry controls'
    \\complete -c zr -f -n '__fish_use_subcommand' -a irun       -d 'Alias for interactive-run'
    \\complete -c zr -f -n '__fish_use_subcommand' -a init       -d 'Scaffold a new zr.toml'
    \\complete -c zr -f -n '__fish_use_subcommand' -a setup      -d 'Set up project environment'
    \\complete -c zr -f -n '__fish_use_subcommand' -a validate   -d 'Validate zr.toml'
    \\complete -c zr -f -n '__fish_use_subcommand' -a lint       -d 'Validate architecture constraints'
    \\complete -c zr -f -n '__fish_use_subcommand' -a conformance -d 'Check code conformance'
    \\complete -c zr -f -n '__fish_use_subcommand' -a completion -d 'Print shell completion script'
    \\complete -c zr -f -n '__fish_use_subcommand' -a tools      -d 'Manage toolchains'
    \\complete -c zr -f -n '__fish_use_subcommand' -a repo       -d 'Multi-repo orchestration'
    \\complete -c zr -f -n '__fish_use_subcommand' -a codeowners -d 'Generate CODEOWNERS file'
    \\complete -c zr -f -n '__fish_use_subcommand' -a version    -d 'Show or bump version'
    \\complete -c zr -f -n '__fish_use_subcommand' -a publish    -d 'Publish a new version'
    \\complete -c zr -f -n '__fish_use_subcommand' -a analytics  -d 'Generate build analysis'
    \\complete -c zr -f -n '__fish_use_subcommand' -a context    -d 'Generate AI-friendly metadata'
    \\complete -c zr -f -n '__fish_use_subcommand' -a bench      -d 'Benchmark task performance'
    \\complete -c zr -f -n '__fish_use_subcommand' -a doctor     -d 'Diagnose environment setup'
    \\complete -c zr -f -n '__fish_use_subcommand' -a env        -d 'Display environment variables'
    \\complete -c zr -f -n '__fish_use_subcommand' -a export     -d 'Export env in shell format'
    \\complete -c zr -f -n '__fish_use_subcommand' -a upgrade    -d 'Upgrade zr to latest version'
    \\
    \\# Subcommand arguments
    \\complete -c zr -f -n '__fish_seen_subcommand_from workspace' -a 'list run sync'
    \\complete -c zr -f -n '__fish_seen_subcommand_from plugin' -a 'list search install remove update info builtins create'
    \\complete -c zr -f -n '__fish_seen_subcommand_from tools' -a 'list install outdated'
    \\complete -c zr -f -n '__fish_seen_subcommand_from repo' -a 'sync status graph run'
    \\complete -c zr -f -n '__fish_seen_subcommand_from cache' -a 'clear status'
    \\complete -c zr -f -n '__fish_seen_subcommand_from codeowners' -a 'generate'
    \\
    \\# Task name completions for run/watch/live/affected/bench/interactive-run/irun
    \\complete -c zr -f -n '__fish_seen_subcommand_from run watch live affected bench interactive-run irun' -a '(__zr_tasks)'
    \\
    \\# Workflow name completions for workflow
    \\complete -c zr -f -n '__fish_seen_subcommand_from workflow' -a '(__zr_workflows)'
    \\
    \\# Shell completions for completion
    \\complete -c zr -f -n '__fish_seen_subcommand_from completion' -a 'bash zsh fish'
    \\
    \\# Global options
    \\complete -c zr -l help       -s h -d 'Show help'
    \\complete -c zr -l version          -d 'Show version information'
    \\complete -c zr -l profile    -s p -d 'Activate named profile' -r
    \\complete -c zr -l dry-run    -s n -d 'Show plan without executing'
    \\complete -c zr -l jobs       -s j -d 'Max parallel tasks' -r
    \\complete -c zr -l no-color         -d 'Disable color output'
    \\complete -c zr -l quiet      -s q -d 'Suppress non-error output'
    \\complete -c zr -l verbose    -s v -d 'Verbose output'
    \\complete -c zr -l config           -d 'Config file path' -r -F
    \\complete -c zr -l format     -s f -d 'Output format' -r -a 'text json'
    \\complete -c zr -l monitor    -s m -d 'Display live resource usage'
    \\complete -c zr -l affected         -d 'Run only affected members' -r
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

test "completion scripts include new Phase 5-8 commands" {
    // Phase 5: toolchains
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "tools") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "tools") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "tools") != null);

    // Phase 6: monorepo intelligence
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "affected") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "affected") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "affected") != null);

    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "lint") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "lint") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "lint") != null);

    // Phase 7: multi-repo
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "repo") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "repo") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "repo") != null);

    // Phase 8: enterprise
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "codeowners") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "codeowners") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "codeowners") != null);

    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "analytics") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "analytics") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "analytics") != null);

    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "conformance") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "conformance") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "conformance") != null);

    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "bench") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "bench") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "bench") != null);

    // Utility commands
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "doctor") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "doctor") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "doctor") != null);

    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "clean") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "clean") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "clean") != null);
}

test "completion scripts include --monitor and --affected flags" {
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "--monitor") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "--monitor") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "monitor") != null);

    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "--affected") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "--affected") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "affected") != null);
}

test "completion scripts include --version flag" {
    try std.testing.expect(std.mem.indexOf(u8, BASH_COMPLETION, "--version") != null);
    try std.testing.expect(std.mem.indexOf(u8, ZSH_COMPLETION, "--version") != null);
    try std.testing.expect(std.mem.indexOf(u8, FISH_COMPLETION, "version") != null);
}
