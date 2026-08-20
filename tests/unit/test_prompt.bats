#!/usr/bin/env bats

# Unit tests for prompt module (config/05-prompt.zsh)

# Helper to run zsh with correct NIVUUS_SHELL_DIR
run_zsh() {
    run zsh -c "export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR' && $1"
}

# =============================================================================
# Module Loading Tests
# =============================================================================

@test "Prompt module loads without errors" {
    run zsh -c "export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR' && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "PROMPT_SUBST is enabled" {
    run zsh -c "export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR' && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' 2>/dev/null; source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && setopt | grep -i promptsubst"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Helper Functions Tests
# =============================================================================

@test "is_ssh function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && typeset -f is_ssh"
    [ "$status" -eq 0 ]
}

@test "is_root function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && typeset -f is_root"
    [ "$status" -eq 0 ]
}

@test "is_ssh detects SSH_CLIENT" {
    run zsh -c "export SSH_CLIENT='1.2.3.4' && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && is_ssh"
    [ "$status" -eq 0 ]
}

@test "is_ssh detects SSH_TTY" {
    run zsh -c "export SSH_TTY='/dev/pts/0' && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && is_ssh"
    [ "$status" -eq 0 ]
}

@test "is_ssh returns false when not SSH" {
    run zsh -c "unset SSH_CLIENT SSH_TTY SESSION_TYPE && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && is_ssh"
    [ "$status" -ne 0 ]
}

# =============================================================================
# Git Prompt Tests
# =============================================================================

@test "git_prompt_info function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && typeset -f git_prompt_info"
    [ "$status" -eq 0 ]
}

@test "git_prompt_info returns empty when not in git repo" {
    run zsh -c "cd /tmp && export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR' && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' 2>/dev/null; source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && git_prompt_info"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Git cache variables are initialized" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '_GIT_PROMPT_CACHE' config/05-prompt.zsh | grep 'typeset -g'"
    [ "$status" -eq 0 ]
}

@test "Git cache uses configurable TTL" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'GIT_PROMPT_CACHE_TTL:-2' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Git prompt shows branch name" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'symbolic-ref' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Git prompt detects dirty state" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'git status --porcelain' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Git prompt uses THEME_GIT_PREFIX/THEME_GIT_BRANCH/THEME_SUCCESS/THEME_ERROR" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 35 'git_prompt_info()' config/05-prompt.zsh | grep -cE 'THEME_GIT_PREFIX|THEME_GIT_BRANCH|THEME_SUCCESS|THEME_ERROR'"
    [ "$status" -eq 0 ]
    [ "$output" -ge 3 ]
}

# =============================================================================
# Python Virtual Environment Tests
# =============================================================================

@test "prompt_python_venv function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'prompt_python_venv()' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Python prompt detects VIRTUAL_ENV" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'VIRTUAL_ENV' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Python prompt detects CONDA" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'CONDA_DEFAULT_ENV' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Python prompt detects Poetry" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'POETRY_ACTIVE' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Python prompt uses the theme's magenta color" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 22 'prompt_python_venv()' config/05-prompt.zsh | grep 'THEME_COLORS\[magenta\]'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Cloud Context Tests
# =============================================================================

@test "prompt_cloud_context function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'prompt_cloud_context()' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Cloud prompt detects AWS_PROFILE" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'AWS_PROFILE' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Cloud prompt detects GCP project" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'CLOUDSDK_CORE_PROJECT' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Cloud prompt detects Azure subscription" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'AZURE_SUBSCRIPTION' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Firebase Prompt Tests
# =============================================================================

@test "prompt_firebase function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'prompt_firebase()' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Firebase prompt can be disabled" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'ENABLE_FIREBASE_PROMPT' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Firebase cache variables are initialized" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '_FIREBASE_PROMPT_CACHE' config/05-prompt.zsh | grep 'typeset -g'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Background Jobs Tests
# =============================================================================

@test "background_jobs_info function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'background_jobs_info()' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Background jobs uses jobstates" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'jobstates' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Background jobs shows running indicator" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '▶' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Background jobs shows suspended indicator" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '⏸' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Build Prompt Tests
# =============================================================================

@test "build_prompt function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && typeset -f build_prompt"
    [ "$status" -eq 0 ]
}

@test "build_prompt generates output" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && build_prompt"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

# =============================================================================
# PROMPT and RPROMPT Tests
# =============================================================================

@test "PROMPT is set" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'PROMPT=' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "RPROMPT is set for background jobs" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'RPROMPT=' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Theme Color Usage Tests
# =============================================================================
# The prompt no longer hardcodes ANSI codes: it reads $THEME_* variables and
# $THEME_COLORS[...] entries set by whichever themes/*.zsh is loaded.

@test "Prompt uses THEME_GIT_PREFIX/THEME_GIT_BRANCH for git decorations" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'THEME_GIT_PREFIX\|THEME_GIT_BRANCH' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 2 ]
}

@test "Prompt uses THEME_ERROR for errors/dirty status" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'THEME_ERROR' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 2 ]
}

@test "Prompt uses THEME_SUCCESS for success" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'THEME_SUCCESS' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 2 ]
}

@test "Prompt contains no hardcoded ANSI-256 color literals" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -cE '%F\{[0-9]+\}' config/05-prompt.zsh"
    [ "$status" -eq 1 ] || [ "${output}" -eq 0 ]
}

# =============================================================================
# Theme Pluggability Tests
# =============================================================================

@test "NIVUUS_THEME=dracula changes the loaded theme colors" {
    run zsh -c "export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR' && export NIVUUS_THEME='dracula' && source '$NIVUUS_SHELL_DIR/config/00-core.zsh' >/dev/null 2>&1 && echo \"\$THEME_BAT_NAME\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dracula"* ]]
}

@test "unknown NIVUUS_THEME falls back to nord" {
    run zsh -c "export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR' && export NIVUUS_THEME='does-not-exist' && source '$NIVUUS_SHELL_DIR/config/00-core.zsh' >/dev/null 2>&1 && echo \"\$THEME_BAT_NAME\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nord"* ]]
}

# =============================================================================
# Prompt Format Template Tests
# =============================================================================

@test "NIVUUS_PROMPT_FORMAT customizes which segments build_prompt renders" {
    run zsh -c "export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR' && export NIVUUS_PROMPT_FORMAT='{path}' && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' >/dev/null 2>&1 && build_prompt"
    [ "$status" -eq 0 ]
    [ "$output" = '$(prompt_segment_path)' ]
}

@test "default build_prompt output matches the documented default template" {
    run zsh -c "export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR' && unset NIVUUS_PROMPT_FORMAT && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' >/dev/null 2>&1 && build_prompt"
    [ "$status" -eq 0 ]
    [ "$output" = '$(prompt_segment_ssh)$(prompt_segment_root)$(prompt_segment_status) $(prompt_segment_path)$(prompt_python_venv)$(prompt_cloud_context)$(prompt_firebase)$(git_prompt_info) ' ]
}

# =============================================================================
# Cache Performance Tests
# =============================================================================

@test "Git cache TTL defaults to 2 seconds" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'GIT_PROMPT_CACHE_TTL:-2' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Firebase cache has TTL" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '_FIREBASE_PROMPT_CACHE_TIME' config/05-prompt.zsh | head -3"
    [ "$status" -eq 0 ]
}

@test "Azure cache has TTL" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '_AZURE_PROMPT_CACHE_TIME' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}
