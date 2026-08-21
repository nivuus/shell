#!/usr/bin/env bats
#
# Les métadonnées du dépôt sont ce que voient tous ceux qui ne cliquent pas.
# Comme tout le reste ici, elles vivent dans un fichier versionné, pas dans
# une UI web où personne ne peut ni les relire ni les tester.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    PKG="$ROOT/package.json"
    META="$ROOT/tools/repo-meta.sh"
}

@test "tools/repo-meta.sh existe, est exécutable et POSIX" {
    [ -x "$META" ]
    run sh -n "$META"
    [ "$status" -eq 0 ]
}

@test "le script lit package.json et n'écrit aucune valeur en dur" {
    grep -qF 'package.json' "$META"
    # Une description en dur dans le script serait une deuxième source de
    # vérité, donc une divergence programmée.
    run grep -nE '^[[:space:]]*DESCRIPTION="[A-Z]' "$META"
    [ "$status" -ne 0 ]
}

@test "la description du dépôt est la promesse, pas un générique" {
    d="$(sed -n 's/.*"description": "\(.*\)",*/\1/p' "$PKG" | head -n1)"
    [ -n "$d" ]
    printf '%s' "$d" | grep -qi 'uninstall\|remove' \
        || { echo "la description ne porte pas la promesse : $d"; false; }
    # GitHub tronque au-delà de ~350 caractères ; une description qu'on ne
    # lit pas en entier est une description ratée.
    [ "${#d}" -le 200 ]
}

@test "les topics couvrent les entrées par lesquelles on cherche cet outil" {
    for t in zsh shell dotfiles prompt cli ai; do
        grep -qF "\"$t\"" "$PKG" || { echo "topic absent de package.json : $t"; false; }
    done
}

@test "le script refuse de tourner sans gh, au lieu d'échouer à mi-course" {
    grep -qE 'command -v gh' "$META"
}

@test "le script rappelle ce que gh NE PEUT PAS faire" {
    # L'image sociale ne se pose pas par API : la seule action manuelle du
    # chantier doit être écrite là où on la cherchera.
    grep -qiE 'social' "$META"
}
