#!/usr/bin/env bats
# Le chemin bin/nivuus doit répondre sans déléguer à un shell interactif :
# en conteneur, en CI et en cron, « zsh -ic » n'est pas garanti.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    DIR="$TMP/share/nivuus-shell"
    mkdir -p "$DIR"
    cp -a "$ROOT"/lib "$ROOT"/bin "$DIR"/
    printf '3.2.0\n' > "$DIR/.version"
}

teardown() { rm -rf "$TMP"; }

@test "INVARIANT: bin/nivuus update exits 0 on a package install" {
    printf 'origin=package\nchannel=aur\npackage=nivuus-shell\nversion=3.2.0\n' \
        > "$DIR/.nivuus-origin"
    run env NIVUUS_SHELL_DIR="$DIR" "$DIR/bin/nivuus" update
    [ "$status" -eq 0 ]
    [[ "$output" == *"nivuus-shell"* ]]
}

@test "bin/nivuus update does not need an interactive zsh in package mode" {
    printf 'origin=package\nchannel=deb\npackage=nivuus-shell\nversion=3.2.0\n' \
        > "$DIR/.nivuus-origin"
    # PATH sans zsh : si le code déléguait à « exec zsh -ic », il échouerait.
    run env NIVUUS_SHELL_DIR="$DIR" PATH="/usr/bin:/bin" "$DIR/bin/nivuus" update
    [ "$status" -eq 0 ]
}
