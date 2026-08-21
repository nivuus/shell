#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/bin"
    # Chemin absolu : `env PATH=... bash` résoudrait `bash` dans le PATH
    # fabriqué (qui ne contient volontairement que les faux binaires).
    BASH_ABS="$(command -v bash)"
}

teardown() { rm -rf "$TMP"; }

# Fabrique un PATH ne contenant QUE les commandes nommées.
fake_path() {
    rm -rf "$TMP/bin"; mkdir -p "$TMP/bin"
    local c
    for c in "$@"; do
        printf '#!/bin/sh\n: > "%s/EXECUTED-%s"\n' "$TMP" "$c" > "$TMP/bin/$c"
        chmod +x "$TMP/bin/$c"
    done
}

deps() {   # deps "<commandes du PATH>" "<appel>"
    fake_path $1
    run env PATH="$TMP/bin" "$BASH_ABS" -c "source '$LIB/log.sh'; source '$LIB/detect.sh'; \
                                     source '$LIB/deps.sh'; $2"
}

@test "pkg_manager finds each supported manager" {
    deps "apt-get" "nivuus_pkg_manager"; [ "$output" = "apt-get" ]
    deps "dnf"     "nivuus_pkg_manager"; [ "$output" = "dnf" ]
    deps "pacman"  "nivuus_pkg_manager"; [ "$output" = "pacman" ]
    deps "apk"     "nivuus_pkg_manager"; [ "$output" = "apk" ]
    deps "zypper"  "nivuus_pkg_manager"; [ "$output" = "zypper" ]
    deps "brew"    "nivuus_pkg_manager"; [ "$output" = "brew" ]
}

@test "pkg_manager prefers the system manager over brew" {
    deps "apt-get brew" "nivuus_pkg_manager"
    [ "$output" = "apt-get" ]
}

@test "pkg_manager fails when there is none" {
    deps "" "nivuus_pkg_manager"
    [ "$status" -eq 1 ]
}

@test "install_cmd emits the exact command per manager" {
    deps "apt-get sudo id" "nivuus_pkg_install_cmd fzf"
    [[ "$output" == *"apt-get install"* ]]
    [[ "$output" == *"fzf"* ]]

    deps "apk sudo id" "nivuus_pkg_install_cmd fzf bat"
    [[ "$output" == *"apk add"* ]]
    [[ "$output" == *"fzf bat"* ]]

    deps "pacman sudo id" "nivuus_pkg_install_cmd fzf"
    [[ "$output" == *"pacman -S"* ]]
}

@test "install_cmd never prefixes brew with sudo" {
    deps "brew id" "nivuus_pkg_install_cmd fzf"
    [[ "$output" == *"brew install fzf"* ]]
    [[ "$output" != *"sudo"* ]]
}

@test "install_cmd omits sudo when sudo is unavailable" {
    # Pas de sudo dans le PATH : la commande reste copiable, sans préfixe
    # inventé. (Le cas root est couvert par la même branche : id -u = 0.)
    deps "apt-get" "nivuus_pkg_install_cmd fzf"
    [[ "$output" == *"apt-get install"* ]]
    [[ "$output" != *"sudo"* ]]
}

@test "deps_missing lists only what is absent" {
    deps "zsh git" "nivuus_deps_missing required"
    [ "$output" = "curl" ]
}

@test "check_required fails, names every missing package and shows the command" {
    deps "apt-get sudo" "nivuus_deps_check_required 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"zsh"* ]]
    [[ "$output" == *"git"* ]]
    [[ "$output" == *"curl"* ]]
    [[ "$output" == *"apt-get install"* ]]
}

@test "check_required succeeds when everything is present" {
    deps "zsh git curl" "nivuus_deps_check_required"
    [ "$status" -eq 0 ]
}

@test "nothing in deps.sh ever executes a package manager or sudo" {
    for mgr in apt-get dnf pacman apk zypper brew; do
        rm -f "$TMP"/EXECUTED-*
        deps "$mgr sudo" "nivuus_deps_check_required; nivuus_deps_suggest recommended; \
                          nivuus_deps_suggest optional; true"
        run ls "$TMP"
        [[ "$output" != *"EXECUTED-"* ]]
    done
}

@test "deps_suggest is silent when nothing is missing" {
    deps "zsh git curl fzf" "nivuus_deps_suggest recommended"
    [ "$output" = "" ]
}
