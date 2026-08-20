#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"; source "$LIB/detect.sh"
    source "$LIB/manifest.sh"; source "$LIB/zshrc.sh"; source "$LIB/steps.sh"
    TMP="$(mktemp -d)"
    export NIVUUS_STATE_DIR="$TMP/state"
    unset NIVUUS_DRY_RUN
    nivuus_manifest_begin user "$TMP/install"

    # Faux arbre source
    SRC="$TMP/src"
    mkdir -p "$SRC/config" "$SRC/themes" "$SRC/bin"
    printf 'core\n'  > "$SRC/config/00-core.zsh"
    printf 'junk\n'  > "$SRC/config/00-core.zsh.zwc"
    printf 'nord\n'  > "$SRC/themes/nord.zsh"
    printf 'hc\n'    > "$SRC/bin/healthcheck"
    printf 'main\n'  > "$SRC/.zshrc"
    printf '3.0.0\n' > "$SRC/.version"
}

teardown() { rm -rf "$TMP"; }

@test "copy_tree copies config, themes and bin" {
    nivuus_step_copy_tree "$SRC" "$TMP/install"
    [ -f "$TMP/install/config/00-core.zsh" ]
    [ -f "$TMP/install/themes/nord.zsh" ]
    [ -f "$TMP/install/bin/healthcheck" ]
    [ -f "$TMP/install/.zshrc" ]
}

@test "copy_tree excludes .zwc files" {
    nivuus_step_copy_tree "$SRC" "$TMP/install"
    [ ! -f "$TMP/install/config/00-core.zsh.zwc" ]
}

@test "copy_tree records every copied file in the manifest" {
    nivuus_step_copy_tree "$SRC" "$TMP/install"
    nivuus_manifest_commit
    run grep -c "00-core.zsh" "$NIVUUS_MANIFEST"
    [ "$output" = "1" ]
}

@test "copy_tree is idempotent: a second run records nothing new" {
    nivuus_step_copy_tree "$SRC" "$TMP/install"
    nivuus_manifest_commit
    first="$(grep -c . "$NIVUUS_MANIFEST")"
    nivuus_manifest_begin user "$TMP/install"
    nivuus_step_copy_tree "$SRC" "$TMP/install"
    nivuus_manifest_commit
    second="$(grep -c . "$NIVUUS_MANIFEST")"
    [ "$second" -lt "$first" ]
}

@test "write_zshrc preserves existing user content" {
    printf 'export MINE=1\n' > "$TMP/.zshrc"
    nivuus_step_write_zshrc "$TMP/.zshrc" "$TMP/install"
    run grep -c "export MINE=1" "$TMP/.zshrc"
    [ "$output" = "1" ]
    run grep -c ">>> nivuus shell >>>" "$TMP/.zshrc"
    [ "$output" = "1" ]
}

@test "write_zshrc creates the file when absent" {
    nivuus_step_write_zshrc "$TMP/new-zshrc" "$TMP/install"
    [ -f "$TMP/new-zshrc" ]
    run grep -c ">>> nivuus shell >>>" "$TMP/new-zshrc"
    [ "$output" = "1" ]
}

@test "write_zshrc fails on a corrupt file without modifying it" {
    printf '# >>> nivuus shell >>>\nbroken\n' > "$TMP/.zshrc"
    before="$(cat "$TMP/.zshrc")"
    run nivuus_step_write_zshrc "$TMP/.zshrc" "$TMP/install"
    [ "$status" -eq 1 ]
    [ "$(cat "$TMP/.zshrc")" = "$before" ]
}

@test "write_version writes the version file" {
    nivuus_step_write_version "$SRC" "$TMP/install"
    [ "$(cat "$TMP/install/.version")" = "3.0.0" ]
}

@test "check_required_deps succeeds when zsh, git and curl are present" {
    if ! command -v zsh >/dev/null || ! command -v git >/dev/null || ! command -v curl >/dev/null; then
        skip "dépendances absentes dans cet environnement"
    fi
    run nivuus_step_check_required_deps
    [ "$status" -eq 0 ]
}

@test "check_required_deps fails and reports when dependencies are missing" {
    mkdir -p "$TMP/emptybin"
    run bash -c "
        PATH='$TMP/emptybin'
        source '$LIB/log.sh'
        source '$LIB/steps.sh'
        nivuus_step_check_required_deps
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"zsh"* ]]
    [[ "$output" == *"git"* ]]
    [[ "$output" == *"curl"* ]]
}

@test "check_required_deps never executes a package manager" {
    mkdir -p "$TMP/fakebin"
    # Tripwires: if any of these is executed, it leaves evidence.
    for tool in sudo apt-get dnf pacman brew; do
        printf '#!/bin/sh\ntouch "%s/EXECUTED-%s"\n' "$TMP" "$tool" > "$TMP/fakebin/$tool"
        chmod +x "$TMP/fakebin/$tool"
    done
    run bash -c "
        PATH='$TMP/fakebin'
        source '$LIB/log.sh'
        source '$LIB/steps.sh'
        nivuus_step_check_required_deps
    "
    [ "$status" -eq 1 ]
    run ls "$TMP"
    [[ "$output" != *"EXECUTED-"* ]]
}
