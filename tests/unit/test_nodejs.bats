#!/usr/bin/env bats

# Unit tests for Node.js module (config/09-nodejs.zsh)

# Note: Many of these tests are implementation checks since we can't test NVM loading
# without actually having NVM installed

# =============================================================================
# Module Loading Tests
# =============================================================================

@test "Node.js module loads without errors" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-nodejs.zsh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "Module checks for NVM directory" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '~/.nvm' config/09-nodejs.zsh | head -3"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Lazy Loading Tests
# =============================================================================

@test "NVM lazy loading function wrapper is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'nvm()' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "Node lazy loading function wrapper is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'node()' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "NPM lazy loading function wrapper is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'npm()' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "Lazy load functions unfunction themselves" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'unfunction' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 3 ]
}

@test "Lazy load sets NVM_DIR" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'export NVM_DIR=' config/09-nodejs.zsh | head -3"
    [ "$status" -eq 0 ]
}

@test "Lazy load sources nvm.sh" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'source.*nvm.sh' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "Lazy load includes bash completion" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'bash_completion' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Auto-switch Tests
# =============================================================================

@test "load-nvmrc function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'load-nvmrc()' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "load-nvmrc respects ENABLE_PROJECT_DETECTION" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'ENABLE_PROJECT_DETECTION:-true' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "load-nvmrc uses nvm_find_nvmrc" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 15 'load-nvmrc()' config/09-nodejs.zsh | grep 'nvm_find_nvmrc'"
    [ "$status" -eq 0 ]
}

@test "load-nvmrc installs missing versions" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 15 'load-nvmrc()' config/09-nodejs.zsh | grep 'nvm install'"
    [ "$status" -eq 0 ]
}

@test "load-nvmrc switches versions silently" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'nvm use --silent' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "load-nvmrc reverts to default version" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'nvm use default --silent' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# nvm_find_nvmrc Tests
# =============================================================================

@test "nvm_find_nvmrc function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'nvm_find_nvmrc()' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "nvm_find_nvmrc searches parent directories" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 'nvm_find_nvmrc()' config/09-nodejs.zsh | grep 'while'"
    [ "$status" -eq 0 ]
}

@test "nvm_find_nvmrc stops at root directory" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 'nvm_find_nvmrc()' config/09-nodejs.zsh | grep '/'"
    [ "$status" -eq 0 ]
}

@test "nvm_find_nvmrc checks for .nvmrc file" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 'nvm_find_nvmrc()' config/09-nodejs.zsh | grep '\.nvmrc'"
    [ "$status" -eq 0 ]
}

@test "Auto-switch uses chpwd hook" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'add-zsh-hook chpwd load-nvmrc' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Project Detection Tests
# =============================================================================

@test "detect-project function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'detect-project()' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "detect-project detects package.json (Node.js)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'package.json' config/09-nodejs.zsh | head -3"
    [ "$status" -eq 0 ]
}

@test "detect-project detects requirements.txt (Python)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'requirements.txt' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "detect-project detects Cargo.toml (Rust)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'Cargo.toml' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "detect-project detects go.mod (Go)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'go.mod' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "detect-project shows Node.js commands" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'npm install' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "detect-project shows Python commands" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'pip install' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "detect-project shows Rust commands" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'cargo build' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "detect-project shows Go commands" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'go mod download' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "detect-project uses emojis for project types" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c -E '(📦|🐍|🦀|🐹)' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 4 ]
}

@test "_check_project_on_cd function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '_check_project_on_cd()' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "Project detection uses chpwd hook" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'add-zsh-hook chpwd _check_project_on_cd' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# NVM Helper Commands Tests
# =============================================================================

@test "nvm-install function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'nvm-install()' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "nvm-install checks if NVM exists" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 5 'nvm-install()' config/09-nodejs.zsh | grep 'NVM already installed'"
    [ "$status" -eq 0 ]
}

@test "nvm-install uses curl" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'curl.*nvm-sh/nvm' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "nvm-update function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'nvm-update()' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "nvm-update checks if NVM exists" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 5 'nvm-update()' config/09-nodejs.zsh | grep 'NVM not installed'"
    [ "$status" -eq 0 ]
}

@test "nvm-update uses git pull" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'git pull' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "nvm-health function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'nvm-health()' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "nvm-health shows health check header" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'NVM Health Check' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
}

@test "nvm-health checks Node.js version" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 20 'nvm-health()' config/09-nodejs.zsh | grep 'node --version'"
    [ "$status" -eq 0 ]
}

@test "nvm-health checks npm version" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 30 'nvm-health()' config/09-nodejs.zsh | grep 'npm --version'"
    [ "$status" -eq 0 ]
}

@test "nvm-health shows NVM version" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 20 'nvm-health()' config/09-nodejs.zsh | grep 'nvm --version'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Coverage Tests
# =============================================================================

@test "Module defines lazy load wrappers for nvm, node, npm" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c -E '^[[:space:]]*(nvm|node|npm)\(\)' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 3 ]
}

@test "Module defines at least 6 helper functions" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c -E '(load-nvmrc|nvm_find_nvmrc|detect-project|nvm-install|nvm-update|nvm-health)\(\)' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 6 ]
}

@test "Module supports 4 project types (Node, Python, Rust, Go)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c -E '(package\.json|requirements\.txt|Cargo\.toml|go\.mod)' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 4 ]
}

@test "Module has proper error/success indicators" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c -E '(✓|✗|⚠)' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 5 ]
}

@test "Module uses chpwd hooks for automation" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'add-zsh-hook chpwd' config/09-nodejs.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 2 ]
}
