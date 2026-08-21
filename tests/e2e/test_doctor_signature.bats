#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
    "$ROOT/bin/nivuus" install --yes --prefix "$TMP/target" >/dev/null
    export NIVUUS_SHELL_DIR="$TMP/target"
}

teardown() { rm -rf "$TMP"; }

# Voir tests/e2e/test_install_keys.bats : le trousseau réel est une tâche
# HUMAINE (Task 11). Le skip se lève tout seul quand les .pem arrivent.
require_real_keyset() {
    ls "$ROOT/keys"/*.pem >/dev/null 2>&1 \
        || skip "nécessite le trousseau réel (Task 11, tâche humaine)"
}

@test "doctor reports the trust store fingerprint" {
    require_real_keyset
    run "$TMP/target/bin/healthcheck"
    [[ "$output" == *"Update signing"* ]]
    [[ "$output" == *"fingerprint"* || "$output" == *"empreinte"* ]]
}

@test "doctor names the verification tool it would use on this machine" {
    run "$TMP/target/bin/healthcheck"
    [[ "$output" == *"openssl"* || "$output" == *"ssh-keygen"* ]]
}

@test "doctor flags a missing key store loudly" {
    rm -rf "$TMP/target/keys"
    run "$TMP/target/bin/healthcheck"
    [[ "$output" == *"aucune clé"* || "$output" == *"no trusted key"* ]]
}

@test "the README makes no security claim about curl | sh" {
    # Garde-fou de rédaction : le problème d'amorçage doit rester nommé.
    run grep -ci "signed.*secure\|badge.*secure" "$ROOT/README.md"
    [ "$output" = "0" ]
    run grep -c "première installation\|first install" "$ROOT/README.md"
    [ "$status" -eq 0 ]
}

@test "SECURITY.md exists and publishes the keyset fingerprint" {
    [ -f "$ROOT/SECURITY.md" ]
    require_real_keyset
    source "$ROOT/lib/log.sh"; source "$ROOT/lib/manifest.sh"; source "$ROOT/lib/keys.sh"
    fp="$(nivuus_keyset_fingerprint "$ROOT/keys")"
    run grep -c "$fp" "$ROOT/SECURITY.md"
    [ "$output" != "0" ]
}
