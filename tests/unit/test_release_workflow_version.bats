#!/usr/bin/env bats
#
# Le workflow de release est du YAML, pas du shell : on ne peut pas
# l'exécuter ici. On peut en revanche interdire mécaniquement les deux
# défauts qui l'ont cassé -- viser une variable qui n'existe pas, et ne
# jamais vérifier que les trois sources de version coïncident.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    WF="$ROOT/.github/workflows/release.yml"
}

@test "le workflow ne vise plus la variable VERSION= disparue d'install.sh" {
    run grep -n 's/\^VERSION=' "$WF"
    [ "$status" -ne 0 ]
}

@test "le workflow met à jour NIVUUS_PINNED_VERSION" {
    run grep -F 'NIVUUS_PINNED_VERSION' "$WF"
    [ "$status" -eq 0 ]
}

@test "le workflow met à jour .version" {
    run grep -nE '>[[:space:]]*\.version|\.version' "$WF"
    [ "$status" -eq 0 ]
}

@test "install.sh contient bien la variable que le workflow modifie" {
    run grep -nE '^NIVUUS_PINNED_VERSION="[0-9]+\.[0-9]+\.[0-9]+"$' "$ROOT/install.sh"
    [ "$status" -eq 0 ]
}

@test "les trois sources de version coïncident dans le dépôt" {
    v_file="$(cat "$ROOT/.version")"
    v_pkg="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$ROOT/package.json" | head -n1)"
    v_sh="$(sed -n 's/^NIVUUS_PINNED_VERSION="\(.*\)"/\1/p' "$ROOT/install.sh" | head -n1)"
    [ "$v_file" = "$v_pkg" ]
    [ "$v_file" = "$v_sh" ]
}

@test "les notes de release donnent le vrai one-liner" {
    run grep -F 'raw.githubusercontent.com' "$WF"
    [ "$status" -eq 0 ]
    run grep -F '| bash' "$WF"
    [ "$status" -ne 0 ]     # le one-liner s'exécute avec sh, pas bash
}
