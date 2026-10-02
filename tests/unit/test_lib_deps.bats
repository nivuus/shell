#!/usr/bin/env bats
# lib/deps.sh : fonctions pures, rien ici n'exécute un gestionnaire de paquets.

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/deps.sh"
    TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

@test "required deps are zsh, git and curl" {
    [ "$NIVUUS_DEPS_REQUIRED" = "zsh git curl" ]
}

@test "optional deps cover the tools the modules look for" {
    for t in jq fzf eza bat fd ripgrep timg; do
        [[ " $NIVUUS_DEPS_OPTIONAL " == *" $t "* ]]
    done
}

@test "dep_present accepts the Debian names batcat and fdfind" {
    mkdir -p "$TMP/bin"
    for t in batcat fdfind; do printf '#!/bin/sh\n' > "$TMP/bin/$t"; chmod +x "$TMP/bin/$t"; done
    run bash -c "PATH='$TMP/bin'; source '$LIB/deps.sh'; nivuus_dep_present bat && nivuus_dep_present fd"
    [ "$status" -eq 0 ]
}

@test "deps_missing lists only the absent tools, in order" {
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\n' > "$TMP/bin/git"; chmod +x "$TMP/bin/git"
    run bash -c "PATH='$TMP/bin'; source '$LIB/deps.sh'; nivuus_deps_missing zsh git curl"
    [ "$output" = "zsh curl" ]
}

@test "deps_missing is empty when everything is present" {
    mkdir -p "$TMP/bin"
    for t in zsh git curl; do printf '#!/bin/sh\n' > "$TMP/bin/$t"; chmod +x "$TMP/bin/$t"; done
    run bash -c "PATH='$TMP/bin'; source '$LIB/deps.sh'; nivuus_deps_missing zsh git curl"
    [ "$output" = "" ]
}

@test "pkg_name maps fd to fd-find on apt and dnf, fd elsewhere" {
    [ "$(nivuus_pkg_name apt-get fd)" = "fd-find" ]
    [ "$(nivuus_pkg_name dnf fd)" = "fd-find" ]
    [ "$(nivuus_pkg_name pacman fd)" = "fd" ]
    [ "$(nivuus_pkg_name brew fd)" = "fd" ]
}

@test "pkg_name returns an empty name for a tool the manager does not ship" {
    [ "$(nivuus_pkg_name zypper timg)" = "" ]
    [ "$(nivuus_pkg_name apk grc)" = "" ]
}

@test "pkg_name passes plain names through" {
    [ "$(nivuus_pkg_name apt-get zsh)" = "zsh" ]
    [ "$(nivuus_pkg_name brew ripgrep)" = "ripgrep" ]
}

@test "pkg_install_cmd is non-interactive for every manager" {
    [ "$(nivuus_pkg_install_cmd apt-get zsh git)" = "apt-get install -y --no-install-recommends zsh git" ]
    [ "$(nivuus_pkg_install_cmd dnf zsh)" = "dnf install -y zsh" ]
    [ "$(nivuus_pkg_install_cmd pacman zsh)" = "pacman -S --noconfirm --needed zsh" ]
    [ "$(nivuus_pkg_install_cmd zypper zsh)" = "zypper --non-interactive install zsh" ]
    [ "$(nivuus_pkg_install_cmd apk zsh)" = "apk add zsh" ]
    [ "$(nivuus_pkg_install_cmd brew zsh)" = "brew install zsh" ]
}

@test "pkg_install_cmd is empty for an unknown manager" {
    [ "$(nivuus_pkg_install_cmd nix zsh)" = "" ]
}

@test "pkg_refresh_cmd exists for apt and apk only" {
    [ "$(nivuus_pkg_refresh_cmd apt-get)" = "apt-get update -qq" ]
    [ "$(nivuus_pkg_refresh_cmd apk)" = "apk update -q" ]
    [ "$(nivuus_pkg_refresh_cmd brew)" = "" ]
    [ "$(nivuus_pkg_refresh_cmd dnf)" = "" ]
}

@test "brew is the only manager that must not run as root" {
    run nivuus_pkg_needs_root brew
    [ "$status" -ne 0 ]
    for m in apt-get dnf pacman zypper apk; do
        run nivuus_pkg_needs_root "$m"
        [ "$status" -eq 0 ]
    done
}
