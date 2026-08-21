#!/usr/bin/env bats
# doctor doit NOMMER la situation en mode paquet : la garde du bloc rend le
# démarrage silencieux, donc le diagnostic à la demande est le seul endroit
# où une installation cassée devient visible.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    SHARED="$TMP/share/nivuus-shell"
    mkdir -p "$SHARED"
    cp -a "$ROOT"/config "$ROOT"/lib "$ROOT"/bin "$SHARED"/
    cp "$ROOT"/.zshrc "$SHARED"/
    printf '3.2.0\n' > "$SHARED/.version"
    DOCTOR="$SHARED/bin/healthcheck"
}

teardown() { rm -rf "$TMP"; }

pkg_marker() {
    printf 'origin=package\nchannel=%s\npackage=nivuus-shell\nversion=3.2.0\n' \
        "${1:-homebrew}" > "$SHARED/.nivuus-origin"
}

block() {
    printf '# >>> nivuus shell >>>\nexport NIVUUS_SHELL_DIR="%s"\n[ -r "$NIVUUS_SHELL_DIR/.zshrc" ] && source "$NIVUUS_SHELL_DIR/.zshrc"\n# <<< nivuus shell <<<\n' \
        "$1" > "$HOME/.zshrc"
}

@test "doctor reports origin source when there is no marker" {
    run env NIVUUS_SHELL_DIR="$SHARED" "$DOCTOR"
    [[ "$output" == *"source"* ]]
}

@test "doctor reports the channel and the package version" {
    pkg_marker aur
    run env NIVUUS_SHELL_DIR="$SHARED" "$DOCTOR"
    [[ "$output" == *"aur"* ]]
    [[ "$output" == *"3.2.0"* ]]
}

@test "doctor names 'package installed, never activated'" {
    pkg_marker
    : > "$HOME/.zshrc"
    run env NIVUUS_SHELL_DIR="$SHARED" "$DOCTOR"
    [[ "$output" == *"nivuus enable"* ]]
}

@test "doctor names 'block present, tree gone' and gives the way out" {
    pkg_marker deb
    block "$TMP/share/nivuus-shell"
    rm -rf "$SHARED"
    run env NIVUUS_SHELL_DIR="$TMP/share/nivuus-shell" "$ROOT/bin/healthcheck"
    [[ "$output" == *"nivuus disable"* ]] || [[ "$output" == *"réinstall"* ]]
}

@test "doctor points at the package manager for a tampered tree, and repairs nothing" {
    pkg_marker homebrew
    block "$SHARED"
    printf 'tampered\n' >> "$SHARED/config/00-core.zsh"
    run env NIVUUS_SHELL_DIR="$SHARED" "$DOCTOR"
    [[ "$output" == *"brew"* ]] || [[ "$output" == *"reinstall"* ]]
    # Rien n'a été réparé : le fichier altéré est toujours là, tel quel.
    grep -q 'tampered' "$SHARED/config/00-core.zsh"
}

@test "doctor mentions that auto-update is disabled in package mode" {
    pkg_marker deb
    block "$SHARED"
    run env NIVUUS_SHELL_DIR="$SHARED" "$DOCTOR"
    [[ "$output" == *"apt"* ]]
}

@test "doctor exits 0 on a healthy package install" {
    pkg_marker homebrew
    block "$SHARED"
    run env NIVUUS_SHELL_DIR="$SHARED" "$DOCTOR"
    [ "$status" -eq 0 ]
}
