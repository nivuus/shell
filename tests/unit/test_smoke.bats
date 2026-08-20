#!/usr/bin/env bats

# Smoke tests to verify test infrastructure works

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
