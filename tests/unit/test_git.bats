#!/usr/bin/env bats

# Unit tests for git aliases module (config/06-git.zsh)

setup() {
    # Test the tree this file belongs to, never whatever NIVUUS_SHELL_DIR the
    # environment happens to point at.
    NIVUUS_SHELL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export NIVUUS_SHELL_DIR
    source "$NIVUUS_SHELL_DIR/themes/nord.zsh"
}

# =============================================================================
# Module Loading Tests
# =============================================================================

@test "Git module loads without errors when git is installed" {
    run zsh -c "command -v git >/dev/null && source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "Git module exits early if git is not installed" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && head -12 config/06-git.zsh | grep -A 2 'command -v git'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"return"* ]]
}

# =============================================================================
# Basic Operations Aliases
# =============================================================================

@test "gs alias is defined (git status -sb)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git status -sb"* ]]
}

@test "ga alias is defined (git add)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias ga"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git add"* ]]
}

@test "gaa alias is defined (git add --all)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gaa"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git add --all"* ]]
}

@test "gc alias is defined (git commit -v)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git commit -v"* ]]
}

@test "gcm alias is defined (git checkout main/master)" {
    # Note: gcm is redefined in the config file, final definition is checkout main/master
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gcm"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git checkout"* ]]
}

@test "gp alias is defined (git push)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git push"* ]]
}

@test "gpl alias is defined (git pull)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gpl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git pull"* ]]
}

# =============================================================================
# Diff Aliases
# =============================================================================

@test "gd alias is defined (git diff)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git diff"* ]]
}

@test "gds alias is defined (git diff --staged)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gds"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git diff --staged"* ]]
}

@test "gdw alias is defined (git diff --word-diff)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gdw"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git diff --word-diff"* ]]
}

# =============================================================================
# Branch Aliases
# =============================================================================

@test "gb alias is defined (git branch)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gb"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git branch"* ]]
}

@test "gba alias is defined (git branch -a)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gba"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git branch -a"* ]]
}

@test "gbd alias is defined (git branch -d)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gbd"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git branch -d"* ]]
}

@test "gco alias is defined (git checkout)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gco"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git checkout"* ]]
}

@test "gcb alias is defined (git checkout -b)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gcb"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git checkout -b"* ]]
}

# =============================================================================
# Log Aliases
# =============================================================================

@test "gl alias is defined (git log with pretty format)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git log --graph"* ]]
}

@test "gla alias is defined (git log --all)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gla"
    [ "$status" -eq 0 ]
    [[ "$output" == *"--all"* ]]
}

@test "gll alias is defined (git log long)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gll"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git log --graph"* ]]
}

# =============================================================================
# Stash Aliases
# =============================================================================

@test "gst alias is defined (git stash)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gst"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git stash"* ]]
}

@test "gstp alias is defined (git stash pop)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gstp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git stash pop"* ]]
}

@test "gstl alias is defined (git stash list)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gstl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git stash list"* ]]
}

# =============================================================================
# Remote Aliases
# =============================================================================

@test "gr alias is defined (git remote -v)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gr"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git remote -v"* ]]
}

@test "gf alias is defined (git fetch)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gf"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git fetch"* ]]
}

@test "gfa alias is defined (git fetch --all)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gfa"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git fetch --all"* ]]
}

# =============================================================================
# Undo/Reset Aliases
# =============================================================================

@test "gundo alias is defined (git reset --soft HEAD~1)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gundo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git reset --soft HEAD~1"* ]]
}

@test "greset alias is defined (git reset --hard HEAD)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias greset"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git reset --hard HEAD"* ]]
}

# =============================================================================
# Clone Alias
# =============================================================================

@test "gcl alias is defined (git clone)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias gcl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"git clone"* ]]
}

# =============================================================================
# Coverage Tests
# =============================================================================

@test "Git module defines at least 25 aliases" {
    count=$(zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh' && alias | grep -c '^g'")
    [ "$count" -ge 25 ]
}

@test "All git aliases use 'g' prefix for consistency" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep \"^alias g\" config/06-git.zsh | grep -v \"^alias g.*='git\""
    [ "$status" -ne 0 ]  # Should not find aliases without 'git' command
}
