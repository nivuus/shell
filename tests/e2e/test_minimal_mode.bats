#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\n: > "%s/CHSH_RAN"\n' "$TMP" > "$TMP/bin/chsh"; chmod +x "$TMP/bin/chsh"
    export PATH="$TMP/bin:$PATH"
}

teardown() { rm -rf "$TMP"; }

@test "minimal mode is chosen automatically without a TTY" {
    run "$NIVUUS" install --yes --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [[ "$output" == *"minimal"* ]]
    [ ! -f "$TMP/CHSH_RAN" ]
}

@test "the minimal block exports NIVUUS_MINIMAL" {
    "$NIVUUS" install --yes --minimal --prefix "$TMP/target"
    run grep -c 'export NIVUUS_MINIMAL=1' "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "a full install writes no NIVUUS_MINIMAL export" {
    "$NIVUUS" install --yes --no-minimal --prefix "$TMP/target"
    run grep -c 'NIVUUS_MINIMAL' "$HOME/.zshrc"
    [ "$output" = "0" ]
}

@test "switching from minimal to full rewrites the block, not the file" {
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    "$NIVUUS" install --yes --minimal --prefix "$TMP/target"
    "$NIVUUS" install --yes --no-minimal --prefix "$TMP/target"
    run grep -c 'NIVUUS_MINIMAL' "$HOME/.zshrc"
    [ "$output" = "0" ]
    run grep -c 'export MINE=1' "$HOME/.zshrc"
    [ "$output" = "1" ]
    run grep -c '>>> nivuus shell >>>' "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "a minimal install stays fully reversible" {
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    "$NIVUUS" install --yes --minimal --prefix "$TMP/target"
    "$NIVUUS" uninstall --yes --purge
    [ "$(cat "$HOME/.zshrc")" = "export MINE=1" ]
}

@test "a minimal install still starts a working shell" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not available"
    "$NIVUUS" install --yes --minimal --prefix "$TMP/target"
    run zsh -i -c 'echo MINIMAL_OK'
    [ "$status" -eq 0 ]
    [[ "$output" == *"MINIMAL_OK"* ]]
}
