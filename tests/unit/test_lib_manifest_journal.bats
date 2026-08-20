#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"
    source "$LIB/manifest.sh"
    TMP="$(mktemp -d)"
    export NIVUUS_STATE_DIR="$TMP/state"
    unset NIVUUS_DRY_RUN
}

teardown() { rm -rf "$TMP"; }

@test "manifest_begin creates the state dir and a header line" {
    nivuus_manifest_begin user "$TMP/install"
    nivuus_manifest_commit
    [ -f "$NIVUUS_MANIFEST" ]
    run head -1 "$NIVUUS_MANIFEST"
    [[ "$output" == "#nivuus-manifest v1"* ]]
    [[ "$output" == *"mode=user"* ]]
    [[ "$output" == *"dir=$TMP/install"* ]]
}

@test "manifest_record appends a tab-separated line" {
    nivuus_manifest_begin user "$TMP/install"
    nivuus_manifest_record CREATE "/tmp/a" "deadbeef" "-"
    nivuus_manifest_commit
    run grep -c . "$NIVUUS_MANIFEST"
    [ "$output" = "2" ]
    run tail -1 "$NIVUUS_MANIFEST"
    [ "$output" = "$(printf 'CREATE\t/tmp/a\tdeadbeef\t-')" ]
}

@test "manifest_record rejects a path containing a tab" {
    nivuus_manifest_begin user "$TMP/install"
    run nivuus_manifest_record CREATE "$(printf 'bad\tpath')" "x" "-"
    [ "$status" -eq 1 ]
}

@test "manifest is not visible until commit" {
    nivuus_manifest_begin user "$TMP/install"
    nivuus_manifest_record CREATE "/tmp/a" "x" "-"
    [ ! -f "$NIVUUS_MANIFEST" ]
    nivuus_manifest_commit
    [ -f "$NIVUUS_MANIFEST" ]
}

@test "manifest_each iterates entries in reverse order, skipping the header" {
    nivuus_manifest_begin user "$TMP/install"
    nivuus_manifest_record MKDIR "/tmp/d" "-" "-"
    nivuus_manifest_record CREATE "/tmp/a" "x" "-"
    nivuus_manifest_commit
    collect() { printf '%s:%s ' "$1" "$2"; }
    run nivuus_manifest_each collect
    [ "$output" = "CREATE:/tmp/a MKDIR:/tmp/d " ]
}

@test "dry-run writes nothing to disk" {
    export NIVUUS_DRY_RUN=1
    nivuus_manifest_begin user "$TMP/install"
    nivuus_manifest_record CREATE "/tmp/a" "x" "-"
    nivuus_manifest_commit
    [ ! -d "$NIVUUS_STATE_DIR" ]
}
