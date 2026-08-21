#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    COUNT="$ROOT/bin/test-count"
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/tests/alpha" "$TMP/tests/beta"
    printf '#!/usr/bin/env bats\n@test "a" { true; }\n@test "b" { true; }\n' > "$TMP/tests/alpha/x.bats"
    printf '#!/usr/bin/env bats\n@test "c" { true; }\n' > "$TMP/tests/beta/y.bats"
    export NIVUUS_TESTS_DIR="$TMP/tests"
    export NIVUUS_COUNT_BASELINE="$TMP/baseline.tsv"
    export NIVUUS_COUNT_SUITES="alpha beta"
}

teardown() { rm -rf "$TMP"; }

@test "counts tests from the bats plan, not from grep" {
    run "$COUNT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"alpha	2"* ]]
    [[ "$output" == *"beta	1"* ]]
    [[ "$output" == *"total	3"* ]]
}

@test "counting does not execute the tests" {
    printf '#!/usr/bin/env bats\n@test "side effect" { touch "%s/ran"; }\n' "$TMP" \
        > "$TMP/tests/alpha/z.bats"
    run "$COUNT"
    [ "$status" -eq 0 ]
    [ ! -e "$TMP/ran" ]
}

@test "--update writes the baseline" {
    run "$COUNT" --update
    [ "$status" -eq 0 ]
    grep -q '^alpha	2$' "$NIVUUS_COUNT_BASELINE"
    grep -q '^beta	1$'  "$NIVUUS_COUNT_BASELINE"
}

@test "--check passes when counts are unchanged" {
    "$COUNT" --update
    run "$COUNT" --check
    [ "$status" -eq 0 ]
}

@test "--check fails when a suite loses tests" {
    "$COUNT" --update
    rm "$TMP/tests/alpha/x.bats"
    run "$COUNT" --check
    [ "$status" -ne 0 ]
    [[ "$output" == *"alpha"* ]]
    [[ "$output" == *"2"* ]]
}

@test "--check passes and tells how to update when a suite gains tests" {
    "$COUNT" --update
    printf '#!/usr/bin/env bats\n@test "new" { true; }\n' > "$TMP/tests/beta/new.bats"
    run "$COUNT" --check
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-count --update"* ]]
}

@test "--check fails loudly when a whole suite disappears" {
    "$COUNT" --update
    rm -rf "$TMP/tests/beta"
    run "$COUNT" --check
    [ "$status" -ne 0 ]
    [[ "$output" == *"beta"* ]]
}

@test "the real repository baseline is committed and honoured" {
    # Le cliquet ne protège de rien si la baseline n'existe pas.
    [ -f "$ROOT/tests/baseline-counts.tsv" ]
    run env -u NIVUUS_TESTS_DIR -u NIVUUS_COUNT_BASELINE -u NIVUUS_COUNT_SUITES "$COUNT" --check
    [ "$status" -eq 0 ]
}
