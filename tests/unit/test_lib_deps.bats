#!/usr/bin/env bats
# lib/deps.sh : fonctions pures, rien ici n'exécute un gestionnaire de paquets.

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/detect.sh"; source "$LIB/deps.sh"
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

@test "optional deps include the zsh plugins the config modules load" {
    for t in zsh-autosuggestions zsh-syntax-highlighting; do
        [[ " $NIVUUS_DEPS_OPTIONAL " == *" $t "* ]]
    done
}

@test "plugin_find locates a plugin under the root and sets REPLY" {
    export NIVUUS_PLUGIN_ROOT="$TMP/plugins"
    mkdir -p "$TMP/plugins/zsh-autosuggestions"
    : > "$TMP/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
    nivuus_plugin_find zsh-autosuggestions
    [ "$REPLY" = "$TMP/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]
    run nivuus_plugin_find zsh-syntax-highlighting
    [ "$status" -eq 1 ]
}

@test "dep_present looks for a zsh plugin where the modules load it, not on PATH" {
    export NIVUUS_PLUGIN_ROOT="$TMP/plugins"
    mkdir -p "$TMP/bin" "$TMP/plugins/zsh-syntax-highlighting"
    : > "$TMP/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
    printf '#!/bin/sh\n' > "$TMP/bin/zsh-autosuggestions"; chmod +x "$TMP/bin/zsh-autosuggestions"
    run bash -c "PATH='$TMP/bin'; source '$LIB/deps.sh'
        nivuus_deps_missing zsh-autosuggestions zsh-syntax-highlighting"
    [ "$output" = "zsh-autosuggestions" ]
}

@test "deps.sh works under zsh, as the config modules source it" {
    command -v zsh >/dev/null || skip "zsh absent"
    mkdir -p "$TMP/plugins/zsh-autosuggestions"
    : > "$TMP/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
    run zsh -fc "NIVUUS_PLUGIN_ROOT='$TMP/plugins' NIVUUS_UID=1000
        source '$LIB/detect.sh'; source '$LIB/deps.sh'
        nivuus_plugin_find zsh-autosuggestions && print -r -- \$REPLY
        missing=\$(nivuus_deps_missing zsh-autosuggestions zsh-syntax-highlighting)
        nivuus_pkg_hint_cmd apt-get \${=missing} fd"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$TMP/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]
    [ "${lines[1]}" = "sudo apt-get install -y --no-install-recommends zsh-syntax-highlighting fd-find" ]
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

@test "pkg_name keeps the zsh plugin names on every manager" {
    for m in apt-get dnf yum pacman zypper apk brew; do
        [ "$(nivuus_pkg_name "$m" zsh-autosuggestions)" = "zsh-autosuggestions" ]
        [ "$(nivuus_pkg_name "$m" zsh-syntax-highlighting)" = "zsh-syntax-highlighting" ]
    done
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

@test "pkg_hint_cmd maps the names and prefixes sudo only when needed" {
    NIVUUS_UID=1000
    [ "$(nivuus_pkg_hint_cmd apt-get fd ripgrep)" = "sudo apt-get install -y --no-install-recommends fd-find ripgrep" ]
    [ "$(nivuus_pkg_hint_cmd brew fd)" = "brew install fd" ]
    NIVUUS_UID=0
    [ "$(nivuus_pkg_hint_cmd pacman fd)" = "pacman -S --noconfirm --needed fd" ]
}

@test "pkg_hint_cmd leaves out what the manager does not ship, empty when nothing is left" {
    NIVUUS_UID=0
    [ "$(nivuus_pkg_hint_cmd zypper timg jq)" = "zypper --non-interactive install jq" ]
    [ "$(nivuus_pkg_hint_cmd zypper timg)" = "" ]
    [ "$(nivuus_pkg_hint_cmd '' jq)" = "" ]
}
