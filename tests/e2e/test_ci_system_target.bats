#!/usr/bin/env bats
#
# Rejoue, dans de vrais conteneurs, la preuve du mode système. Marqué
# `docker` : il crée des comptes et écrit dans /etc et /usr/local ; sa
# place est la matrice nightly, jamais une PR ni un poste.
#
# Les cinq images sont choisies, pas héritées : Fedora et Alpine sont
# exactement les cibles qu'aucun canal de paquet ne servira jamais, donc le
# coeur du périmètre de --system.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    command -v docker >/dev/null 2>&1 || skip "docker indisponible"
}

run_system_in() {
    docker run --rm -v "$ROOT:/src:ro" "$1" sh -c '
        set -e
        cp -r /src /work && chmod -R a+rX /work && cd /work
        ./tests/ci/install-deps.sh >/dev/null
        ./tests/ci/run-system-target.sh'
}

# bats test_tags=docker
@test "run-system-target.sh prouve le mode système sur debian:12" {
    run run_system_in debian:12
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cible système OK"* ]]
}

# bats test_tags=docker
@test "run-system-target.sh prouve le mode système sur ubuntu:24.04" {
    run run_system_in ubuntu:24.04
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "run-system-target.sh prouve le mode système sur fedora:41 (aucun canal de paquet)" {
    run run_system_in fedora:41
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "run-system-target.sh prouve le mode système sur alpine:3.20 (musl, adduser BusyBox)" {
    run run_system_in alpine:3.20
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "run-system-target.sh prouve le mode système sur archlinux:latest" {
    run run_system_in archlinux:latest
    [ "$status" -eq 0 ]
}

@test "le script est du sh valide (contrôle statique, sans docker)" {
    run sh -n "$ROOT/tests/ci/run-system-target.sh"
    [ "$status" -eq 0 ]
}

@test "les trois invariants de la phase 1 sont nommés dans le script" {
    # Garde-fou local, doublé en CI : ces étapes ne doivent pas pouvoir
    # disparaître discrètement.
    grep -q "INVARIANT n° 1" "$ROOT/tests/ci/run-system-target.sh"
    grep -q "INVARIANT n° 2" "$ROOT/tests/ci/run-system-target.sh"
    grep -q "INVARIANT n° 4" "$ROOT/tests/ci/run-system-target.sh"
}
