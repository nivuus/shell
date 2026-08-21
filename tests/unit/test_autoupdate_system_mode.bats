#!/usr/bin/env bats
#
# Un updater destructif ne doit pas s'exécuter là où il détruirait autre
# chose que lui-même. Sur un arbre système, il écrirait en root, hors
# manifeste, dans le domaine root -- ou échouerait silencieusement chaque
# semaine dans le shell de chaque utilisateur.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    command -v zsh >/dev/null 2>&1 || skip "zsh indisponible"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    mkdir -p "$TMP/tree"
    cp -r "$ROOT/config" "$TMP/tree/"
    rm -f "$TMP"/tree/config/*.zwc
    printf 'origin=system\nchannel=selfhosted\nprefix=%s\nversion=3.1.4\n' "$TMP/tree" \
        > "$TMP/tree/.nivuus-origin"
}

teardown() { rm -rf "$TMP"; }

zsrc() { zsh -c "NIVUUS_SHELL_DIR='$TMP/tree' ENABLE_AUTOUPDATE=false
                 source '$TMP/tree/config/20-autoupdate.zsh'; $1"; }

@test "_nivuus_origin lit system dans le marqueur" {
    run zsrc 'print -r -- "$(_nivuus_origin)"'
    [ "${lines[-1]}" = "system" ]
}

@test "l'absence de marqueur vaut toujours source (aucune installation existante ne change)" {
    rm -f "$TMP/tree/.nivuus-origin"
    run zsrc 'print -r -- "$(_nivuus_origin)"'
    [ "${lines[-1]}" = "source" ]
}

@test "origin=system n'est PAS un paquet (le message diffère, la décision non)" {
    run zsrc 'print -r -- "$(_nivuus_is_package_install && print oui || print non)"'
    [ "${lines[-1]}" = "non" ]
    run zsrc 'print -r -- "$(_nivuus_is_managed_install && print oui || print non)"'
    [ "${lines[-1]}" = "oui" ]
}

@test "INVARIANT: aucune sonde de mise à jour dans un shell sur arbre système" {
    run zsh -c "NIVUUS_SHELL_DIR='$TMP/tree' ENABLE_AUTOUPDATE=true
                source '$TMP/tree/config/20-autoupdate.zsh'
                print -r -- done"
    [ "$status" -eq 0 ]
    # La sonde observable : le fichier d'horodatage n'est jamais écrit.
    [ ! -f "$HOME/.nivuus-shell-last-update-check" ]
}

@test "nivuus-update sort en 0 et donne la commande de l'administrateur" {
    run zsrc 'nivuus-update'
    [ "$status" -eq 0 ]
    [[ "$output" == *"sudo nivuus update"* ]]
    [[ "$output" == *"$TMP/tree"* ]]
}

@test "le message nomme aussi la sortie vers une installation personnelle" {
    run zsrc 'nivuus-update'
    [[ "$output" == *"install.sh"* ]]
}

@test "le message est DÉRIVÉ de origin, pas deviné : channel apparaît" {
    run zsrc 'print -r -- "$(_nivuus_origin_channel)"'
    [ "${lines[-1]}" = "selfhosted" ]
}

@test "en mode source, rien ne change (non-régression du chemin historique)" {
    rm -f "$TMP/tree/.nivuus-origin"
    run zsrc 'print -r -- "$(_nivuus_is_managed_install && print oui || print non)"'
    [ "${lines[-1]}" = "non" ]
}

@test "INVARIANT: un shell ROOT sur arbre système ne compile aucun .zwc dans l'arbre" {
    # Le cas où l'écriture RÉUSSIRAIT : l'arbre est inscriptible. Des .zwc
    # orphelins y seraient une trace qu'aucune désinstallation ne connaît.
    [ -w "$TMP/tree/config" ]
    zsh -c "NIVUUS_SHELL_DIR='$TMP/tree' ENABLE_AUTOUPDATE=false
            source '$TMP/tree/config/99-cleanup.zsh'" >/dev/null 2>&1 || true
    sleep 2      # la compilation est lancée en arrière-plan (&!)
    run find "$TMP/tree" -name '*.zwc'
    [ -z "$output" ]
}
