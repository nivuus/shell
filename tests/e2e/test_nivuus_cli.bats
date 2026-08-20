#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"
    mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
}

teardown() { rm -rf "$TMP"; }

@test "nivuus is executable" {
    [ -x "$NIVUUS" ]
}

@test "help exits 0 and lists the subcommands" {
    run "$NIVUUS" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"install"* ]]
    [[ "$output" == *"uninstall"* ]]
}

@test "an unknown subcommand exits non-zero" {
    run "$NIVUUS" bogus
    [ "$status" -ne 0 ]
}

@test "install --dry-run touches nothing" {
    run "$NIVUUS" install --dry-run --yes --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ ! -e "$TMP/target" ]
    [ ! -e "$TMP/state" ]
    [ ! -e "$HOME/.zshrc" ]
}

@test "install --dry-run reports what it would do" {
    run "$NIVUUS" install --dry-run --yes --prefix "$TMP/target"
    [[ "$output" == *"dry-run"* ]]
}

@test "install creates the target and a zshrc block" {
    run "$NIVUUS" install --yes --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ -f "$TMP/target/config/00-core.zsh" ]
    [ -f "$TMP/target/.zshrc" ]
    run grep -c ">>> nivuus shell >>>" "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "install never creates a git repo in the target" {
    "$NIVUUS" install --yes --prefix "$TMP/target"
    [ ! -e "$TMP/target/.git" ]
}

@test "install twice is idempotent" {
    "$NIVUUS" install --yes --prefix "$TMP/target"
    cp "$HOME/.zshrc" "$TMP/zshrc.first"
    run "$NIVUUS" install --yes --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    run diff "$TMP/zshrc.first" "$HOME/.zshrc"
    [ "$status" -eq 0 ]
}

@test "install preserves a pre-existing zshrc" {
    printf 'export MINE=42\n' > "$HOME/.zshrc"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    run grep -c "export MINE=42" "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "uninstall removes the install dir and restores the zshrc" {
    printf 'export MINE=42\n' > "$HOME/.zshrc"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    run "$NIVUUS" uninstall --yes
    [ "$status" -eq 0 ]
    [ ! -d "$TMP/target" ]
    [ "$(cat "$HOME/.zshrc")" = "export MINE=42" ]
}

@test "uninstall never deletes zsh_history" {
    printf 'precious\n' > "$HOME/.zsh_history"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    "$NIVUUS" uninstall --yes --purge
    [ -f "$HOME/.zsh_history" ]
    [ "$(cat "$HOME/.zsh_history")" = "precious" ]
}

@test "uninstall --dry-run changes nothing" {
    "$NIVUUS" install --yes --prefix "$TMP/target"
    run "$NIVUUS" uninstall --dry-run --yes
    [ "$status" -eq 0 ]
    [ -d "$TMP/target" ]
}

@test "uninstall without a manifest exits cleanly with a message" {
    run "$NIVUUS" uninstall --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"aucune installation"* ]] || [[ "$output" == *"Aucune installation"* ]]
}

@test "purge does not delete HOME when NIVUUS_STATE_DIR points at it" {
    printf 'precious\n' > "$HOME/.zsh_history"
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    NIVUUS_STATE_DIR="$HOME" "$NIVUUS" install --yes --prefix "$TMP/target"
    NIVUUS_STATE_DIR="$HOME" "$NIVUUS" uninstall --yes --purge
    [ -d "$HOME" ]
    [ -f "$HOME/.zsh_history" ]
    [ "$(cat "$HOME/.zsh_history")" = "precious" ]
}

@test "purge keeps a zsh_local it did not create" {
    printf 'my own settings\n' > "$HOME/.zsh_local"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    "$NIVUUS" uninstall --yes --purge
    [ -f "$HOME/.zsh_local" ]
    [ "$(cat "$HOME/.zsh_local")" = "my own settings" ]
}

@test "install --prefix without a value fails with a readable message" {
    run "$NIVUUS" install --yes --prefix
    [ "$status" -ne 0 ]
    [[ "$output" == *"--prefix"* ]]
    [[ "$output" != *"unbound variable"* ]]
}
