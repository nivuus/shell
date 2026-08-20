#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    unset NIVUUS_QUIET NO_COLOR
}

@test "log_info writes to stdout" {
    source "$LIB/log.sh"
    run log_info "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
}

@test "log_error writes to stderr, not stdout" {
    source "$LIB/log.sh"
    run bash -c "source '$LIB/log.sh'; log_error 'boom' 2>/dev/null"
    [ "$output" = "" ]
}

@test "NIVUUS_QUIET silences log_info but not log_error" {
    run bash -c "export NIVUUS_QUIET=1; source '$LIB/log.sh'; log_info 'quiet'"
    [ "$output" = "" ]
    run bash -c "export NIVUUS_QUIET=1; source '$LIB/log.sh'; log_error 'loud' 2>&1"
    [[ "$output" == *"loud"* ]]
}

@test "no ANSI escapes when not a TTY" {
    run bash -c "source '$LIB/log.sh'; log_ok 'plain'"
    [[ "$output" != *$'\033'* ]]
}

@test "NO_COLOR disables color" {
    run bash -c "export NO_COLOR=1; source '$LIB/log.sh'; log_warn 'nc' 2>&1"
    [[ "$output" != *$'\033'* ]]
}

@test "log_dry prefixes with dry-run marker" {
    run bash -c "source '$LIB/log.sh'; log_dry 'would write /tmp/x'"
    [[ "$output" == *"dry-run"* ]]
    [[ "$output" == *"/tmp/x"* ]]
}
