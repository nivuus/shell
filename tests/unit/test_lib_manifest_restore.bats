#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"; source "$LIB/manifest.sh"
    TMP="$(mktemp -d)"
    export NIVUUS_STATE_DIR="$TMP/state"
    unset NIVUUS_DRY_RUN
    nivuus_manifest_begin user "$TMP/install"
}

teardown() { rm -rf "$TMP"; }

@test "CREATE is removed when the hash still matches" {
    printf 'x' > "$TMP/src"
    nivuus_install_file "$TMP/src" "$TMP/created"
    nivuus_manifest_commit
    nivuus_manifest_rollback
    [ ! -e "$TMP/created" ]
}

@test "CREATE is kept when the user modified it" {
    printf 'x' > "$TMP/src"
    nivuus_install_file "$TMP/src" "$TMP/created"
    nivuus_manifest_commit
    printf 'user edit' > "$TMP/created"
    nivuus_manifest_rollback
    [ -f "$TMP/created" ]
    [ "$(cat "$TMP/created")" = "user edit" ]
}

@test "MODIFY restores the original content" {
    printf 'original' > "$TMP/target"
    printf 'nivuus'   > "$TMP/src"
    nivuus_install_file "$TMP/src" "$TMP/target"
    nivuus_manifest_commit
    [ "$(cat "$TMP/target")" = "nivuus" ]
    nivuus_manifest_rollback
    [ "$(cat "$TMP/target")" = "original" ]
}

@test "MODIFY leaves the file alone when it diverged after install" {
    printf 'original' > "$TMP/target"
    printf 'nivuus'   > "$TMP/src"
    nivuus_install_file "$TMP/src" "$TMP/target"
    nivuus_manifest_commit
    printf 'user edit' > "$TMP/target"
    nivuus_manifest_rollback
    [ "$(cat "$TMP/target")" = "user edit" ]
}

@test "MKDIR is removed only when empty" {
    nivuus_mkdir_p "$TMP/d/e"
    nivuus_manifest_commit
    nivuus_manifest_rollback
    [ ! -d "$TMP/d/e" ]
    [ ! -d "$TMP/d" ]
}

@test "MKDIR survives when it holds a foreign file" {
    nivuus_mkdir_p "$TMP/d"
    nivuus_manifest_commit
    printf 'foreign' > "$TMP/d/keep"
    nivuus_manifest_rollback
    [ -d "$TMP/d" ]
    [ -f "$TMP/d/keep" ]
}

@test "CHSH restoration never executes chsh" {
    mkdir -p "$TMP/fakebin"
    printf '#!/bin/sh\n: > "%s/EXECUTED-chsh"\n' "$TMP" > "$TMP/fakebin/chsh"
    chmod +x "$TMP/fakebin/chsh"

    nivuus_manifest_record CHSH "$HOME" - /bin/bash
    nivuus_manifest_commit

    # Le vrai PATH reste accessible (nivuus_manifest_each dépend de grep/sed
    # externes) mais fakebin passe devant : le faux chsh masque le vrai.
    run bash -c "
        PATH='$TMP/fakebin:$PATH'
        source '$LIB/log.sh'
        source '$LIB/manifest.sh'
        NIVUUS_MANIFEST='$NIVUUS_MANIFEST'
        NIVUUS_BACKUP_DIR='$NIVUUS_BACKUP_DIR'
        nivuus_manifest_rollback
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"/bin/bash"* ]]      # la commande est bien indiquée...
    run ls "$TMP"
    [[ "$output" != *"EXECUTED-chsh"* ]]  # ...mais jamais exécutée
}

@test "PKG entries are ignored by rollback without warning" {
    nivuus_manifest_record PKG fzf - apt-get
    nivuus_manifest_commit
    run nivuus_manifest_rollback
    [ "$status" -eq 0 ]
    [[ "$output" != *"inconnue"* ]]
}

@test "an unknown manifest action warns but does not abort rollback" {
    nivuus_manifest_record BOGUS "$TMP/whatever" - -
    nivuus_manifest_commit
    run nivuus_manifest_rollback
    [ "$status" -eq 0 ]
    [[ "$output" == *"inconnue"* ]]
}
