#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    TMP="$(mktemp -d)"
    # L'environnement neutre (ni container, ni WSL, ni SSH, ni X) est
    # construit dans le helper `detect` ci-dessous, via env -u.
}

teardown() { rm -rf "$TMP"; }

detect() {   # detect "<env>" "<appel>"
    run env -u container -u WSL_DISTRO_NAME -u WSL_INTEROP \
            -u SSH_CONNECTION -u SSH_CLIENT -u SSH_TTY \
            -u DISPLAY -u WAYLAND_DISPLAY -u NIVUUS_MINIMAL -u NIVUUS_NO_MINIMAL \
            NIVUUS_DOCKERENV="$TMP/absent" NIVUUS_CGROUP="$TMP/absent" \
            NIVUUS_PROC_VERSION="$TMP/absent" \
            bash -c "$1 source '$LIB/detect.sh'; $2"
}

@test "is_wsl is true when /proc/version mentions Microsoft" {
    printf 'Linux version 5.15.0-microsoft-standard-WSL2\n' > "$TMP/proc_version"
    detect "NIVUUS_PROC_VERSION='$TMP/proc_version';" "nivuus_is_wsl"
    [ "$status" -eq 0 ]
}

@test "is_wsl is true when WSL_DISTRO_NAME is set" {
    detect "WSL_DISTRO_NAME=Ubuntu;" "nivuus_is_wsl"
    [ "$status" -eq 0 ]
}

@test "is_wsl is false on a plain Linux kernel" {
    printf 'Linux version 6.6.0-generic\n' > "$TMP/proc_version"
    detect "NIVUUS_PROC_VERSION='$TMP/proc_version';" "nivuus_is_wsl"
    [ "$status" -eq 1 ]
}

@test "is_ssh reacts to each of the three markers" {
    detect "SSH_CONNECTION='1.2.3.4 22';" "nivuus_is_ssh"; [ "$status" -eq 0 ]
    detect "SSH_CLIENT='1.2.3.4';"       "nivuus_is_ssh"; [ "$status" -eq 0 ]
    detect "SSH_TTY='/dev/pts/0';"       "nivuus_is_ssh"; [ "$status" -eq 0 ]
    detect ""                            "nivuus_is_ssh"; [ "$status" -eq 1 ]
}

@test "is_headless is false when a graphical session is present" {
    detect "DISPLAY=':0';"          "nivuus_is_headless"; [ "$status" -eq 1 ]
    detect "WAYLAND_DISPLAY=wl-0;"  "nivuus_is_headless"; [ "$status" -eq 1 ]
}

@test "is_headless is false under WSL even without DISPLAY" {
    detect "WSL_DISTRO_NAME=Ubuntu;" "nivuus_is_headless"
    [ "$status" -eq 1 ]
}

@test "is_headless is true on a bare Linux console" {
    detect "" "nivuus_is_headless"
    [ "$status" -eq 0 ]
}

@test "should_minimal is forced on by NIVUUS_MINIMAL" {
    detect "NIVUUS_MINIMAL=1; DISPLAY=':0';" "nivuus_should_minimal"
    [ "$status" -eq 0 ]
}

@test "NIVUUS_NO_MINIMAL wins over every automatic trigger" {
    detect "NIVUUS_NO_MINIMAL=1; NIVUUS_MINIMAL=1; container=podman;" "nivuus_should_minimal"
    [ "$status" -eq 1 ]
}

@test "should_minimal is true over SSH even with a graphical session" {
    detect "SSH_CONNECTION='1.2.3.4 22'; DISPLAY=':0';" "nivuus_should_minimal"
    [ "$status" -eq 0 ]
}
