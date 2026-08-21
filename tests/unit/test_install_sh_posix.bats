#!/usr/bin/env bats
#
# install.sh est le SEUL fichier du dépôt qui doit tourner sous le shell que
# l'utilisateur a, pas sous celui qu'on aimerait qu'il ait : « curl | sh »
# ne choisit pas. Ce test interdit mécaniquement les bashismes et exécute
# réellement le fichier sous les shells POSIX disponibles.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    SH="$ROOT/install.sh"
    TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

@test "le shebang est /bin/sh" {
    run head -n1 "$SH"
    [ "$output" = "#!/bin/sh" ]
}

@test "aucun bashisme dans install.sh" {
    # Motifs choisis pour ne produire aucun faux positif sur ce fichier :
    # chacun est soit inexistant en POSIX, soit un piège avéré sous dash/ash.
    run grep -nE 'BASH_SOURCE|\blocal\b|\[\[|\]\]|\+=|<<<|\bfunction\b|pipefail|echo -e|\$\{[A-Za-z_]+\[' "$SH"
    [ "$status" -ne 0 ]
}

@test "install.sh passe le contrôle syntaxique de dash" {
    command -v dash >/dev/null 2>&1 || skip "dash indisponible"
    run dash -n "$SH"
    [ "$status" -eq 0 ]
}

@test "install.sh passe le contrôle syntaxique de busybox ash" {
    command -v busybox >/dev/null 2>&1 || skip "busybox indisponible"
    run busybox ash -n "$SH"
    [ "$status" -eq 0 ]
}

@test "install.sh --help fonctionne sous sh, dash et bash" {
    for shell in sh dash bash; do
        command -v "$shell" >/dev/null 2>&1 || continue
        run "$shell" "$SH" --help
        [ "$status" -eq 0 ]
        [[ "$output" == *"sage"* ]]
    done
}

@test "install.sh --dry-run n'écrit rien, lancé par dash" {
    command -v dash >/dev/null 2>&1 || skip "dash indisponible"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
    run dash "$SH" --non-interactive --dry-run --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ ! -e "$TMP/target" ]
}

@test "une copie isolée d'install.sh ne se croit PAS en mode voisin" {
    # Le fichier seul, sans bin/nivuus à côté : il doit basculer en amorçage
    # (qui, sans release atteignable, échoue avec un message explicite) et
    # surtout PAS installer quoi que ce soit depuis le répertoire courant.
    cp "$SH" "$TMP/install.sh"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    run env NIVUUS_RELEASE_BASE_URL="file://$TMP/vide" NIVUUS_GITHUB_API="file://$TMP/vide" \
        sh "$TMP/install.sh" --non-interactive --prefix "$TMP/target"
    [ "$status" -ne 0 ]
    [ ! -e "$TMP/target" ]
}
