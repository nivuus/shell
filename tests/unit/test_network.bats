#!/usr/bin/env bats

# Unit tests for Network module (config/12-network.zsh)

load "${BATS_TEST_DIRNAME}/../helpers/pty"

setup() {
    source "$NIVUUS_SHELL_DIR/config/12-network.zsh"
}

# =============================================================================
# Module Loading Tests
# =============================================================================

@test "Network module loads without errors" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/12-network.zsh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

# =============================================================================
# IP Address Tests
# =============================================================================

@test "myip function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/12-network.zsh' && typeset -f myip"
    [ "$status" -eq 0 ]
}

@test "myip uses ipify API" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'ipify' config/12-network.zsh"
    [ "$status" -eq 0 ]
}

@test "myip uses curl" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 3 'myip()' config/12-network.zsh | grep 'curl'"
    [ "$status" -eq 0 ]
}

@test "myip shows error on failure" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 5 'myip()' config/12-network.zsh | grep 'Failed to retrieve'"
    [ "$status" -eq 0 ]
}

@test "localip function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/12-network.zsh' && typeset -f localip"
    [ "$status" -eq 0 ]
}

@test "localip supports macOS" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'darwin' config/12-network.zsh | head -3"
    [ "$status" -eq 0 ]
}

@test "localip supports Linux" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 'localip()' config/12-network.zsh | grep 'hostname -I'"
    [ "$status" -eq 0 ]
}

@test "localip filters localhost" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 'localip()' config/12-network.zsh | grep '127.0.0.1'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Port Information Tests
# =============================================================================

@test "ports function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/12-network.zsh' && typeset -f ports"
    [ "$status" -eq 0 ]
}

@test "ports supports macOS (lsof)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 'ports()' config/12-network.zsh | grep 'lsof'"
    [ "$status" -eq 0 ]
}

@test "ports supports Linux (ss)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 15 'ports()' config/12-network.zsh | grep 'ss -tulpn'"
    [ "$status" -eq 0 ]
}

@test "ports falls back to netstat" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 15 'ports()' config/12-network.zsh | grep 'netstat -tulpn'"
    [ "$status" -eq 0 ]
}

@test "ports checks for command availability" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 15 'ports()' config/12-network.zsh | grep 'command -v'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Weather Tests
# =============================================================================

@test "weather function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/12-network.zsh' && typeset -f weather"
    [ "$status" -eq 0 ]
}

@test "weather uses wttr.in" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'wttr.in' config/12-network.zsh"
    [ "$status" -eq 0 ]
}

@test "weather supports city argument" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 'weather()' config/12-network.zsh | grep 'city='"
    [ "$status" -eq 0 ]
}

@test "weather uses geolocation by default" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 'weather()' config/12-network.zsh | grep 'if.*-z.*city'"
    [ "$status" -eq 0 ]
}

@test "weatherfull function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/12-network.zsh' && typeset -f weatherfull"
    [ "$status" -eq 0 ]
}

@test "weatherfull shows detailed forecast" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 3 'weatherfull()' config/12-network.zsh | grep 'wttr.in'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Network Testing Aliases
# =============================================================================

@test "at a terminal, ping alias is defined with count" {
    pty_run "source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/12-network.zsh'; alias ping"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-c 5"* ]]
}

@test "speedtest alias checks for speedtest-cli" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'speedtest-cli' config/12-network.zsh"
    [ "$status" -eq 0 ]
}

@test "speedtest alias uses --simple flag" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'speedtest-cli --simple' config/12-network.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# DNS Tools Tests
# =============================================================================

@test "dns function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/12-network.zsh' && typeset -f dns"
    [ "$status" -eq 0 ]
}

@test "dns shows usage when no argument" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 5 'dns()' config/12-network.zsh | grep 'Usage:'"
    [ "$status" -eq 0 ]
}

@test "dns supports dig" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 'dns()' config/12-network.zsh | grep 'dig'"
    [ "$status" -eq 0 ]
}

@test "dns falls back to nslookup" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 20 'dns()' config/12-network.zsh | grep 'nslookup'"
    [ "$status" -eq 0 ]
}

@test "dns checks for command availability" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 20 'dns()' config/12-network.zsh | grep -c 'command -v'"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 2 ]
}

# =============================================================================
# HTTP Tools Tests
# =============================================================================

@test "download alias is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'alias download=' config/12-network.zsh"
    [ "$status" -eq 0 ]
}

@test "download uses wget if available" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'wget -c' config/12-network.zsh"
    [ "$status" -eq 0 ]
}

@test "download falls back to curl" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'curl -O' config/12-network.zsh"
    [ "$status" -eq 0 ]
}

@test "download supports resume (-C)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -E '(wget -c|curl.*-C)' config/12-network.zsh"
    [ "$status" -eq 0 ]
}

@test "headers function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/12-network.zsh' && typeset -f headers"
    [ "$status" -eq 0 ]
}

@test "headers shows usage when no argument" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 5 'headers()' config/12-network.zsh | grep 'Usage:'"
    [ "$status" -eq 0 ]
}

@test "headers uses curl -sI" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 8 'headers()' config/12-network.zsh | grep 'curl -sI'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Coverage Tests
# =============================================================================

@test "Module defines at least 7 main functions" {
    count=$(zsh -c "source '$NIVUUS_SHELL_DIR/config/12-network.zsh' && typeset -f | grep -c -E '(myip|localip|ports|weather|weatherfull|dns|headers)'" || echo "0")
    [ "$count" -ge 7 ]
}

@test "Module has proper error handling" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c '✗' config/12-network.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 3 ]
}

@test "Module supports both macOS and Linux" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'OSTYPE.*darwin' config/12-network.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 2 ]
}

@test "Module checks for command availability before use" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'command -v' config/12-network.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 5 ]
}

@test "Module has usage messages for user-facing functions" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'Usage:' config/12-network.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 2 ]
}
