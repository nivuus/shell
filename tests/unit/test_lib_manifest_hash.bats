#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"
    source "$LIB/manifest.sh"
    TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

@test "nivuus_hash_file returns the known sha256 of an empty file" {
    : > "$TMP/empty"
    run nivuus_hash_file "$TMP/empty"
    [ "$status" -eq 0 ]
    [ "$output" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]
}

@test "nivuus_hash_file returns the known sha256 of 'abc'" {
    printf 'abc' > "$TMP/abc"
    run nivuus_hash_file "$TMP/abc"
    [ "$output" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ]
}

@test "nivuus_hash_file returns dash for a missing file" {
    run nivuus_hash_file "$TMP/nope"
    [ "$status" -eq 0 ]
    [ "$output" = "-" ]
}

@test "nivuus_hash_file handles paths with spaces" {
    printf 'abc' > "$TMP/with space"
    run nivuus_hash_file "$TMP/with space"
    [ "$output" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ]
}
