#!/usr/bin/env bats
#
# Auditer ne demande pas de privilège. Cette suite ne construit rien : elle
# interdit à une propriété déjà vraie de se perdre au prochain refactor.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/etc"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1
    export NIVUUS_UID=1000        # explicitement NON root
}

teardown() { rm -rf "$TMP"; }

@test "--dry-run --system fonctionne sans root et sort en 0" {
    run "$ROOT/bin/nivuus" install --system --dry-run --yes
    [ "$status" -eq 0 ]
}

@test "--dry-run --system produit le rapport COMPLET" {
    run "$ROOT/bin/nivuus" install --system --dry-run --yes
    [[ "$output" == *"$TMP/usr/local/share/nivuus-shell"* ]]
    [[ "$output" == *"$TMP/usr/local/bin/nivuus"* ]]
    # Un rapport qui ne nomme que deux chemins n'est pas un audit.
    n="$(printf '%s\n' "$output" | grep -c "$TMP/usr/local/share/nivuus-shell")"
    [ "$n" -ge 10 ]
}

@test "--dry-run --system n'écrit RIEN, nulle part" {
    fs_fingerprint "$TMP" > "$TMP.avant"
    "$ROOT/bin/nivuus" install --system --dry-run --yes >/dev/null 2>&1
    fs_fingerprint "$TMP" > "$TMP.apres"
    diff "$TMP.avant" "$TMP.apres"
    [ ! -e "$TMP/usr" ]
    [ ! -e "$TMP/var" ]
    [ ! -e "$HOME/.local/state/nivuus" ]
}

@test "--dry-run --system ne réclame jamais sudo" {
    run "$ROOT/bin/nivuus" install --system --dry-run --yes
    [[ "$output" != *"sudo nivuus install"* ]]
}

@test "sans --dry-run, le même appel refuse : la différence est bien le mode audit" {
    run "$ROOT/bin/nivuus" install --system --yes
    [ "$status" -ne 0 ]
    [[ "$output" == *"sudo nivuus install --system"* ]]
}
