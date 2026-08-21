#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"; source "$LIB/detect.sh"
    source "$LIB/manifest.sh"; source "$LIB/zshrc.sh"; source "$LIB/steps.sh"
    TMP="$(mktemp -d)"
    export NIVUUS_STATE_DIR="$TMP/state"
    unset NIVUUS_DRY_RUN
    nivuus_manifest_begin user "$TMP/install"

    SRC="$TMP/src"
    mkdir -p "$SRC/config" "$SRC/keys"
    printf 'core\n'          > "$SRC/config/00-core.zsh"
    printf 'FAKE PEM\n'      > "$SRC/keys/nivuus-release-2026.pem"
    printf 'nivuus-release ssh-ed25519 AAAA fake\n' > "$SRC/keys/allowed_signers"
    : > "$SRC/keys/revoked"
    printf 'main\n'          > "$SRC/.zshrc"
}

teardown() { rm -rf "$TMP"; }

@test "copy_tree installs the public key store" {
    nivuus_step_copy_tree "$SRC" "$TMP/install"
    [ -f "$TMP/install/keys/nivuus-release-2026.pem" ]
}

@test "copy_tree installs allowed_signers" {
    nivuus_step_copy_tree "$SRC" "$TMP/install"
    [ -f "$TMP/install/keys/allowed_signers" ]
}

@test "copy_tree installs the (possibly empty) revoked list" {
    nivuus_step_copy_tree "$SRC" "$TMP/install"
    [ -f "$TMP/install/keys/revoked" ]
}

@test "the key store is recorded in the manifest, so uninstall removes it" {
    nivuus_step_copy_tree "$SRC" "$TMP/install"
    nivuus_manifest_commit
    run grep -c "keys/nivuus-release-2026.pem" "$NIVUUS_MANIFEST"
    [ "$output" = "1" ]
}
