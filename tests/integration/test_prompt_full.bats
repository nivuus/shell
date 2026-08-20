#!/usr/bin/env bats

# Integration tests for complete prompt system

# =============================================================================
# Full Prompt Build Tests
# =============================================================================

@test "build_prompt function generates complete prompt" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && build_prompt"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "Prompt contains path component" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && build_prompt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"prompt_segment_path"* ]]
}

@test "Prompt renders with theme colors" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && eval \"print -rn -- \\\"\$(build_prompt)\\\"\""
    [ "$status" -eq 0 ]
    # Should contain color codes once the embedded \$(...) segment calls are evaluated
    [[ "$output" == *"%F{"* ]]
}

@test "Prompt ends with reset color" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && eval \"print -rn -- \\\"\$(build_prompt)\\\"\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"%f"* ]]
}

# =============================================================================
# Git Integration Tests
# =============================================================================

@test "Git prompt integrates when in repo" {
    skip "Requires git repo context"
    # This would require being in a git repo
    run zsh -c "cd '$NIVUUS_SHELL_DIR' && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && git_prompt_info"
    [ "$status" -eq 0 ]
}

@test "Git cache is used on repeated calls" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '_GIT_PROMPT_CACHE' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Git cache TTL is configurable" {
    run zsh -c "export GIT_PROMPT_CACHE_TTL=5 && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && echo \$GIT_PROMPT_CACHE_TTL"
    [ "$status" -eq 0 ]
    [ "$output" = "5" ]
}

# =============================================================================
# Python Virtual Environment Tests
# =============================================================================

@test "Python venv shows in prompt when VIRTUAL_ENV set" {
    run zsh -c "export VIRTUAL_ENV=/tmp/test-venv && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && prompt_python_venv"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-venv"* ]]
}

@test "Conda environment shows in prompt" {
    run zsh -c "export CONDA_DEFAULT_ENV=myenv && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && prompt_python_venv"
    [ "$status" -eq 0 ]
    [[ "$output" == *"conda:myenv"* ]]
}

@test "Poetry environment shows in prompt" {
    run zsh -c "export POETRY_ACTIVE=1 && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && prompt_python_venv"
    [ "$status" -eq 0 ]
    [[ "$output" == *"poetry"* ]]
}

@test "Python venv uses the theme's magenta color" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 25 'prompt_python_venv' config/05-prompt.zsh | grep 'THEME_COLORS\[magenta\]'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Cloud Context Tests
# =============================================================================

@test "AWS profile shows in prompt" {
    run zsh -c "export AWS_PROFILE=production && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && prompt_cloud_context"
    [ "$status" -eq 0 ]
    [[ "$output" == *"aws"* ]] && [[ "$output" == *"production"* ]]
}

@test "GCP project detection in code" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'CLOUDSDK_CORE_PROJECT' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Azure subscription detection in code" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'AZURE_SUBSCRIPTION' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Cloud context function exists" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && typeset -f prompt_cloud_context"
    [ "$status" -eq 0 ]
}

# =============================================================================
# SSH Detection Tests
# =============================================================================

@test "SSH detection works with SSH_CLIENT" {
    run zsh -c "export SSH_CLIENT='1.2.3.4' && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && is_ssh"
    [ "$status" -eq 0 ]
}

@test "SSH detection works with SSH_TTY" {
    run zsh -c "export SSH_TTY='/dev/pts/0' && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && is_ssh"
    [ "$status" -eq 0 ]
}

@test "Non-SSH returns false" {
    run zsh -c "unset SSH_CLIENT SSH_TTY && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && is_ssh"
    [ "$status" -ne 0 ]
}

# =============================================================================
# Root Detection Tests
# =============================================================================

@test "Root detection function exists" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && typeset -f is_root"
    [ "$status" -eq 0 ]
}

@test "Root detection checks EUID" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'EUID' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Background Jobs Tests
# =============================================================================

@test "Background jobs function exists" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && typeset -f background_jobs_info"
    [ "$status" -eq 0 ]
}

@test "Background jobs uses jobstates" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'jobstates' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Background jobs shows running indicator (▶)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '▶' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Background jobs shows suspended indicator (⏸)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '⏸' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "RPROMPT is set for background jobs" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'RPROMPT=' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Firebase Prompt Tests
# =============================================================================

@test "Firebase prompt can be disabled" {
    run zsh -c "ENABLE_FIREBASE_PROMPT=false source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "Firebase prompt function exists" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'prompt_firebase' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Firebase cache is used" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '_FIREBASE_PROMPT_CACHE' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Performance Tests
# =============================================================================

@test "Prompt generation is fast (<50ms)" {
    start=$(date +%s%N)
    zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && build_prompt" >/dev/null
    end=$(date +%s%N)
    elapsed_ms=$(( (end - start) / 1000000 ))

    [ "$elapsed_ms" -lt 50 ]
}

@test "Git prompt caching reduces repeated calls" {
    skip "Requires git repo and timing measurement"
}

@test "Prompt uses PROMPT_SUBST for dynamic updates" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'PROMPT_SUBST' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Color Consistency Tests
# =============================================================================

@test "All prompt components use theme variables/colors" {
    # Check that prompt uses THEME_* variables or THEME_COLORS[...] lookups
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c -E '(THEME_[A-Z_]+|THEME_COLORS\[)' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 10 ]
}

@test "Success status uses THEME_SUCCESS" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'THEME_SUCCESS' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
    [ "${output}" -ge 1 ]
}

@test "Error status uses THEME_ERROR" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'THEME_ERROR' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
    [ "${output}" -ge 1 ]
}

@test "Git decorations use THEME_GIT_PREFIX" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'THEME_GIT_PREFIX' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
    [ "${output}" -ge 1 ]
}

# =============================================================================
# Integration with Other Modules
# =============================================================================

@test "Prompt integrates with Python module" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/09-python.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && typeset -f prompt_python_venv"
    [ "$status" -eq 0 ]
}

@test "Prompt can call get_python_venv from Python module" {
    run zsh -c "export VIRTUAL_ENV=/tmp/test && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/09-python.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && get_python_venv"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test"* ]]
}

@test "Full shell loads prompt correctly" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/.zshrc' && echo \$PROMPT"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "Full shell honors NIVUUS_THEME=dracula end to end" {
    run zsh -c "export NIVUUS_THEME=dracula && source '$NIVUUS_SHELL_DIR/.zshrc' && echo \$THEME_BAT_NAME"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dracula"* ]]
}

@test "Full shell honors a custom NIVUUS_PROMPT_FORMAT end to end" {
    run zsh -c "export NIVUUS_PROMPT_FORMAT='{path}' && source '$NIVUUS_SHELL_DIR/.zshrc' && print -P -- \"\$PROMPT\""
    [ "$status" -eq 0 ]
    [[ "$output" != *"git:("* ]]
}
