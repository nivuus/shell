#!/usr/bin/env bats
# Le test central du chantier : install puis uninstall doit laisser $HOME
# strictement identique, empreinte par empreinte (chemin, permissions, contenu).

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"
    mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"
}

teardown() { rm -rf "$TMP"; }

@test "install then uninstall leaves HOME bit-identical (empty HOME)" {
    fs_fingerprint "$HOME" > "$TMP/before"
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    "$NIVUUS" uninstall --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "install then uninstall leaves HOME bit-identical (populated HOME)" {
    mkdir -p "$HOME/projects/app"
    printf 'export MINE=42\nalias ll="ls -la"\n' > "$HOME/.zshrc"
    printf 'my history\n' > "$HOME/.zsh_history"
    printf 'code\n' > "$HOME/projects/app/main.py"
    chmod 600 "$HOME/.zshrc"

    fs_fingerprint "$HOME" > "$TMP/before"
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    "$NIVUUS" uninstall --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"

    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "install then uninstall leaves HOME bit-identical (oh-my-zsh present)" {
    mkdir -p "$HOME/.oh-my-zsh"
    printf 'export ZSH="$HOME/.oh-my-zsh"\nsource $ZSH/oh-my-zsh.sh\n' > "$HOME/.zshrc"
    fs_fingerprint "$HOME" > "$TMP/before"
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    "$NIVUUS" uninstall --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "dry-run install leaves HOME bit-identical" {
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    fs_fingerprint "$HOME" > "$TMP/before"
    "$NIVUUS" install --dry-run --yes --prefix "$HOME/.nivuus-shell"
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "a double install then a single uninstall still reverts fully" {
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    fs_fingerprint "$HOME" > "$TMP/before"
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    "$NIVUUS" uninstall --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}
