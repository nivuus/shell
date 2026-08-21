#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    TMP="$(mktemp -d)"
    source "$LIB/detect.sh"
}

teardown() { rm -rf "$TMP"; }

@test "detect_distro reads ID from os-release" {
    printf 'NAME="Ubuntu"\nID=ubuntu\nID_LIKE=debian\n' > "$TMP/os-release"
    run bash -c "NIVUUS_OS_RELEASE='$TMP/os-release'; source '$LIB/detect.sh'; nivuus_detect_distro"
    [ "$output" = "ubuntu" ]
}

@test "detect_distro strips quotes around ID" {
    printf 'ID="alpine"\nVERSION_ID=3.20\n' > "$TMP/os-release"
    run bash -c "NIVUUS_OS_RELEASE='$TMP/os-release'; source '$LIB/detect.sh'; nivuus_detect_distro"
    [ "$output" = "alpine" ]
}

@test "detect_distro ignores a commented or later ID-like key" {
    printf '# ID=decoy\nID_LIKE=debian\nID=debian\n' > "$TMP/os-release"
    run bash -c "NIVUUS_OS_RELEASE='$TMP/os-release'; source '$LIB/detect.sh'; nivuus_detect_distro"
    [ "$output" = "debian" ]
}

@test "detect_distro returns unknown without os-release" {
    run bash -c "NIVUUS_OS_RELEASE='$TMP/absent'; source '$LIB/detect.sh'; nivuus_detect_distro"
    [ "$output" = "unknown" ]
}

@test "detect_distro_like returns ID_LIKE or empty" {
    printf 'ID=fedora\nID_LIKE="rhel centos"\n' > "$TMP/os-release"
    run bash -c "NIVUUS_OS_RELEASE='$TMP/os-release'; source '$LIB/detect.sh'; nivuus_detect_distro_like"
    [ "$output" = "rhel centos" ]

    printf 'ID=arch\n' > "$TMP/os-release"
    run bash -c "NIVUUS_OS_RELEASE='$TMP/os-release'; source '$LIB/detect.sh'; nivuus_detect_distro_like"
    [ "$output" = "" ]
}

@test "detect_arch normalises the common machine names" {
    run nivuus_detect_arch
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    # Une des deux valeurs normalisées sur toutes les cibles du projet.
    [[ "$output" = "arm64" || "$output" = "x86_64" || "$output" = "$(uname -m)" ]]
}
