#!/usr/bin/env bats
#
# Garde-fou : le budget de démarrage doit être VRAIMENT vérifié en CI.
# Un test de performance qui se saute silencieusement est pire que pas de test :
# il produit un vert qui ne prouve rien.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    export NIVUUS_SHELL_DIR="$ROOT"
    # Workflows possédés par le plan de phase 4 (release.yml : Task 12).
    OWNED="$ROOT/.github/workflows/tests.yml"
}

@test "the startup test does not skip itself under CI" {
    run env CI=true GITHUB_ACTIONS=true \
        bats --formatter tap13 --filter-tags portable "$ROOT/tests/performance/test_startup.bats"
    [ "$status" -eq 0 ]
    # Un filtre qui ne matche rien sortirait aussi en 0 : exiger le test.
    [[ "$output" == *"1..1"* ]]
    [[ "$output" == *"ok 1"* ]]
    [[ "$output" != *"# skip"* ]]
    [[ "$output" != *"# SKIP"* ]]
}

@test "no test file skips itself merely because CI is set" {
    # Le motif exact qu'on vient de retirer ; il ne doit pas revenir ailleurs.
    # --exclude : ce fichier-ci contient le motif, forcément.
    run grep -rn --exclude="$(basename "$BATS_TEST_FILENAME")" \
        'skip "Skipped in CI' "$ROOT/tests"
    [ "$status" -ne 0 ]
}

@test "measure_startup reports a median over several runs" {
    grep -q 'median' "$ROOT/tests/performance/measure_startup.sh"
    run env NIVUUS_STARTUP_RUNS=3 "$ROOT/tests/performance/measure_startup.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "the enforced budget is 300 ms and comes from one variable" {
    grep -q 'NIVUUS_STARTUP_BUDGET_MS' "$ROOT/tests/performance/test_startup.bats"
    run env NIVUUS_STARTUP_BUDGET_MS=1 bats --filter-tags portable "$ROOT/tests/performance/test_startup.bats"
    [ "$status" -ne 0 ]   # un budget absurde DOIT faire échouer : la garde mord
}

@test "no test workflow interprets bats output to decide if performance passed" {
    run grep -n "Validate startup time requirement" "$OWNED"
    [ "$status" -ne 0 ]
}
