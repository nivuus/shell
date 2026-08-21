#!/usr/bin/env bats

# Integration tests for Git workflow (aliases + prompt)

# =============================================================================
# Git Alias Integration Tests
# =============================================================================

@test "Git status alias is defined (gs)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git status"* ]]
}

@test "Git log alias shows pretty format (gl)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"--graph"* ]]
}

@test "Git diff aliases include color" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git diff"* ]]
}

@test "Git commit alias is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git commit"* ]]
}

@test "Git push alias is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git push"* ]]
}

@test "Git pull alias is defined (gpl)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gpl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git pull"* ]]
}

@test "Git stash alias (gst)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gst"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git stash"* ]]
}

# =============================================================================
# Git Module Content Tests
# =============================================================================

@test "Git module defines branch aliases" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'alias gb=' config/06-git.zsh"
    [ "$status" -eq 0 ]
}

@test "Git module defines checkout aliases" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'alias gco=' config/06-git.zsh"
    [ "$status" -eq 0 ]
}

@test "Git module defines stash aliases" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'alias gst=' config/06-git.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Git Prompt Integration
# =============================================================================

@test "Git prompt function is defined in config/05-prompt.zsh" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'git_prompt_info()' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Git prompt checks if in repository" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 5 'git_prompt_info()' config/05-prompt.zsh | grep 'git rev-parse'"
    [ "$status" -eq 0 ]
}

@test "Git prompt returns early if not in repo" {
    run bash -c "cd /tmp && zsh -c \"source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && git_prompt_info\""
    # Should return empty when not in a git repo
    [ -z "$output" ]
}

@test "Git prompt works in actual repo" {
    run zsh -c "cd '$NIVUUS_SHELL_DIR' && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && git_prompt_info"
    [ "$status" -eq 0 ]
    # Should output git info if in repo
}

@test "Git prompt shows branch name" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'symbolic-ref --short HEAD' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Git prompt detects dirty state" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'git status --porcelain' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Git Cache Behavior
# =============================================================================

@test "Git cache uses EPOCHSECONDS" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'EPOCHSECONDS' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Git cache stores directory" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '_GIT_PROMPT_CACHE_DIR' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Git cache stores time" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '_GIT_PROMPT_CACHE_TIME' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Git cache stores value" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '_GIT_PROMPT_CACHE_VALUE' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Git cache checks directory match" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 'git_prompt_info()' config/05-prompt.zsh | grep 'current_dir'"
    [ "$status" -eq 0 ]
}

@test "Git cache validates TTL" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 15 'git_prompt_info()' config/05-prompt.zsh | grep 'cache_ttl'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Git Status Icons
# =============================================================================

@test "Git uses clean indicator (●)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '●' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Git uses dirty indicator (○)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '○' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Clean status uses THEME_SUCCESS" {
    # Le glyphe passe par $NIVUUS_GLYPH_GIT_CLEAN (défaut ●, ASCII en mode
    # minimal) ; la couleur, elle, doit rester celle du thème.
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -B 2 'NIVUUS_GLYPH_GIT_CLEAN}%' config/05-prompt.zsh | grep 'THEME_SUCCESS'"
    [ "$status" -eq 0 ]
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'NIVUUS_GLYPH_GIT_CLEAN:=●' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Dirty status uses THEME_ERROR" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -B 2 'NIVUUS_GLYPH_GIT_DIRTY}%' config/05-prompt.zsh | grep 'THEME_ERROR'"
    [ "$status" -eq 0 ]
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'NIVUUS_GLYPH_GIT_DIRTY:=○' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Git Branch Display
# =============================================================================

@test "Git branch uses the theme's red color" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'THEME_GIT_BRANCH' themes/nord.zsh"
    [ "$status" -eq 0 ]
}

@test "Git detached HEAD handling" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'detached' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Git tag detection" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'describe --tags' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Git Module Nord Colors
# =============================================================================

@test "Git module has color-formatted log aliases" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '%C(' config/06-git.zsh"
    [ "$status" -eq 0 ]
}

@test "Git prompt integrates the loaded theme" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'THEME_GIT' themes/nord.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 2 ]
}

# =============================================================================
# Full Workflow Integration
# =============================================================================

@test "Git module loads without errors" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "Git and prompt modules work together" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && echo 'success'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"success"* ]]
}

@test "Git aliases work after full load" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/.zshrc' && alias gs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git status"* ]]
}

@test "Git prompt works after full load" {
    run zsh -c "cd '$NIVUUS_SHELL_DIR' && source '$NIVUUS_SHELL_DIR/.zshrc' && typeset -f git_prompt_info"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Performance Tests
# =============================================================================

@test "Git prompt source loads quickly" {
    start=$(date +%s%N)
    zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh'" >/dev/null
    end=$(date +%s%N)
    elapsed_ms=$(( (end - start) / 1000000 ))

    # Prompt module should load quickly
    [ "$elapsed_ms" -lt 100 ]
}

@test "Git module loads quickly" {
    start=$(date +%s%N)
    zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh'" >/dev/null
    end=$(date +%s%N)
    elapsed_ms=$(( (end - start) / 1000000 ))

    [ "$elapsed_ms" -lt 50 ]
}
