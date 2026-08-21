#!/usr/bin/env bats
#
# « Nivuus n'exécute jamais un sudo que l'utilisateur n'a pas demandé » ne
# devient pas faux parce que le mode entier suppose du root : le mode
# EXIGE le privilège, il ne l'ACQUIERT jamais. Ces tests tiennent la
# distinction, sans jamais être root.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local" NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/detect.sh"; . "$ROOT/lib/system.sh"
}

teardown() { rm -rf "$TMP"; }

@test "sans root, le refus arrive AVANT toute écriture" {
    NIVUUS_UID=1000 run nivuus_system_require_root "installer pour la machine"
    [ "$status" -ne 0 ]
    # Rien n'a été créé : c'est la moitié la plus importante de l'assertion.
    [ ! -e "$TMP/usr" ]
    [ ! -e "$TMP/var" ]
    [ ! -e "$TMP/etc" ]
}

@test "le refus donne la commande exacte à taper" {
    NIVUUS_UID=1000 run nivuus_system_require_root "installer pour la machine"
    [[ "$output" == *"sudo nivuus install --system"* ]]
}

@test "INVARIANT: Nivuus ne se ré-exécute JAMAIS sous sudo tout seul" {
    # Le mode d'échec qu'on refuse par principe : un « exec sudo $0 » qui
    # élèverait le privilège au nom de l'utilisateur. Le grep couvre
    # lib/system.sh, bin/nivuus et install.sh d'un coup.
    run grep -rnE '(exec|sh|bash)[[:space:]]+sudo|sudo[[:space:]]+"?\$0' \
        "$ROOT/lib/" "$ROOT/bin/nivuus" "$ROOT/install.sh"
    [ "$status" -ne 0 ]
}

@test "avec root, la fonction laisse passer sans rien dire" {
    NIVUUS_UID=0 run nivuus_system_require_root "installer pour la machine"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "nivuus_system_is_root lit NIVUUS_UID quand il est posé" {
    NIVUUS_UID=0    run nivuus_system_is_root; [ "$status" -eq 0 ]
    NIVUUS_UID=1000 run nivuus_system_is_root; [ "$status" -ne 0 ]
}
