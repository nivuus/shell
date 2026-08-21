#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"; source "$LIB/manifest.sh"
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/src/sous"; printf 'x\n' > "$TMP/src/sous/f"
}

teardown() { rm -rf "$TMP"; }

@test "move_aside déplace et imprime la destination" {
    run nivuus_move_aside "$TMP/src" "$TMP/etat/migration/1/git"
    [ "$status" -eq 0 ]
    [ "$output" = "$TMP/etat/migration/1/git" ]
    [ ! -e "$TMP/src" ]
    [ -f "$TMP/etat/migration/1/git/sous/f" ]
}

@test "move_aside crée les répertoires parents manquants" {
    nivuus_move_aside "$TMP/src" "$TMP/a/b/c/git"
    [ -d "$TMP/a/b/c/git" ]
}

@test "move_aside refuse d'écraser une destination existante" {
    mkdir -p "$TMP/dest"
    run nivuus_move_aside "$TMP/src" "$TMP/dest"
    [ "$status" -ne 0 ]
    [ -d "$TMP/src" ]
}

@test "move_aside échoue si la source n'existe pas" {
    run nivuus_move_aside "$TMP/absent" "$TMP/dest"
    [ "$status" -ne 0 ]
}

@test "move_aside ne déplace rien en dry-run" {
    run env NIVUUS_DRY_RUN=1 bash -c \
        ". '$LIB/log.sh'; . '$LIB/manifest.sh'; nivuus_move_aside '$TMP/src' '$TMP/dest'"
    [ "$status" -eq 0 ]
    [ -d "$TMP/src" ]
    [ ! -e "$TMP/dest" ]
}
