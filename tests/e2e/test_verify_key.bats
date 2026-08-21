#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
    source "$ROOT/lib/log.sh"; source "$ROOT/lib/manifest.sh"; source "$ROOT/lib/keys.sh"
}

teardown() { rm -rf "$TMP"; }

# Voir tests/e2e/test_install_keys.bats : le trousseau réel est une tâche
# HUMAINE (Task 11). Le skip se lève tout seul quand les .pem arrivent.
require_real_keyset() {
    ls "$ROOT/keys"/*.pem >/dev/null 2>&1 \
        || skip "nécessite le trousseau réel (Task 11, tâche humaine)"
}

@test "install --verify-key with the right fingerprint proceeds" {
    require_real_keyset
    fp="$(nivuus_keyset_fingerprint "$ROOT/keys")"
    run "$NIVUUS" install --yes --verify-key "$fp" --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ -d "$TMP/target/keys" ]
}

@test "install --verify-key with a wrong fingerprint refuses and writes NOTHING" {
    run "$NIVUUS" install --yes --verify-key "cafecafecafecafe" --prefix "$TMP/target"
    [ "$status" -ne 0 ]
    [ ! -e "$TMP/target" ]
    [ ! -e "$HOME/.zshrc" ]
}

@test "install.sh forwards --verify-key" {
    run "$ROOT/install.sh" --non-interactive --verify-key "cafecafecafecafe" --prefix "$TMP/target"
    [ "$status" -ne 0 ]
    [ ! -e "$TMP/target" ]
}
