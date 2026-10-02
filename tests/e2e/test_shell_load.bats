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
    if [[ "${CI:-false}" == "true" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        skip "Requires a provisioned shell environment; a CI runner only has a clone"
    fi

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

# A system-wide install (/etc/zsh/zshrc) and an older per-user one (~/.zshrc)
# both source .zshrc in the same shell: the second must be a no-op, and the
# first install must stay the active one.
@test "Sourcing .zshrc from a second install in the same shell is skipped" {
    TMP="$(mktemp -d)"
    for d in a b; do
        mkdir -p "$TMP/$d"
        cp -r "$NIVUUS_SHELL_DIR/config" "$NIVUUS_SHELL_DIR/themes" "$NIVUUS_SHELL_DIR/.zshrc" "$TMP/$d/"
        find "$TMP/$d" -name '*.zwc' -delete
    done
    run env -u NIVUUS_SHELL_DIR -u NIVUUS_SHELL_LOADED_FROM zsh -c "
        NIVUUS_NO_COMPILE=1
        source '$TMP/a/.zshrc'
        export NIVUUS_SHELL_DIR='$TMP/b'
        source '$TMP/b/.zshrc'
        echo \"DIR=\$NIVUUS_SHELL_DIR\"
        zsh -c 'echo \"CHILD=[\$NIVUUS_SHELL_LOADED_FROM]\"'
    "
    rm -rf "$TMP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DIR=$TMP/a"* ]]      # la première installation reste active
    [[ "$output" == *"CHILD=[]"* ]]         # la garde n'est pas exportée : un zsh fils recharge
}

@test "Re-sourcing the same .zshrc still reloads (source ~/.zshrc after editing)" {
    run env -u NIVUUS_SHELL_LOADED_FROM zsh -c "
        NIVUUS_NO_COMPILE=1
        source '$NIVUUS_SHELL_DIR/.zshrc'
        unfunction build_prompt
        source '$NIVUUS_SHELL_DIR/.zshrc'
        typeset -f build_prompt >/dev/null && echo reloaded
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"reloaded"* ]]
}
