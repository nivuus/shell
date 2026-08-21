#!/usr/bin/env bats
# En mode paquet, la mise à jour automatique est désactivée. Sans exception,
# sans variable d'échappement, et même contre ENABLE_AUTOUPDATE=true.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TMP="$(mktemp -d)"
    DIR="$TMP/tree"
    mkdir -p "$DIR/config"
    cp "$ROOT/config/20-autoupdate.zsh" "$DIR/config/"
    export HOME="$TMP/home"
    mkdir -p "$HOME"
    # Le bytecode périmé masque la source : il ferait passer (ou échouer) ce
    # test contre une version qui n'est pas celle qu'on modifie.
    rm -f "$ROOT"/config/*.zwc
}

teardown() { rm -rf "$TMP"; }

marker() { printf '%s\n' "$@" > "$DIR/.nivuus-origin"; }

# Charge le module avec l'auto-update DÉSACTIVÉ, puis évalue une expression.
probe() {
    NIVUUS_SHELL_DIR="$DIR" zsh -c "
        ENABLE_AUTOUPDATE=false
        source '$DIR/config/20-autoupdate.zsh'
        $1
    "
}

@test "no marker: origin is source" {
    run probe '_nivuus_origin'
    [ "$output" = "source" ]
}

@test "no marker: not a package install" {
    run probe '_nivuus_is_package_install && print yes || print no'
    [ "$output" = "no" ]
}

@test "origin=package: recognised as a package install" {
    marker 'origin=package' 'channel=deb'
    run probe '_nivuus_is_package_install && print yes || print no'
    [ "$output" = "yes" ]
}

@test "an unknown origin value is NOT a package install" {
    marker 'origin=chaussette'
    run probe '_nivuus_is_package_install && print yes || print no'
    [ "$output" = "no" ]
}

@test "the channel is readable from zsh too" {
    marker 'origin=package' 'channel=homebrew'
    run probe '_nivuus_origin_channel'
    [ "$output" = "homebrew" ]
}

@test "INVARIANT: a package install never schedules an async update check" {
    # La preuve observable : le fichier d'horodatage n'est jamais écrit.
    # S'il apparaît, c'est que _nivuus_check_update_async a tourné -- donc
    # que l'updater destructif a pu partir contre un arbre appartenant à
    # dpkg / pacman / brew.
    marker 'origin=package' 'channel=deb'
    NIVUUS_SHELL_DIR="$DIR" zsh -c "
        ENABLE_AUTOUPDATE=true
        AUTOUPDATE_CHECK_FREQUENCY_DAYS=0
        source '$DIR/config/20-autoupdate.zsh'
    " >/dev/null 2>&1
    sleep 1   # laisse une éventuelle tâche &! le temps d'écrire
    [ ! -f "$HOME/.nivuus-shell-last-update-check" ]
}

@test "INVARIANT: the package rule wins over ENABLE_AUTOUPDATE=true" {
    # Corollaire assumé de la spec § 1.1 : il n'existe aucune façon
    # d'honorer ce réglage qui ne produise pas un système incohérent.
    marker 'origin=package' 'channel=homebrew'
    NIVUUS_SHELL_DIR="$DIR" zsh -c "
        ENABLE_AUTOUPDATE=true
        AUTOUPDATE_CHECK_FREQUENCY_DAYS=0
        source '$DIR/config/20-autoupdate.zsh'
    " >/dev/null 2>&1
    sleep 1
    [ ! -f "$HOME/.nivuus-shell-last-update-check" ]
}

@test "a SOURCE install still schedules the check (no regression on the main path)" {
    # Le canal principal ne doit voir strictement aucun changement.
    NIVUUS_SHELL_DIR="$DIR" zsh -c "
        ENABLE_AUTOUPDATE=true
        AUTOUPDATE_CHECK_FREQUENCY_DAYS=0
        NIVUUS_GITHUB_API='http://127.0.0.1:9'
        source '$DIR/config/20-autoupdate.zsh'
    " >/dev/null 2>&1
    sleep 2
    [ -f "$HOME/.nivuus-shell-last-update-check" ]
}

@test "there is NO escape hatch variable for package mode" {
    # Toute variable qui rétablirait l'auto-update en mode paquet
    # réintroduirait l'échec silencieux hebdomadaire que ce chantier ferme.
    run grep -nE 'NIVUUS_(FORCE|ALLOW)_(PACKAGE_)?UPDATE' "$ROOT/config/20-autoupdate.zsh"
    [ "$status" -ne 0 ]
}

@test "reading the marker costs no fork when it is absent" {
    # Le chemin de démarrage de 100% des installations existantes : le
    # [[ -r ]] échoue et on ne doit PAS avoir lancé sed.
    run probe '_nivuus_origin'
    [ "$output" = "source" ]
    # Le corps de la fonction doit sortir avant tout appel externe.
    run grep -A3 '_nivuus_origin()' "$ROOT/config/20-autoupdate.zsh"
    [[ "$output" == *'[[ -r'* ]]
}
