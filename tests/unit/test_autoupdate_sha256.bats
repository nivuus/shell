#!/usr/bin/env bats

load '../helpers/signing'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    ZSH_BIN="$(command -v zsh)"
    TMP="$(mktemp -d)"
    printf 'abc' > "$TMP/abc"
    # Le bytecode périmé masquerait la nouvelle version du module.
    find "$ROOT/config" -name '*.zwc' -delete 2>/dev/null || true
}

teardown() { rm -rf "$TMP"; }

ABC=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad

@test "sha256_of returns the known digest of 'abc'" {
    run zsh_autoupdate "_nivuus_sha256_of '$TMP/abc'"
    [ "$status" -eq 0 ]
    [ "$output" = "$ABC" ]
}

@test "sha256_of works with shasum only (macOS regression)" {
    fake="$(mkfakepath "$TMP/bin" shasum awk zsh)"
    run env PATH="$fake" ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; _nivuus_sha256_of '$TMP/abc'"
    [ "$status" -eq 0 ]
    [ "$output" = "$ABC" ]
}

@test "sha256_of works with sha256sum only" {
    fake="$(mkfakepath "$TMP/bin" sha256sum awk zsh)"
    run env PATH="$fake" ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; _nivuus_sha256_of '$TMP/abc'"
    [ "$status" -eq 0 ]
    [ "$output" = "$ABC" ]
}

@test "sha256_of fails loudly when no hashing tool exists" {
    fake="$(mkfakepath "$TMP/bin" awk zsh)"
    run env PATH="$fake" ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; _nivuus_sha256_of '$TMP/abc'"
    [ "$status" -ne 0 ]
    # Surtout : ne JAMAIS imprimer une chaîne vide qu'un appelant
    # comparerait à une empreinte attendue.
    [ "$output" = "" ]
}

@test "sha256_of fails on a missing file" {
    run zsh_autoupdate "_nivuus_sha256_of '$TMP/nope'"
    [ "$status" -ne 0 ]
    [ "$output" = "" ]
}

@test "sha256_of handles a path with spaces" {
    printf 'abc' > "$TMP/with space"
    run zsh_autoupdate "_nivuus_sha256_of '$TMP/with space'"
    [ "$output" = "$ABC" ]
}
