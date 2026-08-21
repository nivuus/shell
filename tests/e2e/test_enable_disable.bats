#!/usr/bin/env bats
# L'activation est un acte PAR UTILISATEUR, et c'est le seul acte journalisé
# au manifeste quand l'arbre appartient à un gestionnaire de paquets.

load '../helpers/fingerprint'

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"
    # Arbre « partagé » posé à la main : aucun gestionnaire de paquets requis.
    SHARED="$TMP/share/nivuus-shell"
    mkdir -p "$SHARED"
    cp -a "$ROOT"/config "$ROOT"/themes "$ROOT"/lib "$ROOT"/bin "$ROOT"/keys "$SHARED"/ 2>/dev/null || true
    cp "$ROOT"/.zshrc "$SHARED"/
    printf '3.2.0\n' > "$SHARED/.version"
    NIVUUS="$SHARED/bin/nivuus"
}

teardown() { rm -rf "$TMP"; }

pkg_marker() {
    printf 'origin=package\nchannel=%s\npackage=nivuus-shell\nversion=3.2.0\n' \
        "${1:-deb}" > "$SHARED/.nivuus-origin"
}

@test "enable writes the block and nothing else" {
    pkg_marker
    run env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    [ "$status" -eq 0 ]
    grep -q '>>> nivuus shell >>>' "$HOME/.zshrc"
    grep -qF "$SHARED" "$HOME/.zshrc"
}

@test "enable copies NO tree: no CREATE entry points inside the shared tree" {
    # Écart au plan, justifié : sur un HOME sans ~/.zshrc, l'activation CRÉE
    # ce fichier, et c'est cette entrée CREATE qui rend « disable » réversible
    # (test « bit-identical even when ~/.zshrc did not exist » ci-dessous).
    # La propriété visée est « aucun CREATE dans l'arbre partagé », jamais
    # « aucun CREATE du tout ».
    pkg_marker
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    run awk -F'\t' '$1=="CREATE" { print $2 }' "$NIVUUS_STATE_DIR/manifest.tsv"
    for path in $output; do
        [[ "$path" != "$SHARED"* ]]
    done
}

@test "INVARIANT: enable then disable leaves HOME bit-identical" {
    pkg_marker
    printf 'export MINE=42\n' > "$HOME/.zshrc"
    fs_fingerprint "$HOME" > "$TMP/before"
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" disable --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "INVARIANT: enable then disable is bit-identical even when ~/.zshrc did not exist" {
    pkg_marker
    [ ! -f "$HOME/.zshrc" ]
    fs_fingerprint "$HOME" > "$TMP/before"
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" disable --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "disable never touches the shared tree" {
    pkg_marker
    fs_fingerprint "$SHARED" > "$TMP/tree_before"
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" disable --yes
    fs_fingerprint "$SHARED" > "$TMP/tree_after"
    run diff "$TMP/tree_before" "$TMP/tree_after"
    [ "$status" -eq 0 ]
}

@test "install on a package tree behaves as enable and says so" {
    pkg_marker homebrew
    run env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" install --yes
    [ "$status" -eq 0 ]
    grep -q '>>> nivuus shell >>>' "$HOME/.zshrc"
    # Aucun arbre recopié dans le HOME : le paquet possède déjà le sien.
    [ ! -d "$HOME/.nivuus-shell" ]
    [[ "$output" == *"activ"* ]]
}

@test "uninstall on a package tree says the shared files were not touched" {
    pkg_marker homebrew
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    run env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" uninstall --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"brew uninstall"* ]]
    [ -f "$SHARED/.zshrc" ]
}

@test "uninstall on a package tree never invokes the package manager" {
    # Appeler « sudo apt remove » depuis nivuus uninstall violerait la règle
    # « aucun sudo non demandé » au moment où l'utilisateur est le moins
    # attentif.
    run grep -nE 'sudo (apt|pacman|dpkg)|brew (uninstall|remove) [^"]*\$' "$ROOT/bin/nivuus"
    [ "$status" -ne 0 ]
}

@test "enable is idempotent: twice yields one block" {
    pkg_marker
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    run grep -c '>>> nivuus shell >>>' "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "enable in SOURCE mode works too (no tree copy, block only)" {
    # Utile pour ré-écrire un bloc perdu sans réinstaller l'arbre.
    rm -f "$SHARED/.nivuus-origin"
    run env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    [ "$status" -eq 0 ]
    grep -q '>>> nivuus shell >>>' "$HOME/.zshrc"
}

@test "disable with no manifest says so and exits 0" {
    pkg_marker
    run env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" disable --yes
    [ "$status" -eq 0 ]
}
