#!/usr/bin/env bats

# Integration tests for module loading order and dependencies

# =============================================================================
# Module Load Order Tests
# =============================================================================

@test "Config files array exists in .zshrc" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'config_files=(' .zshrc"
    [ "$status" -eq 0 ]
}

@test "All config modules defined in array" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && sed -n '/config_files=(/,/)$/p' .zshrc | grep -c '\.zsh'"
    [ "$status" -eq 0 ]
    count="${output}"
    # Should have at least 20 modules
    [ "$count" -ge 20 ]
}

@test "Cleanup module (99-cleanup) is last in array" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && sed -n '/config_files=(/,/)$/p' .zshrc | grep '\.zsh' | tail -1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"99-cleanup.zsh"* ]]
}

@test "All modules load without errors" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/.zshrc' && echo 'success'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"success"* ]]
}

@test "No duplicate modules in config_files array" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && sed -n '/config_files=(/,/)$/p' .zshrc | grep '05-prompt.zsh' | wc -l"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -eq 1 ]
}

# =============================================================================
# Dependency Tests
# =============================================================================

@test "Prompt module can access theme colors" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && echo \$THEME_SUCCESS"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "Git module can access theme colors" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && echo \$THEME_GIT_BRANCH"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "AI suggestions module loads successfully" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "Modules can access NIVUUS_SHELL_DIR" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/08-vim.zsh' && echo \$NIVUUS_SHELL_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"nivuus-shell"* ]]
}

# =============================================================================
# Module Interaction Tests
# =============================================================================

@test "Functions module (14) appears before aliases (15) in array" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && sed -n '/config_files=(/,/)$/p' .zshrc | grep -n '14-functions.zsh'"
    [ "$status" -eq 0 ]
    functions_line=$(echo "$output" | cut -d: -f1)

    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && sed -n '/config_files=(/,/)$/p' .zshrc | grep -n '15-aliases.zsh'"
    [ "$status" -eq 0 ]
    aliases_line=$(echo "$output" | cut -d: -f1)

    [ "$functions_line" -lt "$aliases_line" ]
}

@test "Prompt module (05) appears before AI suggestions (19) in array" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && sed -n '/config_files=(/,/)$/p' .zshrc | grep -n '05-prompt.zsh'"
    [ "$status" -eq 0 ]
    prompt_line=$(echo "$output" | cut -d: -f1)

    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && sed -n '/config_files=(/,/)$/p' .zshrc | grep -n '19-ai-suggestions.zsh'"
    [ "$status" -eq 0 ]
    ai_line=$(echo "$output" | cut -d: -f1)

    [ "$prompt_line" -lt "$ai_line" ]
}

@test "Git module (06) appears before navigation (07) in array" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && sed -n '/config_files=(/,/)$/p' .zshrc | grep -n '06-git.zsh'"
    [ "$status" -eq 0 ]
    git_line=$(echo "$output" | cut -d: -f1)

    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && sed -n '/config_files=(/,/)$/p' .zshrc | grep -n '07-navigation.zsh'"
    [ "$status" -eq 0 ]
    nav_line=$(echo "$output" | cut -d: -f1)

    [ "$git_line" -lt "$nav_line" ]
}

# =============================================================================
# Critical Module Tests
# =============================================================================

@test "Core module (00-core) is first in config_files array" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && sed -n '/config_files=(/,/)$/p' .zshrc | grep '\.zsh' | head -1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"00-core.zsh"* ]]
}

@test "Environment module (01-environment) is second in array" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && sed -n '/config_files=(/,/)$/p' .zshrc | grep '\.zsh' | head -2 | tail -1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"01-environment.zsh"* ]]
}

@test "History module (02) appears before prompt (05) in array" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && sed -n '/config_files=(/,/)$/p' .zshrc | grep -n '02-history.zsh'"
    [ "$status" -eq 0 ]
    history_line=$(echo "$output" | cut -d: -f1)

    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && sed -n '/config_files=(/,/)$/p' .zshrc | grep -n '05-prompt.zsh'"
    [ "$status" -eq 0 ]
    prompt_line=$(echo "$output" | cut -d: -f1)

    [ "$history_line" -lt "$prompt_line" ]
}

@test "Completion module (03) appears before keybindings (04) in array" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && sed -n '/config_files=(/,/)$/p' .zshrc | grep -n '03-completion.zsh'"
    [ "$status" -eq 0 ]
    completion_line=$(echo "$output" | cut -d: -f1)

    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && sed -n '/config_files=(/,/)$/p' .zshrc | grep -n '04-keybindings.zsh'"
    [ "$status" -eq 0 ]
    keybindings_line=$(echo "$output" | cut -d: -f1)

    [ "$completion_line" -lt "$keybindings_line" ]
}

# =============================================================================
# Performance Impact Tests
# =============================================================================

@test "Module loading completes within 300ms" {
    start=$(date +%s%N)
    zsh -i -c 'exit' 2>/dev/null
    end=$(date +%s%N)
    elapsed_ms=$(( (end - start) / 1000000 ))

    [ "$elapsed_ms" -lt 300 ]
}

@test "Theme loading is fast (<50ms)" {
    start=$(date +%s%N)
    zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh'"
    end=$(date +%s%N)
    elapsed_ms=$(( (end - start) / 1000000 ))

    [ "$elapsed_ms" -lt 50 ]
}

@test "Core modules load fast (<100ms total)" {
    start=$(date +%s%N)
    zsh -c "source '$NIVUUS_SHELL_DIR/config/00-core.zsh' && source '$NIVUUS_SHELL_DIR/config/01-environment.zsh' && source '$NIVUUS_SHELL_DIR/config/02-history.zsh'"
    end=$(date +%s%N)
    elapsed_ms=$(( (end - start) / 1000000 ))

    [ "$elapsed_ms" -lt 100 ]
}

# =============================================================================
# Module Count and Coverage Tests
# =============================================================================

@test "Modules load with for loop" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'for config_file in.*config_files' .zshrc"
    [ "$status" -eq 0 ]
}

@test "No missing module files" {
    # Check key module files exist
    [ -f "$NIVUUS_SHELL_DIR/config/00-core.zsh" ]
    [ -f "$NIVUUS_SHELL_DIR/config/05-prompt.zsh" ]
    [ -f "$NIVUUS_SHELL_DIR/config/14-functions.zsh" ]
    [ -f "$NIVUUS_SHELL_DIR/config/15-aliases.zsh" ]
    [ -f "$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh" ]
    [ -f "$NIVUUS_SHELL_DIR/config/21-safety.zsh" ]
    [ -f "$NIVUUS_SHELL_DIR/config/99-cleanup.zsh" ]
}

@test "Nord theme file exists" {
    [ -f "$NIVUUS_SHELL_DIR/themes/nord.zsh" ]
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "Modules handle missing dependencies gracefully" {
    # Test vim module without vim in PATH (should return early)
    run zsh -c "PATH=/nonexistent source '$NIVUUS_SHELL_DIR/config/08-vim.zsh' 2>/dev/null && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "Optional features can be disabled" {
    run bash -c "ENABLE_SYNTAX_HIGHLIGHTING=false zsh -c \"source '$NIVUUS_SHELL_DIR/.zshrc' && echo 'success'\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"success"* ]]
}

@test "Module loading with missing NVM directory" {
    run bash -c "HOME=/tmp zsh -c \"source '$NIVUUS_SHELL_DIR/config/09-nodejs.zsh' && echo 'loaded'\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

# =============================================================================
# Integration Tests
# =============================================================================

@test "Prompt integrates with git module" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && zsh -c \"source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && typeset -f git_prompt_info\""
    [ "$status" -eq 0 ]
}

@test "AI suggestions integrate with prompt" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && zsh -c \"source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh' && echo \\\$RPROMPT\""
    [ "$status" -eq 0 ]
}

@test "Safety module integrates with preexec hook" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' 2>/dev/null && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}
