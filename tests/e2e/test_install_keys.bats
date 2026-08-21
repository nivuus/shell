#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
}

teardown() { rm -rf "$TMP"; }

# Le trousseau réel est généré et committé par une tâche HUMAINE (Task 11
# du plan) : aucun agent ne doit produire de clé de production. Tant qu'il
# n'y a pas de .pem dans keys/, l'assertion « au moins une clé publique »
# n'a rien à mordre. Le skip se lève TOUT SEUL le jour où la Task 11 est
# faite — pas de skip à retirer à la main, donc pas de skip oublié.
require_real_keyset() {
    ls "$ROOT/keys"/*.pem >/dev/null 2>&1 \
        || skip "nécessite le trousseau réel (Task 11, tâche humaine)"
}

@test "a fresh install owns a usable trust store" {
    run "$NIVUUS" install --yes --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ -d "$TMP/target/keys" ]
    # Au moins une clé publique, sinon l'auto-update est mort-né.
    require_real_keyset
    run bash -c "ls '$TMP/target/keys'/*.pem 2>/dev/null | wc -l"
    [ "$output" -ge 1 ]
}

@test "the installed trust store contains no private key" {
    "$NIVUUS" install --yes --prefix "$TMP/target"
    run grep -rlE 'BEGIN (RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY' "$TMP/target/keys"
    [ "$status" -ne 0 ]
}
