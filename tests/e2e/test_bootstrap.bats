#!/usr/bin/env bats
#
# La porte d'entrée, dans sa forme littérale : le script est LU sur stdin
# par sh, comme le fait « curl … | sh ». Aucun réseau : la release est
# fabriquée sur disque et servie par file://.

load '../helpers/fingerprint'
load '../helpers/release'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"
    export TMPDIR="$TMP/tmp"; mkdir -p "$TMPDIR"
    make_release "$ROOT" "$TMP/releases" 9.9.9
    make_release_api "$TMP/api" fake/nivuus 9.9.9
    export NIVUUS_RELEASE_BASE_URL="file://$TMP/releases"
    export NIVUUS_GITHUB_API="file://$TMP/api"
    export NIVUUS_GITHUB_REPO="fake/nivuus"
}

teardown() { rm -rf "$TMP"; }

# Exactement la forme du README : le script est LU sur stdin par sh.
one_liner() {
    cat "$ROOT/install.sh" | env \
        HOME="$HOME" TMPDIR="$TMPDIR" NIVUUS_STATE_DIR="$NIVUUS_STATE_DIR" \
        NIVUUS_RELEASE_BASE_URL="$NIVUUS_RELEASE_BASE_URL" \
        NIVUUS_GITHUB_API="$NIVUUS_GITHUB_API" NIVUUS_GITHUB_REPO="$NIVUUS_GITHUB_REPO" \
        sh -s -- "$@"
}

@test "le one-liner installe depuis zéro" {
    run one_liner --non-interactive
    [ "$status" -eq 0 ]
    [ -f "$HOME/.nivuus-shell/config/00-core.zsh" ]
    [ -f "$HOME/.nivuus-shell/bin/nivuus" ]
    [ -f "$HOME/.zshrc" ]
    run grep -c '>>> nivuus shell >>>' "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "le one-liner sans arguments du tout fonctionne aussi" {
    # Forme littérale du README : « curl … | sh », zéro option. Sans TTY,
    # l'amorçage doit ajouter --yes de lui-même plutôt que de bloquer.
    run one_liner
    [ "$status" -eq 0 ]
    [ -f "$HOME/.nivuus-shell/config/00-core.zsh" ]
}

@test "le shell démarre après le one-liner" {
    one_liner --non-interactive
    run env HOME="$HOME" zsh -ic 'echo NIVUUS_OK'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NIVUUS_OK"* ]]
}

@test "INVARIANT: aucun dépôt git derrière le one-liner" {
    one_liner --non-interactive
    [ ! -e "$HOME/.nivuus-shell/.git" ]
    run find "$HOME" -maxdepth 4 -name '.git'
    [ -z "$output" ]
}

@test "INVARIANT: aucun temporaire derrière le one-liner" {
    one_liner --non-interactive
    run find "$TMPDIR" -maxdepth 1 -mindepth 1
    [ -z "$output" ]
}

@test "INVARIANT: one-liner puis uninstall --purge laisse HOME bit-identique" {
    fs_fingerprint "$HOME" > "$TMP/before"
    one_liner --non-interactive
    run "$HOME/.nivuus-shell/bin/nivuus" uninstall --yes --purge
    [ "$status" -eq 0 ]
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "la désinstallation est atteignable sans se souvenir d'un chemin" {
    # bin/nivuus est dans le PATH une fois le shell chargé.
    one_liner --non-interactive
    run env HOME="$HOME" zsh -ic 'command -v nivuus'
    [ "$status" -eq 0 ]
    [[ "$output" == *"nivuus"* ]]
}

@test "INVARIANT: archive falsifiée -> rien d'installé, HOME intact" {
    fs_fingerprint "$HOME" > "$TMP/before"
    tamper_release "$TMP/releases" 9.9.9
    run one_liner --non-interactive
    [ "$status" -ne 0 ]
    [ ! -e "$HOME/.nivuus-shell" ]
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "le one-liner honore --dry-run" {
    fs_fingerprint "$HOME" > "$TMP/before"
    run one_liner --non-interactive --dry-run
    [ "$status" -eq 0 ]
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "le one-liner honore --minimal" {
    run one_liner --non-interactive --minimal
    [ "$status" -eq 0 ]
    run grep -c 'NIVUUS_MINIMAL=1' "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "le one-liner honore --prefix, y compris avec un espace" {
    run one_liner --non-interactive --prefix "$HOME/mon dossier"
    [ "$status" -eq 0 ]
    [ -f "$HOME/mon dossier/config/00-core.zsh" ]
}

@test "le one-liner transmet --verify-key au noyau" {
    # Point de contact avec le chantier « signature » : l'option doit
    # traverser l'amorçage, pas seulement le mode voisin.
    [ -d "$ROOT/keys" ] || skip "keys/ absent (chantier signature non mergé)"
    run one_liner --non-interactive --verify-key "cafecafecafecafe"
    [ "$status" -ne 0 ]
    [ ! -e "$HOME/.nivuus-shell" ]
}
