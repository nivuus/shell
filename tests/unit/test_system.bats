#!/usr/bin/env bats

# Unit tests for System module (config/13-system.zsh)

setup() {
    # Test the tree this file belongs to, never whatever NIVUUS_SHELL_DIR the
    # environment happens to point at.
    NIVUUS_SHELL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export NIVUUS_SHELL_DIR
    source "$NIVUUS_SHELL_DIR/config/13-system.zsh"
}

# =============================================================================
# Module Loading Tests
# =============================================================================

@test "System module loads without errors" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/13-system.zsh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

# =============================================================================
# System Information Tests
# =============================================================================

@test "zsh_info function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/13-system.zsh' && typeset -f zsh_info"
    [ "$status" -eq 0 ]
}

@test "zsh_info shows version information" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'Version:' config/13-system.zsh"
    [ "$status" -eq 0 ]
}

@test "zsh_info shows NIVUUS_SHELL_DIR" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/13-system.zsh'; zsh_info"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Install dir:    $NIVUUS_SHELL_DIR"* ]]
}

@test "zsh_info shows ZSH_VERSION" {
    local version
    version="$(zsh -c 'print -r -- $ZSH_VERSION')"
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/13-system.zsh'; zsh_info"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ZSH version:    $version"* ]]
}

@test "zsh_info shows feature flags" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'ENABLE_SYNTAX_HIGHLIGHTING' config/13-system.zsh"
    [ "$status" -eq 0 ]
}

@test "zsh_info shows load time" {
    run env NIVUUS_LOAD_TIME=123 zsh -c "source '$NIVUUS_SHELL_DIR/config/13-system.zsh'; zsh_info"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Load time:      123ms"* ]]
}

@test "zsh_info lists config files" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'ls -1' config/13-system.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Health Check Tests
# =============================================================================

@test "healthcheck function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/13-system.zsh' && typeset -f healthcheck"
    [ "$status" -eq 0 ]
}

@test "healthcheck checks for bin/healthcheck" {
    local dir="$BATS_TEST_TMPDIR/install"
    mkdir -p "$dir/bin"
    printf '#!/bin/sh\necho FULL-HEALTHCHECK\n' > "$dir/bin/healthcheck"
    chmod +x "$dir/bin/healthcheck"
    run env NIVUUS_SHELL_DIR="$dir" zsh -c "source '$NIVUUS_SHELL_DIR/config/13-system.zsh'; healthcheck"
    [ "$status" -eq 0 ]
    [ "$output" = "FULL-HEALTHCHECK" ]
}

@test "healthcheck has inline fallback" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 5 'healthcheck()' config/13-system.zsh | grep 'Inline simple health check'"
    [ "$status" -eq 0 ]
}

@test "healthcheck shows disk usage" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 20 'healthcheck()' config/13-system.zsh | grep 'df -h'"
    [ "$status" -eq 0 ]
}

@test "healthcheck shows memory" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 20 'healthcheck()' config/13-system.zsh | grep -E '(free -h|PhysMem)'"
    [ "$status" -eq 0 ]
}

@test "healthcheck shows uptime" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 25 'healthcheck()' config/13-system.zsh | grep 'uptime'"
    [ "$status" -eq 0 ]
}

@test "healthcheck supports macOS" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 20 'healthcheck()' config/13-system.zsh | grep 'darwin'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Benchmark Tests
# =============================================================================

@test "benchmark function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/13-system.zsh' && typeset -f benchmark"
    [ "$status" -eq 0 ]
}

@test "benchmark checks for bin/benchmark" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'bin/benchmark' config/13-system.zsh"
    [ "$status" -eq 0 ]
}

@test "benchmark has inline fallback" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 5 'benchmark()' config/13-system.zsh | grep 'Inline simple benchmark'"
    [ "$status" -eq 0 ]
}

@test "benchmark tests shell reload" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 15 'benchmark()' config/13-system.zsh | grep 'source.*zshrc'"
    [ "$status" -eq 0 ]
}

@test "benchmark uses EPOCHREALTIME" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 15 'benchmark()' config/13-system.zsh | grep 'EPOCHREALTIME'"
    [ "$status" -eq 0 ]
}

@test "benchmark validates 300ms target" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 20 'benchmark()' config/13-system.zsh | grep '300'"
    [ "$status" -eq 0 ]
}

@test "benchmark shows performance ratings" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 25 'benchmark()' config/13-system.zsh | grep -E '(Excellent|Good|Slow)'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Cleanup Tests
# =============================================================================

@test "cleanup function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/13-system.zsh' && typeset -f cleanup"
    [ "$status" -eq 0 ]
}

@test "cleanup removes ZSH cache" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '\.cache/zsh' config/13-system.zsh"
    [ "$status" -eq 0 ]
}

@test "cleanup removes completion dumps" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '\.zcompdump' config/13-system.zsh"
    [ "$status" -eq 0 ]
}

@test "cleanup deduplicates history" {
    local home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$home"
    printf 'ls\ncd /tmp\nls\ngit status\ncd /tmp\n' > "$home/.zsh_history"
    run env HOME="$home" zsh -c "source '$NIVUUS_SHELL_DIR/config/13-system.zsh'; cleanup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"removed 2 entries"* ]]
    [ "$(cat "$home/.zsh_history")" = "$(printf 'ls\ncd /tmp\ngit status')" ]
}

@test "cleanup uses awk to remove duplicates" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 30 'cleanup()' config/13-system.zsh | grep 'awk.*seen'"
    [ "$status" -eq 0 ]
}

@test "cleanup removes Nivuus cache" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'nivuus-shell' config/13-system.zsh | grep cache"
    [ "$status" -eq 0 ]
}

# =============================================================================
# System Update Tests
# =============================================================================

@test "update_system function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/13-system.zsh' && typeset -f update_system"
    [ "$status" -eq 0 ]
}

@test "update_system supports apt-get (Debian/Ubuntu)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'apt-get' config/13-system.zsh"
    [ "$status" -eq 0 ]
}

@test "update_system supports yum (RHEL/CentOS)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'yum' config/13-system.zsh"
    [ "$status" -eq 0 ]
}

@test "update_system supports dnf (Fedora)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'dnf' config/13-system.zsh"
    [ "$status" -eq 0 ]
}

@test "update_system supports brew (macOS)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'brew update' config/13-system.zsh"
    [ "$status" -eq 0 ]
}

@test "update_system supports pacman (Arch)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'pacman' config/13-system.zsh"
    [ "$status" -eq 0 ]
}

@test "update_system checks for package managers" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 30 'update_system()' config/13-system.zsh | grep -c 'command -v'"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 5 ]
}

# =============================================================================
# Configuration Management Tests
# =============================================================================

@test "config_edit function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/13-system.zsh' && typeset -f config_edit"
    [ "$status" -eq 0 ]
}

@test "config_edit uses case statement" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 5 'config_edit()' config/13-system.zsh | grep 'case'"
    [ "$status" -eq 0 ]
}

@test "config_edit supports main config" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 15 'config_edit()' config/13-system.zsh | grep 'main)'"
    [ "$status" -eq 0 ]
}

@test "config_edit supports local config" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 15 'config_edit()' config/13-system.zsh | grep 'local)'"
    [ "$status" -eq 0 ]
}

@test "config_edit supports functions" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 15 'config_edit()' config/13-system.zsh | grep 'functions)'"
    [ "$status" -eq 0 ]
}

@test "config_edit supports aliases" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 15 'config_edit()' config/13-system.zsh | grep 'aliases)'"
    [ "$status" -eq 0 ]
}

@test "config_edit shows usage on invalid type" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 20 'config_edit()' config/13-system.zsh | grep 'Usage:'"
    [ "$status" -eq 0 ]
}

@test "config_backup function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/13-system.zsh' && typeset -f config_backup"
    [ "$status" -eq 0 ]
}

@test "config_backup uses timestamp" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 5 'config_backup()' config/13-system.zsh | grep 'date +%Y%m%d'"
    [ "$status" -eq 0 ]
}

@test "config_backup backs up .zshrc" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 'config_backup()' config/13-system.zsh | grep '\.zshrc'"
    [ "$status" -eq 0 ]
}

@test "config_backup backs up history" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 'config_backup()' config/13-system.zsh | grep '\.zsh_history'"
    [ "$status" -eq 0 ]
}

@test "config_restore function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/13-system.zsh' && typeset -f config_restore"
    [ "$status" -eq 0 ]
}

@test "config_restore lists available backups" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 'config_restore()' config/13-system.zsh | grep 'ls -1t'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Auto-Maintenance Tests
# =============================================================================

@test "_auto_maintenance function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '_auto_maintenance()' config/13-system.zsh"
    [ "$status" -eq 0 ]
}

@test "auto-maintenance checks weekly" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'date +%Y%W' config/13-system.zsh"
    [ "$status" -eq 0 ]
}

@test "auto-maintenance uses cache file" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'last-maintenance' config/13-system.zsh"
    [ "$status" -eq 0 ]
}

@test "auto-maintenance runs cleanup in background" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 '_auto_maintenance()' config/13-system.zsh | grep 'cleanup.*&'"
    [ "$status" -eq 0 ]
}

@test "auto-maintenance runs asynchronously" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -E '_auto_maintenance.*&\)' config/13-system.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Coverage Tests
# =============================================================================

@test "Module defines at least 8 main functions" {
    count=$(zsh -c "source '$NIVUUS_SHELL_DIR/config/13-system.zsh' && typeset -f | grep -c -E '(zsh_info|healthcheck|benchmark|cleanup|update_system|config_edit|config_backup|config_restore)'" || echo "0")
    [ "$count" -ge 8 ]
}

@test "Module has proper error/success indicators" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c -E '(✓|✗|⚠)' config/13-system.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 10 ]
}

@test "Module supports multiple package managers" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c -E '(apt-get|yum|dnf|brew|pacman)' config/13-system.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 5 ]
}

@test "Module supports both macOS and Linux" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'OSTYPE.*darwin' config/13-system.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 1 ]
}

@test "Module has usage messages" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'Usage:' config/13-system.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 1 ]
}
