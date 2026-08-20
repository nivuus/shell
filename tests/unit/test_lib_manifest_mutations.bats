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
    nivuus_mkdir_p "$TMP/a/b"
    [ -d "$TMP/a/b" ]
    nivuus_manifest_commit
    run grep -c "^MKDIR" "$NIVUUS_MANIFEST"
    [ "$output" = "2" ]
}

@test "mkdir_p on an existing dir records nothing" {
    mkdir -p "$TMP/exists"
    nivuus_mkdir_p "$TMP/exists"
    nivuus_manifest_commit
    run grep -c "^MKDIR" "$NIVUUS_MANIFEST"
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
