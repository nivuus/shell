#!/usr/bin/env bats
#
# Rejoue en local, dans un vrai conteneur, ce que la CI fera de install-deps.sh.
# Marqué `docker` : exclu des runs de PR via --filter-tags (voir tests/ci/bats-run.sh).

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    command -v docker >/dev/null 2>&1 || skip "docker indisponible"
}

# Un conteneur vierge, le dépôt monté en lecture seule, le script, puis la
# preuve qu'on peut réellement lancer des tests derrière.
run_in() {
    docker run --rm -v "$ROOT:/src:ro" "$1" sh -c '
        set -e
        cp -r /src /work && chmod -R a+rX /work && cd /work
        ./tests/ci/install-deps.sh
        bats --version | grep -q "1.11.1"
        bats --count tests/unit/test_lib_detect.bats
        command -v zsh >/dev/null
        # `diff` : exigé par tests/e2e/test_nivuus_cli.bats ; absent des
        # images fedora et archlinux de base, où son absence se manifestait
        # par un code 127 déguisé en échec de test.
        command -v diff >/dev/null
    '
}

# bats test_tags=docker
@test "install-deps works on debian:12" {
    run run_in debian:12
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "install-deps works on fedora:41" {
    run run_in fedora:41
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "install-deps works on archlinux:latest" {
    run run_in archlinux:latest
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "install-deps works on alpine:3.20 (musl, no GNU coreutils)" {
    run run_in alpine:3.20
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "install-deps is idempotent (second run is a no-op that still succeeds)" {
    run docker run --rm -v "$ROOT:/src:ro" debian:12 sh -c '
        set -e
        cp -r /src /work && chmod -R a+rX /work && cd /work
        ./tests/ci/install-deps.sh >/dev/null
        ./tests/ci/install-deps.sh
    '
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "run-target.sh installs, runs a real interactive shell and reverts, on debian:12" {
    run docker run --rm -v "$ROOT:/src:ro" debian:12 sh -c '
        set -e
        cp -r /src /work && chmod -R a+rX /work && cd /work
        ./tests/ci/install-deps.sh >/dev/null
        ./tests/ci/run-target.sh
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"REAL_SHELL_OK"* ]]
}

# bats test_tags=docker
@test "run-target.sh works on alpine:3.20 too" {
    run docker run --rm -v "$ROOT:/src:ro" alpine:3.20 sh -c '
        set -e
        cp -r /src /work && chmod -R a+rX /work && cd /work
        ./tests/ci/install-deps.sh >/dev/null
        ./tests/ci/run-target.sh
    '
    [ "$status" -eq 0 ]
}

