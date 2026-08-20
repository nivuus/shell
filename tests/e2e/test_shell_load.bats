#!/usr/bin/env bats

# E2E tests for complete shell loading

setup() {
    export NIVUUS_SHELL_DIR="${BATS_TEST_DIRNAME}/../.."
}

@test "Full shell loads without errors" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/.zshrc' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "PROMPT is set after loading" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/.zshrc' && echo \$PROMPT"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "Performance tracking variables are set" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'NIVUUS_LOAD_TIME' .zshrc"
    [ "$status" -eq 0 ]
}

@test "Shell loads efficiently (no slow warning shown)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/.zshrc' 2>&1"
    [ "$status" -eq 0 ]
    # If warning appears, load time is > 500ms
    ! [[ "$output" == *"⚠️"*"Nivuus Shell"* ]]
}

@test "Theme colors are available" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/.zshrc' && echo \$THEME_SUCCESS"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "Git aliases are available" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/.zshrc' && alias gs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git"* ]]
}

@test "Prompt functions are available" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/.zshrc' && typeset -f build_prompt"
    [ "$status" -eq 0 ]
}

@test "AI functions are available" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/.zshrc' && typeset -f aihelp"
    [ "$status" -eq 0 ]
}

@test "System functions are available" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/.zshrc' && typeset -f cleanup"
    [ "$status" -eq 0 ]
}

@test "No errors in shell output" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/.zshrc' 2>&1"
    ! [[ "$output" == *"error"* ]]
    ! [[ "$output" == *"Error"* ]]
    ! [[ "$output" == *"ERROR"* ]]
}

@test "Feature toggles are exported" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/.zshrc' && echo \$ENABLE_SYNTAX_HIGHLIGHTING"
    [ "$status" -eq 0 ]
    [[ "$output" == "true" ]] || [[ "$output" == "false" ]]
}

@test "Shell loads in interactive mode" {
    run zsh -i -c "echo 'interactive'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"interactive"* ]]
}

@test "PATH includes common directories" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/.zshrc' && echo \$PATH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/usr/bin"* ]] || [[ "$output" == *"/bin"* ]]
}

@test "History settings are configured" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/.zshrc' && echo \$HISTFILE"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "Completion system is initialized" {
    # Check for lazy-loaded completion function (compinit loads on first TAB)
    run zsh -c "source '$NIVUUS_SHELL_DIR/.zshrc' 2>&1 && typeset -f _nivuus_lazy_compinit"
    [ "$status" -eq 0 ]
}
