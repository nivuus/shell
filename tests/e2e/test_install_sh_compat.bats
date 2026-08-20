#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
}

teardown() { rm -rf "$TMP"; }

@test "install.sh --help still works" {
    run "$ROOT/install.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"sage"* ]]
}

@test "install.sh --non-interactive installs without prompting" {
    run "$ROOT/install.sh" --non-interactive --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ -f "$TMP/target/config/00-core.zsh" ]
}

@test "install.sh --system fails with an explicit message" {
    run "$ROOT/install.sh" --system --non-interactive
    [ "$status" -ne 0 ]
    [[ "$output" == *"--system"* ]]
}

@test "install.sh --no-backup is accepted" {
    run "$ROOT/install.sh" --non-interactive --no-backup --prefix "$TMP/target"
    [ "$status" -eq 0 ]
}

@test "install.sh no longer creates a git repo" {
    "$ROOT/install.sh" --non-interactive --prefix "$TMP/target"
    [ ! -e "$TMP/target/.git" ]
}

@test "install.sh --prefix with a space in the path works end-to-end" {
    run "$ROOT/install.sh" --non-interactive --prefix "$TMP/target dir"
    [ "$status" -eq 0 ]
    [ -f "$TMP/target dir/config/00-core.zsh" ]
}
