# shellcheck shell=bash
# tests/helpers/pty.bash
# Exécute du code zsh derrière un vrai pseudo-terminal.
#
# Pourquoi : la config distingue « un humain devant un terminal » de « un
# script, une CI, un shell d'agent » avec `[[ -t 2 ]]` (voir
# nivuus_has_terminal dans config/00-core.zsh). `zsh -ic` ne suffit PAS à
# simuler le premier cas : bats capture la sortie dans un tuyau, donc fd 2
# n'est pas un terminal même si l'option `interactive` est posée. C'est
# exactement la confusion que nivuus_has_terminal existe pour corriger, et un
# test qui utilise `zsh -ic` comme proxy réintroduit le bug côté test.
#
# LIMITE CONNUE : `script` normalise les fins de ligne en CRLF, d'où le
# `tr -d '\r'`. Les codes de sortie transitent par `script -e`, disponible sur
# util-linux ; sur BSD/macOS la signature diffère et ce helper ne marchera pas
# en l'état.

# pty_run <code zsh>
#
# Peuple $output et $status comme `run`, mais avec un terminal sur les trois
# descripteurs standard.
pty_run() {
    local code="$1" raw
    # --no-rcs : le test source explicitement les modules qu'il vise. Sans ça,
    # `zsh -i` chargerait le ~/.zshrc réel de la machine et le test mesurerait
    # la config de l'utilisateur au lieu de la sienne.
    #
    # Pas de tuyau sur cette ligne : $? doit être celui de `script -e`, donc
    # celui du zsh fils. Le nettoyage vient après, sur la variable.
    #
    # Le `|| status=$?` n'est pas décoratif : bats tourne sous `set -e`, et une
    # affectation dont la substitution échoue interromprait la fonction avant
    # qu'on ait pu lire le code. Ici l'échec est justement ce qu'on mesure.
    raw="$(script -qec "zsh --no-rcs -ic $(printf '%q' "$code")" /dev/null 2>/dev/null)" && status=0 || status=$?
    # Le titre de terminal (OSC 0) est émis par config/20-terminal-title.zsh
    # dès qu'un terminal est présent : c'est du bruit attendu ici, pas un
    # résultat, donc on le retire pour que les assertions portent sur la sortie.
    output="$(printf '%s' "$raw" | tr -d '\r' | sed $'s/\033\][0-9];[^\007]*\007//g')"
    export output status
    # Comme `run`, pty_run réussit toujours : le verdict appartient au test,
    # qui lit $status. Sans ça, `set -e` couperait le test avant l'assertion.
    return 0
}
