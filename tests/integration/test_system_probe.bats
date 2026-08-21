#!/usr/bin/env bats
#
# Une installation « réussie » que personne ne peut charger est le mode
# d'échec le plus coûteux de ce chantier : elle casse tous les shells de la
# machine APRÈS avoir affiché OK. On ne se croit donc pas sur parole -- on
# charge réellement l'arbre, depuis un environnement non privilégié.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    command -v zsh >/dev/null 2>&1 || skip "zsh indisponible"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/etc"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_UID=0 NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1
    export NIVUUS_SYSTEM_PROBE_USER=''      # sonder en tant que soi-même
}

teardown() { rm -rf "$TMP"; }

@test "un arbre sain passe la sonde" {
    "$ROOT/bin/nivuus" install --system --yes
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/detect.sh"; . "$ROOT/lib/system.sh"
    run nivuus_system_probe_tree "$TMP/usr/local/share/nivuus-shell"
    [ "$status" -eq 0 ]
}

@test "un arbre illisible échoue à la sonde" {
    "$ROOT/bin/nivuus" install --system --yes
    chmod 000 "$TMP/usr/local/share/nivuus-shell/.zshrc"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/detect.sh"; . "$ROOT/lib/system.sh"
    [ "$(id -u)" -ne 0 ] || skip "root lit tout : la sonde n'a de sens que non privilégiée"
    run nivuus_system_probe_tree "$TMP/usr/local/share/nivuus-shell"
    [ "$status" -ne 0 ]
}

@test "la sonde utilise un HOME jetable, jamais celui de quelqu'un" {
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/detect.sh"; . "$ROOT/lib/system.sh"
    "$ROOT/bin/nivuus" install --system --yes
    before="$(ls -A "$HOME" | wc -l)"
    nivuus_system_probe_tree "$TMP/usr/local/share/nivuus-shell"
    after="$(ls -A "$HOME" | wc -l)"
    [ "$before" -eq "$after" ]
}

# Un zsh qui démarre mais ne charge PAS l'arbre : c'est exactement ce que
# produisent un /usr/local monté noexec, un SELinux sans restorecon ou un
# umask hostile. On l'injecte par le zsh lui-même plutôt que par un mode
# 000 : un arbre illisible serait aussi illisible pour le ROLLBACK, qui ne
# peut pas empreindre ce qu'il ne peut pas lire et conserve alors le fichier
# (à raison). Le mode d'échec qu'on veut prouver ici est celui de
# l'INSTALLEUR -- « ce qui n'est pas prouvé n'est pas laissé en place » --
# et la détection, elle, est prouvée par les deux premiers tests.
fake_zsh_bin() {
    mkdir -p "$TMP/fakebin"
    printf '#!/bin/sh\nprintf "none\\n"\n' > "$TMP/fakebin/zsh"
    chmod 755 "$TMP/fakebin/zsh"
    printf '%s\n' "$TMP/fakebin"
}

@test "une installation dont la sonde échoue est ANNULÉE par le manifeste" {
    p="$(fake_zsh_bin)"
    run env PATH="$p:$PATH" "$ROOT/bin/nivuus" install --system --yes
    [ "$status" -ne 0 ]
    [[ "$output" == *"annulée"* ]] || [[ "$output" == *"Annul"* ]]
    # L'arbre a disparu : le manifeste a rejoué ses propres entrées.
    [ ! -f "$TMP/usr/local/share/nivuus-shell/config/00-core.zsh" ]
    [ ! -L "$TMP/usr/local/bin/nivuus" ]
}

@test "l'échec de sonde donne le diagnostic, pas seulement le verdict" {
    p="$(fake_zsh_bin)"
    run env PATH="$p:$PATH" "$ROOT/bin/nivuus" install --system --yes
    [[ "$output" == *"umask"* ]] || [[ "$output" == *"SELinux"* ]] || [[ "$output" == *"noexec"* ]]
}
