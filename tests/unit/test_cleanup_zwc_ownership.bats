#!/usr/bin/env bats
# Nivuus ne compile jamais de bytecode dans un arbre qu'il ne possède pas :
# sous /usr/share, un shell root laisserait des orphelins qu'apt purge ne
# nettoie pas -- une trace, alors que le projet promet l'absence de trace.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TMP="$(mktemp -d)"
    DIR="$TMP/tree"
    mkdir -p "$DIR/config"
    cp "$ROOT/config/99-cleanup.zsh" "$DIR/config/"
    printf '# test module\nexport NIVUUS_TESTMOD=1\n' > "$DIR/config/50-test.zsh"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    printf '# user zshrc\n' > "$HOME/.zshrc"
    rm -f "$ROOT"/config/*.zwc
}

teardown() { chmod -R u+w "$DIR" 2>/dev/null || true; rm -rf "$TMP"; }

marker() { printf '%s\n' "$@" > "$DIR/.nivuus-origin"; }

cleanup_run() {
    NIVUUS_SHELL_DIR="$DIR" zsh -c "
        source '$DIR/config/99-cleanup.zsh'
    " >/dev/null 2>&1
    # La compilation des modules est lancée en tâche de fond (&!) : on
    # laisse le temps d'écrire avant de conclure à une absence.
    sleep 1
}

@test "a source install with a writable tree still compiles (no regression)" {
    cleanup_run
    [ -f "$DIR/config/50-test.zsh.zwc" ]
}

@test "INVARIANT: a package install compiles NOTHING in the shared tree" {
    marker 'origin=package' 'channel=deb'
    cleanup_run
    [ ! -f "$DIR/config/50-test.zsh.zwc" ]
    run find "$DIR" -name '*.zwc'
    [ -z "$output" ]
}

@test "a package install leaves no .zwc even when the tree IS writable" {
    # Le cas du shell root sur machine paquetée : l'écriture réussirait.
    marker 'origin=package' 'channel=aur'
    [ -w "$DIR/config" ]
    cleanup_run
    run find "$DIR" -name '*.zwc'
    [ -z "$output" ]
}

@test "a read-only tree compiles nothing, marker or not" {
    [ "$(id -u)" -ne 0 ] || skip "root écrit partout"
    chmod 500 "$DIR/config"
    cleanup_run
    chmod 700 "$DIR/config"
    run find "$DIR" -name '*.zwc'
    [ -z "$output" ]
}

@test "the user's own ~/.zshrc is still compiled in package mode" {
    # Ce fichier appartient à l'utilisateur dans TOUS les modes.
    marker 'origin=package' 'channel=homebrew'
    cleanup_run
    [ -f "$HOME/.zshrc.zwc" ]
}

@test "NIVUUS_NO_COMPILE=1 still disables everything" {
    NIVUUS_NO_COMPILE=1 NIVUUS_SHELL_DIR="$DIR" zsh -c "
        source '$DIR/config/99-cleanup.zsh'
    " >/dev/null 2>&1
    sleep 1
    run find "$DIR" "$HOME" -name '*.zwc'
    [ -z "$output" ]
}

@test "cleanup does not crash when config/20-autoupdate.zsh was never loaded" {
    # 99-cleanup doit être autonome : il ne peut pas présumer que
    # _nivuus_origin a été définie par un autre module.
    marker 'origin=package'
    run env NIVUUS_SHELL_DIR="$DIR" zsh -c "source '$DIR/config/99-cleanup.zsh'"
    [ "$status" -eq 0 ]
}
