#!/usr/bin/env bats

# Unit tests for general aliases module (config/15-aliases.zsh)

bats_require_minimum_version 1.5.0

load "${BATS_TEST_DIRNAME}/../helpers/pty"

setup() {
    # Test the tree this file belongs to, never whatever NIVUUS_SHELL_DIR the
    # environment happens to point at.
    NIVUUS_SHELL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export NIVUUS_SHELL_DIR
}

# =============================================================================
# Module Loading Tests
# =============================================================================

# Loaded the way .zshrc loads it (after 00-core, which defines
# nivuus_has_terminal): no error at all, not merely a zero exit status.
@test "Aliases module loads without errors" {
    run --separate-stderr zsh -c "source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh'"
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
}

# =============================================================================
# Navigation Aliases
# =============================================================================

@test "'-' alias is defined (cd -)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias -- -"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cd -"* ]]
}

# Note: '~' cannot be aliased as it's a reserved zsh token
# This test has been removed as the alias is not possible

# =============================================================================
# Safety Aliases
# =============================================================================

@test "rm alias includes -i flag when a terminal is attached" {
    pty_run "source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias rm"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-i"* ]]
}

@test "cp alias includes -i flag when a terminal is attached" {
    pty_run "source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias cp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-i"* ]]
}

@test "mv alias includes -i flag when a terminal is attached" {
    pty_run "source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias mv"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-i"* ]]
}

@test "ln alias includes -i flag when a terminal is attached" {
    pty_run "source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias ln"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-i"* ]]
}

@test "confirmation aliases are absent in a non-interactive shell" {
    for cmd in rm cp mv ln; do
        run zsh -c "source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias $cmd"
        [ "$status" -ne 0 ]
    done
}

# =============================================================================
# Shortcut Aliases
# =============================================================================

@test "c alias is defined (clear)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias c"
    [ "$status" -eq 0 ]
    [[ "$output" == *"clear"* ]]
}

@test "cls alias is defined (clear)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias cls"
    [ "$status" -eq 0 ]
    [[ "$output" == *"clear"* ]]
}

@test "reload alias is defined (source ~/.zshrc)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias reload"
    [ "$status" -eq 0 ]
    [[ "$output" == *"source"* ]]
    [[ "$output" == *".zshrc"* ]]
}

@test "zshconfig alias is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias zshconfig"
    [ "$status" -eq 0 ]
    [[ "$output" == *"EDITOR"* ]] || [[ "$output" == *".zshrc"* ]]
}

@test "h alias is defined (history)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias h"
    [ "$status" -eq 0 ]
    [[ "$output" == *"history"* ]]
}

@test "hg alias is defined (history | grep)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias hg"
    [ "$status" -eq 0 ]
    [[ "$output" == *"history"* ]]
    [[ "$output" == *"grep"* ]]
}

@test "j alias is defined (jobs -l)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias j"
    [ "$status" -eq 0 ]
    [[ "$output" == *"jobs"* ]]
}

# =============================================================================
# System Aliases
# =============================================================================

@test "please alias is defined (sudo)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias please"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sudo"* ]]
}

@test "pls alias is defined (sudo)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias pls"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sudo"* ]]
}

@test "psa alias is defined (ps aux)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias psa"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ps aux"* ]]
}

@test "top is not aliased (procps top has no -o cpu)" {
    pty_run "source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh'; whence -w top"
    [[ "$output" != *"top: alias"* ]]
}

@test "at a terminal, df alias includes -h flag (human readable)" {
    pty_run "source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh'; alias df"
    [ "$status" -eq 0 ]
    [[ "$output" == *"df -h"* ]]
}

@test "at a terminal, du alias includes -h flag (human readable)" {
    pty_run "source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh'; alias du"
    [ "$status" -eq 0 ]
    [[ "$output" == *"du -h"* ]]
}

# =============================================================================
# Network Aliases
# =============================================================================

@test "listening is defined as a function (ports)" {
    # A function rather than an alias, so that `listening | grep 443` pipes the
    # whole fallback chain and not only its last branch.
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && typeset -f listening"
    [ "$status" -eq 0 ]
    [[ "$output" == *"lsof"* ]] && [[ "$output" == *"ss"* ]] && [[ "$output" == *"netstat"* ]]
}

# =============================================================================
# Date/Time Aliases
# =============================================================================

@test "now alias is defined (formatted date)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias now"
    [ "$status" -eq 0 ]
    [[ "$output" == *"date"* ]]
}

@test "timestamp alias is defined (unix timestamp)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias timestamp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"date"* ]]
}

@test "isodate alias is defined (ISO 8601)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' && alias isodate"
    [ "$status" -eq 0 ]
    [[ "$output" == *"date"* ]]
}

# =============================================================================
# Coverage Tests
# =============================================================================

@test "Safety aliases are enabled by default" {
    # Check that rm, cp, mv, ln have -i flag
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -E \"alias (rm|cp|mv|ln)='\" config/15-aliases.zsh | grep -c -- '-i'"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 4 ]
}

@test "All date/time aliases use 'date' command" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -E \"alias (now|timestamp|isodate)=\" config/15-aliases.zsh | grep -c 'date'"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 3 ]
}

@test "Sudo shortcuts are available (please, pls)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -E \"alias (please|pls)=\" config/15-aliases.zsh | grep -c 'sudo'"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 2 ]
}
