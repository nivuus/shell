#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    DIR="$TMP/tree"
    mkdir -p "$DIR"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"
    . "$ROOT/lib/origin.sh"
}

teardown() { rm -rf "$TMP"; }

marker() { printf '%s\n' "$@" > "$DIR/.nivuus-origin"; }

@test "no marker at all means origin=source (comportement d'aujourd'hui)" {
    run nivuus_origin "$DIR"
    [ "$status" -eq 0 ]
    [ "$output" = "source" ]
}

@test "no marker at all means not a package install" {
    run nivuus_origin_is_package "$DIR"
    [ "$status" -ne 0 ]
}

@test "origin=package is recognised" {
    marker 'origin=package' 'channel=homebrew' 'package=nivuus-shell' 'version=3.2.0'
    run nivuus_origin "$DIR"
    [ "$output" = "package" ]
    run nivuus_origin_is_package "$DIR"
    [ "$status" -eq 0 ]
}

@test "an unknown origin value degrades to source, never to package" {
    marker 'origin=chaussette'
    run nivuus_origin "$DIR"
    [ "$output" = "source" ]
    run nivuus_origin_is_package "$DIR"
    [ "$status" -ne 0 ]
}

@test "a marker with no origin= line degrades to source" {
    marker 'channel=aur' 'version=3.2.0'
    run nivuus_origin "$DIR"
    [ "$output" = "source" ]
}

@test "an unreadable marker degrades to source, it does not crash" {
    marker 'origin=package'
    chmod 000 "$DIR/.nivuus-origin"
    run nivuus_origin "$DIR"
    [ "$status" -eq 0 ]
    [ "$output" = "source" ]
    chmod 644 "$DIR/.nivuus-origin"
}

@test "fields are read individually" {
    marker 'origin=package' 'channel=aur' 'package=nivuus-shell' 'version=3.2.0'
    run nivuus_origin_field "$DIR" channel
    [ "$output" = "aur" ]
    run nivuus_origin_field "$DIR" version
    [ "$output" = "3.2.0" ]
    run nivuus_origin_field "$DIR" package
    [ "$output" = "nivuus-shell" ]
}

@test "only the first occurrence of a key is used" {
    marker 'channel=aur' 'channel=deb'
    run nivuus_origin_field "$DIR" channel
    [ "$output" = "aur" ]
}

@test "an absent field fails, it does not print garbage" {
    marker 'origin=package'
    run nivuus_origin_field "$DIR" channel
    [ -z "$output" ]
}

@test "channel defaults to unknown when the marker says package but names no channel" {
    marker 'origin=package'
    run nivuus_origin_channel "$DIR"
    [ "$output" = "unknown" ]
}

@test "the update command is derived from the channel, never guessed" {
    marker 'origin=package' 'channel=homebrew' 'package=nivuus-shell'
    run nivuus_origin_update_command "$DIR"
    [[ "$output" == *"brew upgrade nivuus-shell"* ]]

    marker 'origin=package' 'channel=deb' 'package=nivuus-shell'
    run nivuus_origin_update_command "$DIR"
    [[ "$output" == *"apt"* ]]

    # On ne présume pas de yay plutôt que paru : les deux sont nommés.
    marker 'origin=package' 'channel=aur' 'package=nivuus-shell'
    run nivuus_origin_update_command "$DIR"
    [[ "$output" == *"yay"* ]] || [[ "$output" == *"paru"* ]]
}

@test "an unknown channel still yields a usable sentence, never an empty one" {
    marker 'origin=package' 'channel=chaussette' 'package=nivuus-shell'
    run nivuus_origin_update_command "$DIR"
    [ -n "$output" ]
}

@test "a writable tree is reported writable" {
    run nivuus_origin_tree_writable "$DIR"
    [ "$status" -eq 0 ]
}

@test "a read-only tree is reported non writable" {
    # Inopérant en root (root écrit partout) : c'est précisément pour ça que
    # le marqueur existe en plus du garde-fou. On saute plutôt que de mentir.
    [ "$(id -u)" -ne 0 ] || skip "root ignore les permissions d'écriture"
    chmod 500 "$DIR"
    run nivuus_origin_tree_writable "$DIR"
    [ "$status" -ne 0 ]
    chmod 700 "$DIR"
}

@test "a missing tree is reported non writable" {
    run nivuus_origin_tree_writable "$TMP/nexistepas"
    [ "$status" -ne 0 ]
}

@test "INVARIANT: nivuus install never writes origin=package" {
    # Le seul producteur de cette valeur est une recette de paquet. Si cette
    # ligne apparaît un jour dans bin/nivuus, lib/ ou install.sh, le mode
    # paquet devient auto-proclamable et le refus d'auto-update se retourne
    # contre les installations par le one-liner.
    run grep -rn 'origin=package' "$ROOT/bin" "$ROOT/lib" "$ROOT/install.sh"
    [ "$status" -ne 0 ]
}
