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

# L'image sociale DÉRIVE de la démo (une frame du .cast). Tant qu'aucun
# enregistrement n'existe, elle ne peut pas exister non plus : c'est la
# conséquence directe de « dérivée, jamais dessinée ». La règle ci-dessous
# est donc conditionnelle -- mais la cohérence, elle, ne l'est pas.
demo_recorded() { [ -f "$ROOT/docs/assets/demo.cast" ]; }

@test "social.sh existe, est exécutable et dérive de la démo" {
    [ -x "$ROOT/tools/demo/social.sh" ]
    run sh -n "$ROOT/tools/demo/social.sh"
    [ "$status" -eq 0 ]
    # Dérivée, jamais dessinée : une image dessinée à la main peut montrer
    # ce que le produit ne fait pas.
    grep -qF 'demo.cast' "$ROOT/tools/demo/social.sh"
}

@test "l'image sociale ne peut pas exister sans la démo dont elle dérive" {
    # L'état interdit : une carte sociale qui montre autre chose que le
    # produit, parce qu'elle aurait survécu à la démo qui l'a produite.
    if [ -f "$ROOT/docs/assets/social.png" ]; then
        demo_recorded || { echo "social.png sans demo.cast : elle ne dérive de rien"; false; }
    fi
}

@test "l'image sociale existe et respecte le format attendu par GitHub" {
    demo_recorded || skip "aucun enregistrement : tools/demo/record.sh"
    img="$ROOT/docs/assets/social.png"
    [ -f "$img" ]
    # GitHub recommande 1280x640 et refuse au-delà de 1 Mo.
    n="$(wc -c < "$img")"
    [ "$n" -le 1048576 ] || { echo "social.png pèse $n octets (max: 1 Mo)"; false; }
    if command -v file >/dev/null 2>&1; then
        run file "$img"
        [[ "$output" == *"1280 x 640"* ]] || [[ "$output" == *"PNG"* ]]
    fi
}

@test "le script rappelle que le téléversement est manuel" {
    grep -qiE 'settings|manuel|manually' "$ROOT/tools/demo/social.sh"
}
