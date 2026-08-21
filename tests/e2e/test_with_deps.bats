#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"
    mkdir -p "$HOME" "$TMP/bin"
    export NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"
    # Faux gestionnaire de paquets : trace son appel, n'installe rien.
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/APT_CALLS"\n' "$TMP" > "$TMP/bin/apt-get"
    chmod +x "$TMP/bin/apt-get"
    printf '#!/bin/sh\nshift 0\nexec "$@"\n' > "$TMP/bin/sudo"
    chmod +x "$TMP/bin/sudo"
    export PATH="$TMP/bin:$PATH"
}

teardown() { rm -rf "$TMP"; }

@test "without --with-deps nothing is ever installed" {
    run "$NIVUUS" install --yes --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/APT_CALLS" ]
}

@test "without --with-deps the missing extras are still suggested as a copyable line" {
    run "$NIVUUS" install --yes --no-minimal --prefix "$TMP/target"
    [[ "$output" == *"apt-get install"* ]]
}

@test "--with-deps runs one grouped command and records a PKG entry per package" {
    run "$NIVUUS" install --yes --no-minimal --with-deps --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ -f "$TMP/APT_CALLS" ]
    # Une seule invocation, groupée.
    [ "$(wc -l < "$TMP/APT_CALLS" | tr -d ' ')" -eq 1 ]
    run grep -c "^PKG" "$NIVUUS_STATE_DIR/manifest.tsv"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "--with-deps in --dry-run installs nothing and writes no manifest" {
    run "$NIVUUS" install --yes --no-minimal --with-deps --dry-run --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/APT_CALLS" ]
    [ ! -e "$NIVUUS_STATE_DIR" ]
    [[ "$output" == *"dry-run"* ]]
}

@test "--minimal skips the extras entirely, even with --with-deps" {
    run "$NIVUUS" install --yes --minimal --with-deps --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/APT_CALLS" ]
    [[ "$output" != *"apt-get install"* ]]
}

@test "uninstall never removes a package it recorded" {
    "$NIVUUS" install --yes --no-minimal --with-deps --prefix "$TMP/target"
    rm -f "$TMP/APT_CALLS"
    run "$NIVUUS" uninstall --yes --purge
    [ "$status" -eq 0 ]
    [ ! -f "$TMP/APT_CALLS" ]
}

@test "install.sh forwards --with-deps" {
    run "$ROOT/install.sh" --non-interactive --with-deps
    [ "$status" -eq 0 ]
}
