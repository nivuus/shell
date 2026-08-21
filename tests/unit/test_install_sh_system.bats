#!/usr/bin/env bats
#
# install.sh ne connaît pas le mode système : il le TRANSMET. Toute logique
# de mode qui remonterait dans ce fichier serait un second endroit où la
# décision se prend -- exactement ce que le refus historique était.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    SH="$ROOT/install.sh"
    TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

@test "install.sh ne contient plus le message « pas encore disponible »" {
    run grep -n "pas encore disponible" "$SH"
    [ "$status" -ne 0 ]
}

@test "install.sh ne décide RIEN du mode système (il ne fait que traduire)" {
    # Aucun chemin système en dur dans le script d'amorçage : les chemins
    # vivent dans lib/system.sh, un seul endroit.
    run grep -nE '/usr/local/share/nivuus-shell|/var/lib/nivuus|/etc/skel' "$SH"
    [ "$status" -ne 0 ]
}

@test "--system est transmis au noyau voisin" {
    mkdir -p "$TMP/bin" "$TMP/lib"
    cp "$SH" "$TMP/install.sh"
    printf '' > "$TMP/lib/manifest.sh"
    # Faux noyau : il journalise ses arguments et ne fait rien d'autre.
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/args"\n' "$TMP" > "$TMP/bin/nivuus"
    chmod +x "$TMP/bin/nivuus"
    run sh "$TMP/install.sh" --system --non-interactive
    [ "$status" -eq 0 ]
    grep -qx -- "--system" "$TMP/args"
    grep -qx -- "--yes" "$TMP/args"
}

@test "--system --dry-run est transmis lui aussi" {
    mkdir -p "$TMP/bin" "$TMP/lib"
    cp "$SH" "$TMP/install.sh"; printf '' > "$TMP/lib/manifest.sh"
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/args"\n' "$TMP" > "$TMP/bin/nivuus"
    chmod +x "$TMP/bin/nivuus"
    run sh "$TMP/install.sh" --system --dry-run
    [ "$status" -eq 0 ]
    grep -qx -- "--system" "$TMP/args"
    grep -qx -- "--dry-run" "$TMP/args"
}

@test "l'aide décrit --system au lieu de le démentir" {
    run sh "$SH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--system"* ]]
    [[ "$output" != *"Indisponible"* ]]
}

@test "install.sh reste POSIX après la modification" {
    run grep -nE 'BASH_SOURCE|\blocal\b|\[\[|\]\]|\+=|<<<|pipefail' "$SH"
    [ "$status" -ne 0 ]
    command -v dash >/dev/null 2>&1 && dash -n "$SH"
    command -v busybox >/dev/null 2>&1 && busybox ash -n "$SH"
    true
}
