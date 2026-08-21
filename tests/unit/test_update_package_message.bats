#!/usr/bin/env bats
# En mode paquet, « nivuus update » affiche la commande du gestionnaire,
# ne télécharge rien, et SORT EN 0.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TMP="$(mktemp -d)"
    DIR="$TMP/tree"
    mkdir -p "$DIR/config"
    cp "$ROOT/config/20-autoupdate.zsh" "$DIR/config/"
    printf '3.2.0\n' > "$DIR/.version"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    rm -f "$ROOT"/config/*.zwc
}

teardown() { rm -rf "$TMP"; }

marker() { printf '%s\n' "$@" > "$DIR/.nivuus-origin"; }

update() {
    NIVUUS_SHELL_DIR="$DIR" zsh -c "
        ENABLE_AUTOUPDATE=false
        NIVUUS_GITHUB_API='http://127.0.0.1:9'
        source '$DIR/config/20-autoupdate.zsh'
        nivuus-update
    " 2>&1
}

@test "INVARIANT: nivuus-update exits 0 on a package install" {
    marker 'origin=package' 'channel=homebrew' 'package=nivuus-shell' 'version=3.2.0'
    run update
    [ "$status" -eq 0 ]
}

@test "the homebrew channel prints the brew command" {
    marker 'origin=package' 'channel=homebrew' 'package=nivuus-shell' 'version=3.2.0'
    run update
    [[ "$output" == *"brew upgrade nivuus-shell"* ]]
}

@test "the aur channel names both assistants, presuming neither" {
    marker 'origin=package' 'channel=aur' 'package=nivuus-shell' 'version=3.2.0'
    run update
    [[ "$output" == *"yay"* ]]
    [[ "$output" == *"paru"* ]]
}

@test "the deb channel prints an apt command" {
    marker 'origin=package' 'channel=deb' 'package=nivuus-shell' 'version=3.2.0'
    run update
    [[ "$output" == *"apt"* ]]
}

@test "the installed version is shown" {
    marker 'origin=package' 'channel=homebrew' 'package=nivuus-shell' 'version=3.2.0'
    run update
    [[ "$output" == *"3.2.0"* ]]
}

@test "the way back to automatic updates is offered, not hidden" {
    # Un refus sans issue est un bug d'UX : on donne la sortie exacte.
    marker 'origin=package' 'channel=homebrew' 'package=nivuus-shell' 'version=3.2.0'
    run update
    [[ "$output" == *"brew uninstall nivuus-shell"* ]]
    [[ "$output" == *"install.sh"* ]]
}

@test "nothing is downloaded: no temp tree, no backup" {
    marker 'origin=package' 'channel=deb' 'package=nivuus-shell' 'version=3.2.0'
    run update
    [[ "$output" != *"Downloading"* ]]
    [[ "$output" != *"Backup created"* ]]
    [ ! -d "$HOME/.nivuus-backups" ]
}

@test "a SOURCE install is unaffected (no regression on the main path)" {
    run update
    [[ "$output" != *"gère les mises à jour"* ]]
}
