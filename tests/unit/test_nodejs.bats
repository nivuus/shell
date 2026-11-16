#!/usr/bin/env bats

# Unit tests for Node.js module (config/09-nodejs.zsh)

# Note: Many of these tests are implementation checks since we can't test NVM loading
# without actually having NVM installed

# =============================================================================
# Module Loading Tests
# =============================================================================

setup() {
    # Test the tree this file belongs to, never whatever NIVUUS_SHELL_DIR the
    # environment happens to point at.
    NIVUUS_SHELL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export NIVUUS_SHELL_DIR
}

@test "Node.js module loads without errors" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-nodejs.zsh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "Module checks for NVM directory" {
    mkdir -p "$BATS_TEST_TMPDIR/without" "$BATS_TEST_TMPDIR/with/.nvm"
    run env HOME="$BATS_TEST_TMPDIR/without" zsh -c "source '$NIVUUS_SHELL_DIR/config/09-nodejs.zsh'; whence -w nvm"
    [[ "$output" != *"nvm: function"* ]]
    run env HOME="$BATS_TEST_TMPDIR/with" zsh -c "source '$NIVUUS_SHELL_DIR/config/09-nodejs.zsh'; whence -w nvm"
    [ "$status" -eq 0 ]
    [[ "$output" == *"nvm: function"* ]]
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
    local home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$home/.nvm"
    printf 'nvm() { print -r -- "real nvm, NVM_DIR=$NVM_DIR" }\n' > "$home/.nvm/nvm.sh"
    run env -u NVM_DIR HOME="$home" zsh -c "source '$NIVUUS_SHELL_DIR/config/09-nodejs.zsh'; nvm"
    [ "$status" -eq 0 ]
    [ "$output" = "real nvm, NVM_DIR=$home/.nvm" ]
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
    mkdir -p "$BATS_TEST_TMPDIR/proj"
    printf '{}\n' > "$BATS_TEST_TMPDIR/proj/package.json"
    run zsh -c "cd '$BATS_TEST_TMPDIR/proj'; source '$NIVUUS_SHELL_DIR/config/09-nodejs.zsh'; detect-project"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Node.js project detected"* ]]
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
    mkdir -p "$BATS_TEST_TMPDIR/home/.nvm"
    run env HOME="$BATS_TEST_TMPDIR/home" zsh -c "source '$NIVUUS_SHELL_DIR/config/09-nodejs.zsh' >/dev/null 2>&1; nvm-install"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NVM already installed"* ]]
}

# A local repository stands in for nvm-sh/nvm: tag v0.41.0 on a commit whose
# nvm.sh defines a recognisable nvm function.
_fake_nvm_repo() {
    local repo="$BATS_TEST_TMPDIR/nvm-src"
    git init -q -b master "$repo"
    printf 'nvm() { print -r -- "pinned nvm" }\n' > "$repo/nvm.sh"
    git -C "$repo" add nvm.sh
    git -C "$repo" -c user.name=t -c user.email=t@t commit -q -m release
    git -C "$repo" tag v0.41.0
    git -C "$repo" rev-parse HEAD
}

_nvm_cmd() {
    run env HOME="$BATS_TEST_TMPDIR/home" NIVUUS_NVM_REPO="file://$BATS_TEST_TMPDIR/nvm-src" \
        NIVUUS_NVM_COMMIT="$1" zsh -c "source '$NIVUUS_SHELL_DIR/config/09-nodejs.zsh' >/dev/null 2>&1; $2"
}

@test "nvm-install clones the pinned tag and checks its commit, without piping a script to a shell" {
    local commit
    commit="$(_fake_nvm_repo)"
    mkdir -p "$BATS_TEST_TMPDIR/home"
    _nvm_cmd "$commit" "nvm-install"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NVM v0.41.0 installed"* ]]
    [ "$(git -C "$BATS_TEST_TMPDIR/home/.nvm" rev-parse HEAD)" = "$commit" ]
    [ -s "$BATS_TEST_TMPDIR/home/.nvm/nvm.sh" ]
    # The lazy loader picks the clone up.
    _nvm_cmd "$commit" "nvm"
    [[ "$output" == *"pinned nvm"* ]]
}

@test "nvm-install refuses a tag that no longer points at the pinned commit" {
    _fake_nvm_repo >/dev/null
    mkdir -p "$BATS_TEST_TMPDIR/home"
    _nvm_cmd 0000000000000000000000000000000000000000 "nvm-install"
    [ "$status" -ne 0 ]
    [[ "$output" == *"expected 0000000000000000000000000000000000000000: refusing it"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/home/.nvm" ]
    [ -z "$(ls -A "$BATS_TEST_TMPDIR/home")" ]
}

@test "nvm-update functions are defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-nodejs.zsh' >/dev/null 2>&1; typeset -f nvm-install nvm-update >/dev/null"
    [ "$status" -eq 0 ]
}

@test "nvm-update checks if NVM exists" {
    mkdir -p "$BATS_TEST_TMPDIR/home"
    run env HOME="$BATS_TEST_TMPDIR/home" zsh -c "source '$NIVUUS_SHELL_DIR/config/09-nodejs.zsh' >/dev/null 2>&1; nvm-update"
    [ "$status" -eq 1 ]
    [[ "$output" == *"NVM not installed"* ]]
}

@test "nvm-update moves to the pinned commit and refuses a moved tag" {
    local commit
    commit="$(_fake_nvm_repo)"
    mkdir -p "$BATS_TEST_TMPDIR/home"
    _nvm_cmd "$commit" "nvm-install"
    [ "$status" -eq 0 ]
    _nvm_cmd "$commit" "nvm-update"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NVM at v0.41.0"* ]]
    # The tag is moved upstream to another commit: refused, checkout kept.
    local src="$BATS_TEST_TMPDIR/nvm-src"
    echo "evil" >> "$src/nvm.sh"
    git -C "$src" -c user.name=t -c user.email=t@t commit -qam moved
    git -C "$src" tag -f v0.41.0 >/dev/null
    _nvm_cmd "$commit" "nvm-update"
    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing it"* ]]
    [ "$(git -C "$BATS_TEST_TMPDIR/home/.nvm" rev-parse HEAD)" = "$commit" ]
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
