#!/usr/bin/env bats

# Unit tests for safety module (config/21-safety.zsh)

setup() {
    # Load dependencies
    source "$NIVUUS_SHELL_DIR/themes/nord.zsh"
}

# =============================================================================
# Module Loading Tests
# =============================================================================

@test "Safety module loads without errors" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "Safety module can be disabled via ENABLE_SAFETY_CHECKS" {
    run zsh -c "export ENABLE_SAFETY_CHECKS=false && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && typeset -f _nivuus_match_danger"
    [ "$status" -ne 0 ]
}

# =============================================================================
# Dangerous Patterns Tests
# =============================================================================

@test "DANGEROUS_PATTERNS associative array is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && typeset -p DANGEROUS_PATTERNS"
    [ "$status" -eq 0 ]
}

# Behavioural: assert what commands are actually detected as dangerous,
# independent of how the patterns are spelled.
_danger() {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && _nivuus_match_danger '$1'"
}

@test "detects 'rm -rf /'" {
    _danger 'rm -rf /'
    [ "$status" -eq 0 ]
}

@test "detects 'rm -rf ~'" {
    _danger 'rm -rf ~'
    [ "$status" -eq 0 ]
}

@test "detects 'chmod -R 777'" {
    _danger 'chmod -R 777 /var/www'
    [ "$status" -eq 0 ]
}

@test "detects raw disk write 'dd ... of=/dev/sd'" {
    _danger 'dd if=image.iso of=/dev/sda bs=4M'
    [ "$status" -eq 0 ]
}

@test "detects 'mkfs'" {
    _danger 'mkfs.ext4 /dev/sdb1'
    [ "$status" -eq 0 ]
}

@test "detects system directory deletions" {
    _danger 'rm -rf /etc'
    [ "$status" -eq 0 ]
}

@test "detects sudo package removal" {
    _danger 'apt-get remove sudo'
    [ "$status" -eq 0 ]
}

@test "detects iptables flush" {
    _danger 'iptables -F'
    [ "$status" -eq 0 ]
}

# =============================================================================
# Warning Patterns Tests
# =============================================================================

@test "WARNING_PATTERNS associative array is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && typeset -p WARNING_PATTERNS"
    [ "$status" -eq 0 ]
}

# Behavioural warning detection.
_warn() {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && _nivuus_match_warning '$1'"
}

@test "warns on 'rm -rf <dir>'" {
    _warn 'rm -rf node_modules'
    [ "$status" -eq 0 ]
}

@test "warns on git force push" {
    _warn 'git push --force origin main'
    [ "$status" -eq 0 ]
}

@test "warns on 'sudo rm'" {
    _warn 'sudo rm file.txt'
    [ "$status" -eq 0 ]
}

@test "warns on 'chmod 777'" {
    _warn 'chmod 777 file.txt'
    [ "$status" -eq 0 ]
}

@test "warns on mass deletion" {
    _warn 'find . -name "*.tmp" -delete'
    [ "$status" -eq 0 ]
}

# =============================================================================
# Safety Check Function Tests
# =============================================================================

@test "detection predicates are defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && typeset -f _nivuus_match_danger _nivuus_match_warning _nivuus_safety_confirm"
    [ "$status" -eq 0 ]
}

@test "_nivuus_match_danger does not match safe commands" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && _nivuus_match_danger 'ls -la'"
    [ "$status" -ne 0 ]
}

@test "_nivuus_match_danger returns non-zero for empty commands" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && _nivuus_match_danger ''"
    [ "$status" -ne 0 ]
}

@test "_nivuus_match_danger matches rm -rf /" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && _nivuus_match_danger 'rm -rf /'"
    [ "$status" -eq 0 ]
}

@test "_nivuus_match_danger does NOT match rm -rf of a subdirectory" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && _nivuus_match_danger 'rm -rf /home/user/project'"
    [ "$status" -ne 0 ]
}

# =============================================================================
# accept-line Widget Tests
# =============================================================================
# Unlike a preexec hook, the accept-line widget runs before submission so it
# can actually prevent execution of a dangerous command.

@test "_nivuus_safety_accept_line widget function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && typeset -f _nivuus_safety_accept_line"
    [ "$status" -eq 0 ]
}

@test "safety wraps accept-line via ZLE (not preexec)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -q 'zle -N accept-line _nivuus_safety_accept_line' config/21-safety.zsh && ! grep -q 'add-zsh-hook preexec' config/21-safety.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Safe Alternatives Tests
# =============================================================================

@test "safe-rm function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && typeset -f safe-rm"
    [ "$status" -eq 0 ]
}

@test "safe-chmod function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && typeset -f safe-chmod"
    [ "$status" -eq 0 ]
}

@test "safety-help function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && typeset -f safety-help"
    [ "$status" -eq 0 ]
}

@test "safety-help provides documentation" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && safety-help"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Command Safety Checks"* ]]
    [[ "$output" == *"ENABLE_SAFETY_CHECKS"* ]]
}

# =============================================================================
# Safe Aliases Tests
# =============================================================================

@test "Safe aliases are NOT enabled by default" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'ENABLE_SAFE_ALIASES:-false' config/21-safety.zsh"
    [ "$status" -eq 0 ]
}

@test "Safe aliases can be enabled via ENABLE_SAFE_ALIASES" {
    run zsh -c "export ENABLE_SAFE_ALIASES=true && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && alias rm"
    [ "$status" -eq 0 ]
    [[ "$output" == *"safe-rm"* ]]
}

# =============================================================================
# Pattern Coverage Tests
# =============================================================================

@test "Safety module covers at least 10 dangerous patterns" {
    count=$(zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && echo \${#DANGEROUS_PATTERNS[@]}")
    [ "$count" -ge 10 ]
}

@test "Safety module covers at least 5 warning patterns" {
    count=$(zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh' && echo \${#WARNING_PATTERNS[@]}")
    [ "$count" -ge 5 ]
}

# =============================================================================
# Color Usage Tests
# =============================================================================

@test "Safety module uses Nord error color for dangers" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'NORD_ERROR' config/21-safety.zsh"
    [ "$status" -eq 0 ]
}

@test "Safety module uses Nord colors for messages" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -E '(NORD_PATH|NORD_FIREBASE|NORD_RESET)' config/21-safety.zsh"
    [ "$status" -eq 0 ]
}
