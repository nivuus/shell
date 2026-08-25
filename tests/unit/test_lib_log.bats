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

@test "log_dry n'emploie plus de dim" {
    run bash -c "export NIVUUS_CHARTE_TTY=1; source '$LIB/log.sh'; log_dry 'x' | cat -v"
    [[ "$output" != *"[2m"* ]]
}

@test "log_dry marque le prefixe en gras" {
    run bash -c "export NIVUUS_CHARTE_TTY=1; source '$LIB/log.sh'; log_dry 'x' | cat -v"
    [[ "$output" == *"[1m"* ]]
}

@test "log_ok emploie la teinte ok de la charte" {
    run bash -c "export NIVUUS_CHARTE_TTY=1 COLORTERM=truecolor
        source '$LIB/log.sh'; log_ok 'x'"
    [[ "$output" == *"38;2;78;211;154"* ]]
}

@test "log_error emploie la teinte danger de la charte" {
    run bash -c "export NIVUUS_CHARTE_TTY=1 COLORTERM=truecolor
        source '$LIB/log.sh'; log_error 'x' 2>&1"
    [[ "$output" == *"38;2;255;122;133"* ]]
}

@test "log_info emploie la teinte busy de la charte" {
    run bash -c "export NIVUUS_CHARTE_TTY=1 COLORTERM=truecolor
        source '$LIB/log.sh'; log_info 'x'"
    [[ "$output" == *"38;2;122;182;255"* ]]
}

@test "log_warn emploie la teinte warn de la charte" {
    run bash -c "export NIVUUS_CHARTE_TTY=1 COLORTERM=truecolor
        source '$LIB/log.sh'; log_warn 'x' 2>&1"
    [[ "$output" == *"38;2;242;179;61"* ]]
}

@test "chaque helper porte un glyphe lisible en noir et blanc" {
    run bash -c "source '$LIB/log.sh'
        log_info i; log_ok o; log_warn w 2>&1; log_error e 2>&1"
    [[ "$output" == *"·"* ]]
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"!"* ]]
    [[ "$output" == *"✗"* ]]
}

@test "log.sh degrade sans erreur si charte.sh est absent" {
    tmp="$(mktemp -d)"
    cp "$LIB/log.sh" "$tmp/log.sh"
    run bash -c "source '$tmp/log.sh'; log_ok 'sans charte'"
    rm -rf "$tmp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sans charte"* ]]
}
