#!/usr/bin/env bats
#
# « --system est redondant à ~90 % sur Debian/Ubuntu » est une conclusion de
# la spec. Une conclusion qui ne change pas le comportement de l'outil n'a
# servi à rien : ce test est la forme exécutable de cette phrase.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export NIVUUS_OS_RELEASE="$TMP/os-release"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/detect.sh"; . "$ROOT/lib/system.sh"
}

teardown() { rm -rf "$TMP"; }

@test "sur Debian, le message nomme le paquet et ce que dpkg apporte en plus" {
    printf 'ID=debian\n' > "$TMP/os-release"
    run nivuus_system_package_notice
    [ "$status" -eq 0 ]
    [[ "$output" == *"apt install"* ]]
    [[ "$output" == *"dpkg"* ]]
}

@test "sur Ubuntu (ID_LIKE=debian), même message" {
    printf 'ID=ubuntu\nID_LIKE=debian\n' > "$TMP/os-release"
    run nivuus_system_package_notice
    [ "$status" -eq 0 ]
    [[ "$output" == *"apt install"* ]]
}

@test "sur Fedora, RIEN n'est dit : c'est le périmètre propre de --system" {
    printf 'ID=fedora\n' > "$TMP/os-release"
    run nivuus_system_package_notice
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "sur Alpine non plus" {
    printf 'ID=alpine\n' > "$TMP/os-release"
    run nivuus_system_package_notice
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "le message n'est PAS un refus : il n'y a ni « refusé » ni « impossible »" {
    printf 'ID=debian\n' > "$TMP/os-release"
    run nivuus_system_package_notice
    [[ "$output" != *"refus"* ]]
    [[ "$output" != *"impossible"* ]]
}

@test "NIVUUS_SYSTEM_ASSUME_NO_PACKAGE fait taire la recommandation (crochet de test)" {
    printf 'ID=debian\n' > "$TMP/os-release"
    NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1 run nivuus_system_package_notice
    [ "$status" -ne 0 ]
}

@test "le talon de la Task 7 n'existe plus" {
    run grep -n "TALON" "$ROOT/lib/system.sh"
    [ "$status" -ne 0 ]
}
