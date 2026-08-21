#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"; source "$LIB/manifest.sh"; source "$LIB/keys.sh"
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/keys"
    printf 'KEY A\n' > "$TMP/keys/a.pem"
    printf 'KEY B\n' > "$TMP/keys/b.pem"
    printf 'nivuus-release ssh-ed25519 AAAA x\n' > "$TMP/keys/allowed_signers"
    : > "$TMP/keys/revoked"
}

teardown() { rm -rf "$TMP"; }

@test "keyset_list prints one sorted line per key" {
    run nivuus_keyset_list "$TMP/keys"
    [ "$status" -eq 0 ]
    [ "${lines[0]%% *}" = "a.pem" ]
    [ "${lines[1]%% *}" = "b.pem" ]
    [ "${lines[2]%% *}" = "allowed_signers" ]
}

@test "keyset_fingerprint is stable across calls" {
    a="$(nivuus_keyset_fingerprint "$TMP/keys")"
    b="$(nivuus_keyset_fingerprint "$TMP/keys")"
    [ "$a" = "$b" ]
    [ -n "$a" ]
}

@test "keyset_fingerprint changes when a key is added" {
    before="$(nivuus_keyset_fingerprint "$TMP/keys")"
    printf 'KEY C\n' > "$TMP/keys/c.pem"
    after="$(nivuus_keyset_fingerprint "$TMP/keys")"
    [ "$before" != "$after" ]
}

@test "keyset_fingerprint changes when a key is altered" {
    before="$(nivuus_keyset_fingerprint "$TMP/keys")"
    printf 'KEY A TAMPERED\n' > "$TMP/keys/a.pem"
    after="$(nivuus_keyset_fingerprint "$TMP/keys")"
    [ "$before" != "$after" ]
}

@test "keyset_fingerprint ignores the revoked list ordering artefacts" {
    # revoked fait partie de la politique, pas de l'identité du jeu :
    # une révocation ne doit pas invalider l'empreinte que l'utilisateur
    # a notée. (Décision : l'empreinte couvre les clés, pas la dénylist.)
    before="$(nivuus_keyset_fingerprint "$TMP/keys")"
    printf 'sha256:deadbeef\n' > "$TMP/keys/revoked"
    after="$(nivuus_keyset_fingerprint "$TMP/keys")"
    [ "$before" = "$after" ]
}

@test "keyset_verify accepts the right fingerprint and rejects a wrong one" {
    fp="$(nivuus_keyset_fingerprint "$TMP/keys")"
    run nivuus_keyset_verify "$TMP/keys" "$fp"
    [ "$status" -eq 0 ]
    run nivuus_keyset_verify "$TMP/keys" "0000000000000000"
    [ "$status" -eq 1 ]
}

@test "keyset_verify rejects an empty or missing key store" {
    mkdir -p "$TMP/empty"
    run nivuus_keyset_verify "$TMP/empty" "whatever"
    [ "$status" -eq 1 ]
    run nivuus_keyset_verify "$TMP/nope" "whatever"
    [ "$status" -eq 1 ]
}
