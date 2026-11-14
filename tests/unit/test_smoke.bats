#!/usr/bin/env bats

# Smoke tests to verify test infrastructure works

setup() {
    # Test the tree this file belongs to, never whatever NIVUUS_SHELL_DIR the
    # environment happens to point at.
    NIVUUS_SHELL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export NIVUUS_SHELL_DIR
}

@test "bats is working" {
    run echo "hello"
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "NIVUUS_SHELL_DIR is set" {
    [ -n "$NIVUUS_SHELL_DIR" ]
}

@test "can load Nord theme" {
    run source "$NIVUUS_SHELL_DIR/themes/nord.zsh"
    [ "$status" -eq 0 ]
}

@test "Theme colors are defined after loading theme" {
    source "$NIVUUS_SHELL_DIR/themes/nord.zsh"
    [ -n "$THEME_PATH" ]
    [ -n "$THEME_SUCCESS" ]
    [ -n "$THEME_ERROR" ]
}

@test "can load prompt module" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh'"
    [ "$status" -eq 0 ]
}
