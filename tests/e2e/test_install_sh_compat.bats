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
    run "$ROOT/install.sh" --non-interactive --minimal --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ -f "$TMP/target/config/00-core.zsh" ]
}

@test "install.sh --system is forwarded to nivuus install --system" {
    # Fausse racine : rien ne touche /etc ni /usr. --dry-run ne demande
    # jamais sudo, donc ce test tourne aussi bien root que non.
    mkdir -p "$TMP/root/etc/zsh"
    : > "$TMP/root/etc/zsh/zshrc"
    export NIVUUS_ETC_DIR="$TMP/root/etc" NIVUUS_SYSTEM_PREFIX="$TMP/root/usr/share/nivuus-shell"
    run "$ROOT/install.sh" --system --non-interactive --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TMP/root/etc/zsh/zshrc"* ]]
    [[ "$output" == *"$TMP/root/usr/share/nivuus-shell"* ]]
}

@test "install.sh --user is forwarded and never touches the system" {
    mkdir -p "$TMP/root/etc/zsh"
    : > "$TMP/root/etc/zsh/zshrc"
    export NIVUUS_ETC_DIR="$TMP/root/etc" NIVUUS_SYSTEM_PREFIX="$TMP/root/usr/share/nivuus-shell"
    run "$ROOT/install.sh" --user --non-interactive --dry-run --minimal
    [ "$status" -eq 0 ]
    [[ "$output" == *"$HOME/.zshrc"* ]]
    [[ "$output" != *"$TMP/root/etc/zsh/zshrc"* ]]
    [[ "$output" != *"$TMP/root/usr"* ]]
}

@test "install.sh --no-chsh is accepted" {
    run "$ROOT/install.sh" --non-interactive --no-chsh --prefix "$TMP/target" --minimal
    [ "$status" -eq 0 ]
}

@test "install.sh --no-backup is accepted" {
    run "$ROOT/install.sh" --non-interactive --no-backup --minimal --prefix "$TMP/target"
    [ "$status" -eq 0 ]
}

@test "install.sh no longer creates a git repo" {
    "$ROOT/install.sh" --non-interactive --minimal --prefix "$TMP/target"
    [ ! -e "$TMP/target/.git" ]
}

@test "install.sh --prefix with a space in the path works end-to-end" {
    run "$ROOT/install.sh" --non-interactive --minimal --prefix "$TMP/target dir"
    [ "$status" -eq 0 ]
    [ -f "$TMP/target dir/config/00-core.zsh" ]
}
