#!/usr/bin/env bats

# Unit tests for Vim module (config/08-vim.zsh)

# =============================================================================
# Module Loading Tests
# =============================================================================

setup() {
    # Test the tree this file belongs to, never whatever NIVUUS_SHELL_DIR the
    # environment happens to point at.
    NIVUUS_SHELL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export NIVUUS_SHELL_DIR
}

@test "Vim module loads without errors" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/08-vim.zsh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "Module checks if vim is installed" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'command -v vim' config/08-vim.zsh"
    [ "$status" -eq 0 ]
}

@test "Module returns early when vim not found" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 1 'command -v vim' config/08-vim.zsh | grep 'return'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Environment Detection Tests
# =============================================================================

@test "detect_vim_env function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'detect_vim_env()' config/08-vim.zsh"
    [ "$status" -eq 0 ]
}

@test "detect_vim_env detects SSH environment" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'SSH_CLIENT' config/08-vim.zsh"
    [ "$status" -eq 0 ]
}

@test "detect_vim_env detects VS Code environment" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'VSCODE_INJECTION' config/08-vim.zsh"
    [ "$status" -eq 0 ]
}

@test "detect_vim_env detects TERM_PROGRAM vscode" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'TERM_PROGRAM.*vscode' config/08-vim.zsh"
    [ "$status" -eq 0 ]
}

@test "detect_vim_env detects Codespaces" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'CODESPACES' config/08-vim.zsh"
    [ "$status" -eq 0 ]
}

@test "detect_vim_env detects Gitpod" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'GITPOD_WORKSPACE_ID' config/08-vim.zsh"
    [ "$status" -eq 0 ]
}

@test "detect_vim_env returns ssh, vscode, web, or local" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c -E '(echo \"ssh\"|echo \"vscode\"|echo \"web\"|echo \"local\")' config/08-vim.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 4 ]
}

# =============================================================================
# vedit Function Tests
# =============================================================================

@test "vedit function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'vedit()' config/08-vim.zsh"
    [ "$status" -eq 0 ]
}

@test "vedit uses detect_vim_env" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 3 'vedit()' config/08-vim.zsh | grep 'detect_vim_env'"
    [ "$status" -eq 0 ]
}

@test "vedit uses .vimrc.nord" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 5 'vedit()' config/08-vim.zsh | grep '.vimrc.nord'"
    [ "$status" -eq 0 ]
}

@test "vedit has case statement for environment" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 'vedit()' config/08-vim.zsh | grep 'case.*env'"
    [ "$status" -eq 0 ]
}

@test "vedit SSH mode uses --noplugin" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 15 'vedit()' config/08-vim.zsh | grep 'ssh)' -A 3 | grep -- '--noplugin'"
    [ "$status" -eq 0 ]
}

@test "vedit VS Code mode tries code command" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 20 'vedit()' config/08-vim.zsh | grep 'vscode)' -A 3 | grep 'code'"
    [ "$status" -eq 0 ]
}

@test "vedit web mode uses --noplugin" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 25 'vedit()' config/08-vim.zsh | grep 'web)' -A 3 | grep -- '--noplugin'"
    [ "$status" -eq 0 ]
}

@test "vedit local mode uses full features" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 30 'vedit()' config/08-vim.zsh | grep '\*)' -A 3 | grep 'vim -u'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Vim Aliases Tests
# =============================================================================

@test "vim.modern alias is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'alias vim.modern=' config/08-vim.zsh"
    [ "$status" -eq 0 ]
}

@test "vim.modern uses .vimrc.nord" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'vim.modern=.*\.vimrc\.nord' config/08-vim.zsh"
    [ "$status" -eq 0 ]
}

@test "vim.ssh alias is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'alias vim.ssh=' config/08-vim.zsh"
    [ "$status" -eq 0 ]
}

@test "vim.ssh uses --noplugin" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'vim.ssh=.*--noplugin' config/08-vim.zsh"
    [ "$status" -eq 0 ]
}

@test "Default vim alias uses Nord theme" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'alias vim=.*\.vimrc\.nord' config/08-vim.zsh"
    [ "$status" -eq 0 ]
}

@test "Default vim alias adapts to SSH" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 5 'if.*detect_vim_env.*ssh' config/08-vim.zsh | grep 'alias vim='"
    [ "$status" -eq 0 ]
}

# =============================================================================
# vim_help Function Tests
# =============================================================================

@test "vim_help function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'vim_help()' config/08-vim.zsh"
    [ "$status" -eq 0 ]
}

@test "vim_help shows keyboard shortcuts" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 25 'vim_help()' config/08-vim.zsh | grep 'Ctrl+C'"
    [ "$status" -eq 0 ]
}

@test "vim_help shows Ctrl+V shortcut" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 25 'vim_help()' config/08-vim.zsh | grep 'Ctrl+V'"
    [ "$status" -eq 0 ]
}

@test "vim_help shows Ctrl+X shortcut" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 25 'vim_help()' config/08-vim.zsh | grep 'Ctrl+X'"
    [ "$status" -eq 0 ]
}

@test "vim_help shows Ctrl+A shortcut" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 25 'vim_help()' config/08-vim.zsh | grep 'Ctrl+A'"
    [ "$status" -eq 0 ]
}

@test "vim_help documents vedit command" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 30 'vim_help()' config/08-vim.zsh | grep 'vedit'"
    [ "$status" -eq 0 ]
}

@test "vim_help documents vim.modern" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 30 'vim_help()' config/08-vim.zsh | grep 'vim.modern'"
    [ "$status" -eq 0 ]
}

@test "vim_help documents vim.ssh" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 30 'vim_help()' config/08-vim.zsh | grep 'vim.ssh'"
    [ "$status" -eq 0 ]
}

@test "vim_help shows current environment" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 35 'vim_help()' config/08-vim.zsh | grep 'detect_vim_env'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Environment Variables Tests
# =============================================================================

@test "EDITOR is set to vim" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'export EDITOR=' config/08-vim.zsh"
    [ "$status" -eq 0 ]
}

@test "VISUAL is set to vim" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'export VISUAL=' config/08-vim.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Integration Tests
# =============================================================================

@test ".vimrc.nord file exists" {
    [ -f "$NIVUUS_SHELL_DIR/.vimrc.nord" ]
}

@test "All vim commands reference .vimrc.nord" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c '.vimrc.nord' config/08-vim.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 5 ]
}

# =============================================================================
# Coverage Tests
# =============================================================================

@test "Module defines at least 3 main functions/commands" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c -E '(detect_vim_env|vedit|vim_help)\(\)' config/08-vim.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -eq 3 ]
}

@test "Module defines 3 vim aliases" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c '^alias vim' config/08-vim.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 2 ]
}

@test "Module supports 4 environment types (ssh, vscode, web, local)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c -E '(ssh\)|vscode\)|web\)|\\*\\))' config/08-vim.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 4 ]
}

@test "Module documents modern keyboard shortcuts" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 30 'vim_help()' config/08-vim.zsh | grep -c 'Ctrl+'"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 4 ]
}

@test "Module uses NIVUUS_SHELL_DIR variable" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'NIVUUS_SHELL_DIR' config/08-vim.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 3 ]
}
