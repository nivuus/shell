#!/usr/bin/env bats
# Garde-fou secondaire, INDÉPENDANT du marqueur : un arbre que l'utilisateur
# courant ne peut pas écrire n'est jamais réécrit par l'updater.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TMP="$(mktemp -d)"
    DIR="$TMP/tree"
    mkdir -p "$DIR/config"
    cp "$ROOT/config/20-autoupdate.zsh" "$DIR/config/"
    printf '3.0.0\n' > "$DIR/.version"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    rm -f "$ROOT"/config/*.zwc
}

teardown() { chmod -R u+w "$DIR" 2>/dev/null || true; rm -rf "$TMP"; }

perform() {
    NIVUUS_SHELL_DIR="$DIR" zsh -c "
        ENABLE_AUTOUPDATE=false
        source '$DIR/config/20-autoupdate.zsh'
        _nivuus_perform_update 9.9.9
    " 2>&1
}

@test "a read-only tree makes the destructive update refuse" {
    [ "$(id -u)" -ne 0 ] || skip "root écrit partout : c'est le marqueur qui couvre ce cas"
    chmod 500 "$DIR"
    run perform
    [ "$status" -ne 0 ]
    [[ "$output" == *"$DIR"* ]]
}

@test "the refusal names the tree and does not pretend to have updated" {
    [ "$(id -u)" -ne 0 ] || skip "root écrit partout"
    chmod 500 "$DIR"
    run perform
    [[ "$output" != *"Restart your shell"* ]]
}

@test "the refusal happens BEFORE any download or backup" {
    # Un refus doit être gratuit : ni tarball téléchargé, ni copie de ~50 Mo.
    [ "$(id -u)" -ne 0 ] || skip "root écrit partout"
    chmod 500 "$DIR"
    run perform
    [[ "$output" != *"Backup created"* ]]
    [ ! -d "$HOME/.nivuus-backups" ]
}

@test "the guard does not depend on the marker (no marker, read-only tree)" {
    # C'est LE cas visé : un tiers empaquette sans poser .nivuus-origin.
    [ "$(id -u)" -ne 0 ] || skip "root écrit partout"
    [ ! -f "$DIR/.nivuus-origin" ]
    chmod 500 "$DIR"
    run perform
    [ "$status" -ne 0 ]
}

@test "a writable tree is NOT refused by this guard" {
    # Preuve que le garde-fou ne bloque pas le canal principal : on échoue
    # plus loin (réseau injoignable), pas sur l'inscriptibilité.
    run env NIVUUS_SHELL_DIR="$DIR" zsh -c "
        ENABLE_AUTOUPDATE=false
        NIVUUS_GITHUB_API='http://127.0.0.1:9'
        source '$DIR/config/20-autoupdate.zsh'
        _nivuus_perform_update 9.9.9
    "
    [[ "$output" != *"lecture seule"* ]]
    [[ "$output" != *"read-only"* ]]
}
