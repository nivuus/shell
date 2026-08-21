#!/usr/bin/env bats

load '../helpers/portable'

setup() { TMP="$(mktemp -d)"; }
teardown() { rm -rf "$TMP"; }

@test "pt_prepend_line inserts at the top and keeps the rest byte-for-byte" {
    printf 'b\nc\n' > "$TMP/f"
    pt_prepend_line "$TMP/f" 'a'
    run cat "$TMP/f"
    [ "${lines[0]}" = "a" ]
    [ "${lines[1]}" = "b" ]
    [ "${lines[2]}" = "c" ]
}

@test "pt_prepend_line preserves the file permissions" {
    printf 'b\n' > "$TMP/f"; chmod 600 "$TMP/f"
    pt_prepend_line "$TMP/f" 'a'
    run bash -c "stat -c '%a' '$TMP/f' 2>/dev/null || stat -f '%Lp' '$TMP/f'"
    [ "$output" = "600" ]
}

@test "pt_to_crlf ends every line with CR LF" {
    printf 'a\nb\n' > "$TMP/f"
    pt_to_crlf "$TMP/f"
    run od -c "$TMP/f"
    [[ "$output" == *'\r'*'\n'* ]]
}

@test "no test file edits a file in place with the non-portable flag" {
    # Motif écrit de façon à ne pas se matcher lui-même (ce fichier est dans
    # l'arborescence scannée) : GNU et BSD n'ont pas la même signature pour
    # l'édition en place, aucun test ne doit s'y fier.
    run grep -rnE 'sed +-i' "${BATS_TEST_DIRNAME}/../unit" "${BATS_TEST_DIRNAME}/../e2e"
    [ "$status" -ne 0 ]
}
