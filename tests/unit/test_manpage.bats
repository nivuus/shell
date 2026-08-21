#!/usr/bin/env bats

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    MAN="$ROOT/doc/nivuus.1"
}

@test "the man page exists" { [ -f "$MAN" ]; }

@test "the man page is section 1 and names the command" {
    head -n5 "$MAN" | grep -q '^\.TH NIVUUS 1'
}

@test "the man page renders without groff warnings" {
    # Écart au plan, justifié : -Tascii ne sait rendre AUCUN caractère
    # accentué (« special character not defined » sur chaque é, à, ç), et la
    # documentation du projet est en français. -Tutf8 -k (preconv) est la
    # sortie réelle de « man » sur une locale UTF-8 ; c'est elle qu'on vérifie.
    command -v groff >/dev/null || skip "groff absent"
    run groff -man -Tutf8 -ww -k "$MAN"
    [ "$status" -eq 0 ]
    [[ "$output" != *"warning"* ]]
}

@test "every subcommand of nivuus help is documented in the man page" {
    # Le garde-fou anti-dérive : une sous-commande ajoutée sans sa ligne de
    # manuel fait échouer ce test, pas un rapport d'utilisateur six mois plus tard.
    for cmd in install uninstall enable disable migrate update doctor help; do
        grep -q "^\.B $cmd$" "$MAN" || {
            echo "sous-commande absente du manuel : $cmd"
            return 1
        }
    done
}

@test "the man page documents that package installs disable auto-update" {
    grep -qi 'paquet' "$MAN"
    grep -q 'nivuus enable' "$MAN"
}

@test "the man page is copied into an installed tree" {
    grep -q 'nivuus.1' "$ROOT/lib/steps.sh"
}
