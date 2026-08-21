#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"
}

teardown() { rm -rf "$TMP"; }

@test "install works with WSL markers injected" {
    printf 'Linux version 5.15.0-microsoft-standard-WSL2\n' > "$TMP/proc_version"
    run env NIVUUS_PROC_VERSION="$TMP/proc_version" WSL_DISTRO_NAME=Ubuntu \
        "$NIVUUS" install --yes --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ -f "$TMP/target/.zshrc" ]
    run grep -c '>>> nivuus shell >>>' "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "uninstall reverts a WSL install completely" {
    printf 'Linux version 5.15.0-microsoft-standard-WSL2\n' > "$TMP/proc_version"
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    env NIVUUS_PROC_VERSION="$TMP/proc_version" WSL_DISTRO_NAME=Ubuntu \
        "$NIVUUS" install --yes --prefix "$TMP/target"
    env NIVUUS_PROC_VERSION="$TMP/proc_version" WSL_DISTRO_NAME=Ubuntu \
        "$NIVUUS" uninstall --yes --purge
    [ "$(cat "$HOME/.zshrc")" = "export MINE=1" ]
}

@test "install fails with a copyable command when a required dep is missing" {
    mkdir -p "$TMP/bin"
    # PATH sans zsh, mais avec de quoi tourner. `bash` en fait partie :
    # le shebang de bin/nivuus est `/usr/bin/env bash`, donc env le résout
    # dans ce PATH fabriqué et l'installeur ne démarrerait même pas sans lui.
    for c in bash sh cat cp mv rm mkdir rmdir find awk sed grep printf id uname dirname \
             head tail wc tr sort cut mktemp chmod stat sha256sum shasum touch ls date git curl; do
        p="$(command -v "$c" 2>/dev/null)" && ln -sf "$p" "$TMP/bin/$c"
    done
    run env PATH="$TMP/bin" "$NIVUUS" install --yes --prefix "$TMP/target"
    [ "$status" -eq 1 ]
    [[ "$output" == *"zsh"* ]]
    [ ! -e "$TMP/target" ]
    [ ! -e "$NIVUUS_STATE_DIR/manifest.tsv" ]
}

@test "install then uninstall is clean inside an Alpine container" {
    command -v docker >/dev/null 2>&1 || skip "docker unavailable"
    run docker run --rm -v "$ROOT:/src:ro" alpine:3.20 sh -c '
        set -e
        apk add --no-cache bash zsh git curl >/dev/null
        cp -r /src /work && cd /work
        export HOME=/root
        ./bin/nivuus install --yes --prefix "$HOME/.nivuus-shell"
        test -f "$HOME/.nivuus-shell/.zshrc"
        grep -q ">>> nivuus shell >>>" "$HOME/.zshrc"
        zsh -i -c "echo ALPINE_SHELL_OK"
        ./bin/nivuus uninstall --yes --purge
        test ! -e "$HOME/.nivuus-shell"
        echo ALPINE_CLEAN_OK
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALPINE_SHELL_OK"* ]]
    [[ "$output" == *"ALPINE_CLEAN_OK"* ]]
}
