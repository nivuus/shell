#!/usr/bin/env bats
#
# Nivuus enregistre des hooks, des widgets ZLE et des precmd : les charger
# deux fois les DOUBLE. La garde qui l'empêche doit être locale au
# processus -- une variable exportée désactiverait Nivuus dans tout zsh
# imbriqué, ce qui est pire que le problème qu'elle résout.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    command -v zsh >/dev/null 2>&1 || skip "zsh indisponible"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    rm -f "$ROOT"/config/*.zwc "$ROOT/.zshrc.zwc"
}

teardown() { rm -rf "$TMP"; }

# NIVUUS_SHELL_DIR est EXPORTÉ ici, délibérément : c'est ce qui permet au
# zsh imbriqué du test « la garde ne fuit pas » de retrouver l'arbre sans
# qu'on le lui repasse -- exactement comme dans une vraie session.
zrun() { zsh -c "export NIVUUS_SHELL_DIR='$ROOT' ENABLE_AUTOUPDATE=false; $1"; }

@test "sourcer deux fois ne charge qu'une fois" {
    run zrun 'source $NIVUUS_SHELL_DIR/.zshrc >/dev/null 2>&1
              source $NIVUUS_SHELL_DIR/.zshrc >/dev/null 2>&1
              print -r -- "$_nivuus_load_count"'
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = "1" ]
}

@test "les deux tentatives sont bien comptées (le test précédent ne triche pas)" {
    run zrun 'source $NIVUUS_SHELL_DIR/.zshrc >/dev/null 2>&1
              source $NIVUUS_SHELL_DIR/.zshrc >/dev/null 2>&1
              print -r -- "$_nivuus_source_attempts"'
    [ "${lines[-1]}" = "2" ]
}

@test "INVARIANT: la garde n'est PAS exportée" {
    # Le mode d'échec qu'on refuse : un zsh imbriqué qui hériterait de la
    # garde démarrerait SANS Nivuus, en silence et pour toujours.
    run zrun 'source $NIVUUS_SHELL_DIR/.zshrc >/dev/null 2>&1
              print -r -- "${(t)_nivuus_sourced}"'
    [[ "${lines[-1]}" != *"export"* ]]
}

@test "INVARIANT: un zsh imbriqué charge bien Nivuus (la garde ne fuit pas)" {
    run zrun 'source $NIVUUS_SHELL_DIR/.zshrc >/dev/null 2>&1
              zsh -c "source \$NIVUUS_SHELL_DIR/.zshrc >/dev/null 2>&1
                      print -r -- \$_nivuus_load_count"'
    [ "${lines[-1]}" = "1" ]
}

@test "NIVUUS_SHELL_LOADED reste exportée (on ne l'a pas détournée)" {
    run zrun 'source $NIVUUS_SHELL_DIR/.zshrc >/dev/null 2>&1
              print -r -- "${(t)NIVUUS_SHELL_LOADED}"'
    [[ "${lines[-1]}" == *"export"* ]]
}

@test "la garde n'ajoute aucun fork au démarrage" {
    # Deux affectations arithmétiques, rien d'autre : ni command -v, ni test
    # de fichier, ni sous-shell. Le budget de 300 ms est un test bloquant du
    # projet ; une substitution de commande en tête de .zshrc serait un fork
    # sur le chemin de démarrage de CHAQUE shell.
    run head -n 30 "$ROOT/.zshrc"
    [[ "$output" != *'$('* ]]
    [[ "$output" == *"_nivuus_sourced"* ]]
}
