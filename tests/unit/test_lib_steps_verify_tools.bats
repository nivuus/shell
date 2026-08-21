#!/usr/bin/env bats

load '../helpers/signing'

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"; source "$LIB/deps.sh"; source "$LIB/steps.sh"
    TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

@test "the step is a thin facade over the deps policy" {
    # Même structure que nivuus_step_check_required_deps : la politique
    # de dépendances vit dans lib/deps.sh, steps.sh n'expose qu'un nom.
    run type nivuus_deps_check_verify_tools
    [ "$status" -eq 0 ]
    run type nivuus_step_check_verify_tools
    [ "$status" -eq 0 ]
}

@test "check_verify_tools succeeds silently when openssl is present" {
    command -v openssl >/dev/null || skip "openssl absent de cet environnement"
    run nivuus_step_check_verify_tools
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "check_verify_tools warns but NEVER fails when both tools are missing" {
    fake="$(mkfakepath "$TMP/bin" bash sh grep awk cat)"
    run env PATH="$fake" bash -c \
        "source '$LIB/log.sh'; source '$LIB/deps.sh'; source '$LIB/steps.sh'; nivuus_step_check_verify_tools; echo rc=\$?"
    # Consultative : une machine sans openssl doit pouvoir installer Nivuus.
    [[ "$output" == *"rc=0"* ]]
}

@test "the warning names the consequence and the remedy" {
    fake="$(mkfakepath "$TMP/bin" bash sh grep awk cat)"
    run env PATH="$fake" bash -c \
        "source '$LIB/log.sh'; source '$LIB/deps.sh'; source '$LIB/steps.sh'; nivuus_step_check_verify_tools 2>&1"
    [[ "$output" == *"openssl"* ]]
    [[ "$output" == *"ssh-keygen"* ]]
    [[ "$output" == *"jour"* ]]     # « mise à jour automatique … inactive »
}
