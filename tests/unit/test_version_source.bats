#!/usr/bin/env bats

setup() {
    SCRIPTS="${BATS_TEST_DIRNAME}/../../scripts"
    WORK="$(mktemp -d)"
    cd "$WORK" || return 1
    git init -q -b main .
    git config user.email "test@nivuus.local"
    git config user.name "Test"
    git commit -q --allow-empty -m "chore: initial commit"
}

teardown() {
    [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

@test "falls back to 0.0.0 with no tag" {
    run bash -c "source '$SCRIPTS/version.sh'; current_version"
    [ "$status" -eq 0 ]
    [ "$output" = "0.0.0" ]
}

@test "reads the latest version tag" {
    git tag -a v3.0.0 -m "Release v3.0.0"
    run bash -c "source '$SCRIPTS/version.sh'; current_version"
    [ "$status" -eq 0 ]
    [ "$output" = "3.0.0" ]
}

@test "picks the highest version, not the most recent tag" {
    git tag -a v3.0.0 -m "Release v3.0.0"
    git commit -q --allow-empty -m "chore: another commit"
    git tag -a v3.1.0 -m "Release v3.1.0"
    git commit -q --allow-empty -m "chore: yet another"
    git tag -a v3.0.1 -m "Release v3.0.1"

    run bash -c "source '$SCRIPTS/version.sh'; current_version"
    [ "$status" -eq 0 ]
    [ "$output" = "3.1.0" ]
}

@test "ignores non-version tags" {
    git tag -a nightly -m "Nightly"
    run bash -c "source '$SCRIPTS/version.sh'; current_version"
    [ "$status" -eq 0 ]
    [ "$output" = "0.0.0" ]
}
