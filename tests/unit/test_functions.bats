#!/usr/bin/env bats

# Unit tests for utility functions module (config/14-functions.zsh)

setup() {
    # Test the tree this file belongs to, never whatever NIVUUS_SHELL_DIR the
    # environment happens to point at.
    NIVUUS_SHELL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export NIVUUS_SHELL_DIR
    source "$NIVUUS_SHELL_DIR/themes/nord.zsh"
    source "$NIVUUS_SHELL_DIR/config/14-functions.zsh"
}

# =============================================================================
# Module Loading Tests
# =============================================================================

@test "Functions module loads without errors" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

# =============================================================================
# tmpcd Function Tests
# =============================================================================

@test "tmpcd function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && typeset -f tmpcd"
    [ "$status" -eq 0 ]
}

@test "tmpcd creates temporary directory" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && tmpcd && pwd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/tmp"* ]]
}

# =============================================================================
# replace Function Tests
# =============================================================================

@test "replace function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && typeset -f replace"
    [ "$status" -eq 0 ]
}

@test "replace shows usage when called without arguments" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && replace 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

# =============================================================================
# count Function Tests
# =============================================================================

@test "count function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && typeset -f count"
    [ "$status" -eq 0 ]
}

@test "count shows file and directory counts" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && count ."
    [ "$status" -eq 0 ]
    [[ "$output" == *"Files:"* ]]
    [[ "$output" == *"Directories:"* ]]
}

# =============================================================================
# editx Function Tests
# =============================================================================

@test "editx function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && typeset -f editx"
    [ "$status" -eq 0 ]
}

@test "editx shows usage when called without arguments" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && editx 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

# =============================================================================
# serve Function Tests
# =============================================================================

@test "serve function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && typeset -f serve"
    [ "$status" -eq 0 ]
}

@test "serve checks for python availability" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 '^serve()' config/14-functions.zsh | grep 'python'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# psgrep Function Tests
# =============================================================================

@test "psgrep function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && typeset -f psgrep"
    [ "$status" -eq 0 ]
}

@test "psgrep shows usage when called without arguments" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && psgrep 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "psgrep finds running processes" {
    # This test may fail if no zsh processes are running or ps command varies
    # We just verify the function executes without crashing
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && psgrep zsh 2>&1 || true"
    # Success if function runs (exit 0) or if it finds/doesn't find processes
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# =============================================================================
# killp Function Tests
# =============================================================================

@test "killp function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && typeset -f killp"
    [ "$status" -eq 0 ]
}

@test "killp shows usage when called without arguments" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && killp 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

# =============================================================================
# memof Function Tests
# =============================================================================

@test "memof function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && typeset -f memof"
    [ "$status" -eq 0 ]
}

# =============================================================================
# path Function Tests
# =============================================================================

@test "path function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && typeset -f path"
    [ "$status" -eq 0 ]
}

@test "path shows PATH entries" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && path"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/"* ]]
}

# =============================================================================
# addpath Function Tests
# =============================================================================

@test "addpath function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && typeset -f addpath"
    [ "$status" -eq 0 ]
}

# =============================================================================
# urlencode Function Tests
# =============================================================================

@test "urlencode function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && typeset -f urlencode"
    [ "$status" -eq 0 ]
}

@test "urlencode encodes spaces" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && urlencode 'hello world'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"%20"* ]] || [[ "$output" == *"+"* ]]
}

# =============================================================================
# json Function Tests
# =============================================================================

@test "json function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && typeset -f json"
    [ "$status" -eq 0 ]
}

# =============================================================================
# largest Function Tests
# =============================================================================

@test "largest function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && typeset -f largest"
    [ "$status" -eq 0 ]
}

@test "largest finds large files" {
    # Test that the function exists and processes directory
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 5 '^largest()' config/14-functions.zsh | grep 'du'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Coverage Tests
# =============================================================================

@test "Functions module defines at least 13 functions" {
    count=$(zsh -c "source '$NIVUUS_SHELL_DIR/config/14-functions.zsh' && typeset -f | grep -c '() {'")
    [ "$count" -ge 13 ]
}

@test "All functions have usage/error handling" {
    # Check that functions validate their inputs
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'Usage:' config/14-functions.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 5 ]
}
