#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"
    source "$LIB/manifest.sh"
    TMP="$(mktemp -d)"
    export NIVUUS_STATE_DIR="$TMP/state"
    unset NIVUUS_DRY_RUN
    nivuus_manifest_begin user "$TMP/install"
}

teardown() { rm -rf "$TMP"; }

@test "install_file creates the destination and records CREATE" {
    printf 'hello' > "$TMP/src"
    nivuus_install_file "$TMP/src" "$TMP/dst"
    [ "$(cat "$TMP/dst")" = "hello" ]
    nivuus_manifest_commit
    run grep -c "^CREATE" "$NIVUUS_MANIFEST"
    [ "$output" = "1" ]
}

@test "install_file over an existing file records MODIFY and backs up the original" {
    printf 'old' > "$TMP/dst"
    printf 'new' > "$TMP/src"
    nivuus_install_file "$TMP/src" "$TMP/dst"
    [ "$(cat "$TMP/dst")" = "new" ]
    nivuus_manifest_commit
    run grep -c "^MODIFY" "$NIVUUS_MANIFEST"
    [ "$output" = "1" ]
    # le backup de 'old' est retrouvable par son hash
    old_hash="$(printf 'old' | { command -v sha256sum >/dev/null && sha256sum || shasum -a 256; } | cut -d' ' -f1)"
    [ -f "$NIVUUS_BACKUP_DIR/$old_hash" ]
    [ "$(cat "$NIVUUS_BACKUP_DIR/$old_hash")" = "old" ]
}

@test "install_file is idempotent: identical content records nothing" {
    printf 'same' > "$TMP/src"
    printf 'same' > "$TMP/dst"
    nivuus_install_file "$TMP/src" "$TMP/dst"
    nivuus_manifest_commit
    run grep -c "^CREATE\|^MODIFY" "$NIVUUS_MANIFEST"
    [ "$status" -ne 0 ]
}

@test "mkdir_p records MKDIR only for levels it creates" {
    # nivuus_manifest_begin (setup) journalise déjà ses propres MKDIR de
    # bootstrap pour $NIVUUS_STATE_DIR : on ne compte ici que les entrées
    # sous le répertoire propre à ce test.
    nivuus_mkdir_p "$TMP/a/b"
    [ -d "$TMP/a/b" ]
    nivuus_manifest_commit
    run grep -c "^MKDIR.*$TMP/a" "$NIVUUS_MANIFEST"
    [ "$output" = "2" ]
}

@test "mkdir_p on an existing dir records nothing" {
    mkdir -p "$TMP/exists"
    nivuus_mkdir_p "$TMP/exists"
    nivuus_manifest_commit
    run grep -c "^MKDIR.*$TMP/exists" "$NIVUUS_MANIFEST"
    [ "$status" -ne 0 ]
}

@test "write_file takes content from stdin" {
    printf 'from stdin' | nivuus_write_file "$TMP/out"
    [ "$(cat "$TMP/out")" = "from stdin" ]
}

@test "dry-run mutates nothing on disk" {
    export NIVUUS_DRY_RUN=1
    printf 'x' > "$TMP/src"
    nivuus_install_file "$TMP/src" "$TMP/never"
    nivuus_mkdir_p "$TMP/never-dir"
    [ ! -e "$TMP/never" ]
    [ ! -e "$TMP/never-dir" ]
}

@test "dry-run write_file does not create the destination" {
    export NIVUUS_DRY_RUN=1
    printf 'content' | nivuus_write_file "$TMP/never-written"
    [ ! -e "$TMP/never-written" ]
}

@test "reinstalling over an already-nivuus'd file carries the original backup ref forward" {
    printf 'pristine' > "$TMP/dst"
    printf 'nivuus-v1' > "$TMP/src"
    nivuus_install_file "$TMP/src" "$TMP/dst"
    nivuus_manifest_commit
    pristine_hash="$(printf 'pristine' | { command -v sha256sum >/dev/null && sha256sum || shasum -a 256; } | cut -d' ' -f1)"
    [ -f "$NIVUUS_BACKUP_DIR/$pristine_hash" ]

    # Une seconde "installation" (nouveau manifeste qui hérite du premier,
    # comme le fait bin/nivuus) écrit un contenu différent sur le même
    # chemin -- ce que ferait un vrai second install si l'utilisateur avait
    # entre-temps édité le fichier de façon à changer sa forme finale.
    nivuus_manifest_begin user "$TMP/install"
    nivuus_manifest_inherit
    printf 'nivuus-v2-different' > "$TMP/src2"
    nivuus_install_file "$TMP/src2" "$TMP/dst"
    nivuus_manifest_commit

    # Le pointeur de sauvegarde le plus récent doit toujours désigner la
    # sauvegarde ORIGINALE (pristine), jamais une sauvegarde de la version
    # déjà nivuusée -- sinon un rollback restaurerait un état géré par
    # Nivuus au lieu du fichier d'avant Nivuus.
    latest_ref="$(grep '^MODIFY' "$NIVUUS_MANIFEST" | tail -n1 | cut -f4)"
    [ "$latest_ref" = "$pristine_hash" ]
    [ -f "$NIVUUS_BACKUP_DIR/$pristine_hash" ]
    [ "$(cat "$NIVUUS_BACKUP_DIR/$pristine_hash")" = "pristine" ]

    nivuus_manifest_rollback
    [ "$(cat "$TMP/dst")" = "pristine" ]
}

@test "writing through a symlinked destination warns and names the real target" {
    printf 'stow-managed\n' > "$TMP/real-target"
    ln -s "$TMP/real-target" "$TMP/dst"
    printf 'new' > "$TMP/src"
    run nivuus_install_file "$TMP/src" "$TMP/dst"
    [[ "$output" == *"$TMP/dst"* ]]
    [[ "$output" == *"$TMP/real-target"* ]]
    [ "$(cat "$TMP/real-target")" = "new" ]
}
