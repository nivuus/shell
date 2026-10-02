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

@test "is_root honours a simulated NIVUUS_UID" {
    NIVUUS_UID=1000 run nivuus_is_root
    [ "$status" -eq 1 ]
    NIVUUS_UID=0 run nivuus_is_root
    [ "$status" -eq 0 ]
}

@test "system_zshrc is /etc/zsh/zshrc when /etc/zsh exists, /etc/zshrc otherwise" {
    export NIVUUS_ETC_DIR="$TMP/etc"
    unset NIVUUS_SYSTEM_ZSHRC
    mkdir -p "$TMP/etc"
    [ "$(nivuus_system_zshrc)" = "$TMP/etc/zshrc" ]
    mkdir -p "$TMP/etc/zsh"
    [ "$(nivuus_system_zshrc)" = "$TMP/etc/zsh/zshrc" ]
}

@test "NIVUUS_SYSTEM_ZSHRC overrides the detected global zshrc" {
    export NIVUUS_ETC_DIR="$TMP/etc"
    mkdir -p "$TMP/etc/zsh"
    NIVUUS_SYSTEM_ZSHRC="$TMP/custom" run nivuus_system_zshrc
    [ "$output" = "$TMP/custom" ]
}

@test "pkg_manager finds the first manager on PATH and honours an override" {
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\n' > "$TMP/bin/dnf"; chmod +x "$TMP/bin/dnf"
    run bash -c "PATH='$TMP/bin'; source '$LIB/detect.sh'; nivuus_pkg_manager"
    [ "$output" = "dnf" ]
    run bash -c "PATH='$TMP/bin'; NIVUUS_PKG_MANAGER=brew; source '$LIB/detect.sh'; nivuus_pkg_manager"
    [ "$output" = "brew" ]
    run bash -c "PATH='$TMP/empty'; source '$LIB/detect.sh'; nivuus_pkg_manager"
    [ "$output" = "" ]
}

@test "invoking_user is SUDO_USER under sudo, the current user otherwise" {
    SUDO_USER=alice run nivuus_invoking_user
    [ "$output" = "alice" ]
    SUDO_USER= run nivuus_invoking_user
    [ "$output" = "$(id -un)" ]
}
