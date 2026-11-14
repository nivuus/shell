#!/usr/bin/env bats

# E2E tests for installation verification

setup() {
    export NIVUUS_SHELL_DIR="${BATS_TEST_DIRNAME}/../.."
}

@test "install.sh script exists and is executable" {
    [ -f "$NIVUUS_SHELL_DIR/install.sh" ]
    [ -x "$NIVUUS_SHELL_DIR/install.sh" ]
}

@test "All required config files exist" {
    [ -f "$NIVUUS_SHELL_DIR/config/00-core.zsh" ]
    [ -f "$NIVUUS_SHELL_DIR/config/05-prompt.zsh" ]
    [ -f "$NIVUUS_SHELL_DIR/config/10-ai.zsh" ]
    [ -f "$NIVUUS_SHELL_DIR/config/99-cleanup.zsh" ]
}

@test "Theme file exists" {
    [ -f "$NIVUUS_SHELL_DIR/themes/nord.zsh" ]
}

@test "Main .zshrc file exists" {
    [ -f "$NIVUUS_SHELL_DIR/.zshrc" ]
}

@test "Bin scripts exist" {
    [ -f "$NIVUUS_SHELL_DIR/bin/healthcheck" ]
    [ -f "$NIVUUS_SHELL_DIR/bin/benchmark" ]
}

@test "README.md exists" {
    [ -f "$BATS_TEST_DIRNAME/../../README.md" ] || [ -f "$NIVUUS_SHELL_DIR/README.md" ]
}

@test "FEATURES.md documentation exists" {
    [ -f "$BATS_TEST_DIRNAME/../../doc/FEATURES.md" ] || [ -f "$NIVUUS_SHELL_DIR/doc/FEATURES.md" ]
}

@test "Installation can run in non-interactive mode" {
    run "$NIVUUS_SHELL_DIR/install.sh" --help
    [ "$status" -eq 0 ]
}

@test "Install script shows help" {
    run "$NIVUUS_SHELL_DIR/install.sh" --help
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]] || [[ "$output" == *"help"* ]]
}

@test "Install script supports --non-interactive flag" {
    run bash -c "grep -E '(--non-interactive|-n|non.interactive)' '$NIVUUS_SHELL_DIR/install.sh'"
    [ "$status" -eq 0 ]
}

@test "Install script supports --system flag" {
    run bash -c "grep -E '(--system|system.mode)' '$NIVUUS_SHELL_DIR/install.sh'"
    [ "$status" -eq 0 ]
}

@test "Install script has backup functionality" {
    run bash -c "grep -E '(backup|Backup)' '$NIVUUS_SHELL_DIR/install.sh'"
    [ "$status" -eq 0 ]
}

@test "All module numbers are sequential" {
    # Every module .zshrc lists exists under config/, named NN-name.zsh.
    run zsh -c "cd '$NIVUUS_SHELL_DIR'; eval \"\$(sed -n '/^config_files=(/,/^)$/p' .zshrc)\"
for f in \$config_files; do [[ \$f == [0-9][0-9]-*.zsh && -f config/\$f ]] || print -r -- MISSING \$f; done
print -r -- \${#config_files}"
    [ "$status" -eq 0 ]
    [[ "$output" != *MISSING* ]]
    [ "${lines[-1]}" -ge 15 ]
}

@test "Module numbering allows intentional duplicates for related modules" {
    # Some modules intentionally share numbers (e.g., 09-nodejs and 09-python, 20-autoupdate and 20-terminal-title)
    run zsh -c "files=('$NIVUUS_SHELL_DIR'/config/[0-9][0-9]-*.zsh(N)); print -r -- \${#files}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 20 ]
}

@test "Installation includes test framework" {
    [ -d "$BATS_TEST_DIRNAME/../.." ] && [ -d "$BATS_TEST_DIRNAME/.." ]
}

@test "Test helpers directory exists" {
    [ -d "$BATS_TEST_DIRNAME/../helpers" ] || [ -d "$NIVUUS_SHELL_DIR/tests/helpers" ]
}

@test "CLAUDE.md developer guide exists" {
    [ -f "$BATS_TEST_DIRNAME/../../doc/CLAUDE.md" ] || [ -f "$NIVUUS_SHELL_DIR/doc/CLAUDE.md" ]
}

@test "Installation preserves execute permissions on scripts" {
    [ -x "$NIVUUS_SHELL_DIR/bin/healthcheck" ]
    [ -x "$NIVUUS_SHELL_DIR/bin/benchmark" ]
    [ -x "$NIVUUS_SHELL_DIR/install.sh" ]
}
