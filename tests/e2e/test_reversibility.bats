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

@test "uninstall keeps a pre-existing empty ~/.local" {
    mkdir -p "$HOME/.local"
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    fs_fingerprint "$HOME" > "$TMP/before"
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    "$NIVUUS" uninstall --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "install, use the shell once, then uninstall still leaves HOME bit-identical" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not available"
    printf 'export MINE=42\n' > "$HOME/.zshrc"

    fs_fingerprint "$HOME" > "$TMP/before"
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    # An ordinary interactive session: zcompile of .zshrc, config/*.zsh and
    # the compdump all happen here, none of it through the manifest.
    NIVUUS_NO_COMPILE=0 zsh -i -c true
    "$NIVUUS" uninstall --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"

    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]

    # The sharpest edge of all: the shell must still start cleanly afterwards
    # (a stale .zwc newer than a restored .zshrc used to source a directory
    # uninstall had just deleted).
    run zsh -i -c 'echo POST_UNINSTALL_OK'
    [ "$status" -eq 0 ]
    [[ "$output" == *"POST_UNINSTALL_OK"* ]]
}

@test "reinstalling after the user edits their zshrc still restores the pristine original on uninstall" {
    printf 'export MINE=42\n' > "$HOME/.zshrc"
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    # The user edits their own file while Nivuus is installed, in a way
    # that changes the byte layout the next merge produces (prepending,
    # not appending, so the second install is not a no-op on .zshrc).
    sed -i '1i alias early=1' "$HOME/.zshrc"
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    "$NIVUUS" uninstall --yes --purge
    # The original backup must never have been overwritten by the
    # already-nivuus'd version taken at the second install.
    [ "$(cat "$HOME/.zshrc")" = "export MINE=42" ]
}

@test "uninstall keeps a pre-existing ~/.local/state with foreign content" {
    mkdir -p "$HOME/.local/state/someapp"
    printf 'foreign\n' > "$HOME/.local/state/someapp/data"
    fs_fingerprint "$HOME" > "$TMP/before"
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    "$NIVUUS" uninstall --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "uninstall keeps a zwc the user compiled before installing" {
    printf 'export MINE=42\n' > "$HOME/.zshrc"
    printf 'pre-existing bytecode\n' > "$HOME/.zshrc.zwc"
    fs_fingerprint "$HOME" > "$TMP/before"
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    "$NIVUUS" uninstall --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "uninstall removes a zwc Nivuus itself compiled, even after a reinstall" {
    printf 'export MINE=42\n' > "$HOME/.zshrc"
    fs_fingerprint "$HOME" > "$TMP/before"
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    zsh -i -c true || true
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell2"
    "$NIVUUS" uninstall --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "uninstall keeps a pre-existing empty ~/.cache" {
    mkdir -p "$HOME/.cache"
    printf 'export MINE=42\n' > "$HOME/.zshrc"
    fs_fingerprint "$HOME" > "$TMP/before"
    "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    zsh -i -c true || true
    "$NIVUUS" uninstall --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}
