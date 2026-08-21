#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/detect.sh"
    TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

@test "detect_os returns linux or macos" {
    run nivuus_detect_os
    [[ "$output" = "linux" || "$output" = "macos" ]]
}

@test "is_container is true when /.dockerenv exists" {
    export NIVUUS_DOCKERENV="$TMP/.dockerenv"
    : > "$NIVUUS_DOCKERENV"
    run nivuus_is_container
    [ "$status" -eq 0 ]
}

@test "is_container is false without any container marker" {
    export NIVUUS_DOCKERENV="$TMP/absent"
    export NIVUUS_CGROUP="$TMP/absent"
    unset container
    run nivuus_is_container
    [ "$status" -eq 1 ]
}

@test "is_container is true when the container env var is set" {
    export NIVUUS_DOCKERENV="$TMP/absent"
    export NIVUUS_CGROUP="$TMP/absent"
    export container=podman
    run nivuus_is_container
    [ "$status" -eq 0 ]
}

@test "is_tty is false under bats (no controlling terminal)" {
    run nivuus_is_tty
    [ "$status" -eq 1 ]
}

@test "should_minimal is true when there is no TTY" {
    run nivuus_should_minimal
    [ "$status" -eq 0 ]
}
