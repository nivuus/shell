#!/usr/bin/env bats
#
# bin/nivuus update doit répondre SANS déléguer à « zsh -ic », qui exige un
# shell interactif : un conteneur, une CI ou un cron n'en ont pas.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/etc"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local" NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_UID=0 NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1 NIVUUS_SYSTEM_PROBE_USER=''
    "$ROOT/bin/nivuus" install --system --yes >/dev/null
    export NIVUUS_SHELL_DIR="$TMP/usr/local/share/nivuus-shell"
}

teardown() { rm -rf "$TMP"; }

@test "nivuus update sur un arbre système sort en 0, sans shell interactif" {
    run env NIVUUS_UID=1000 "$ROOT/bin/nivuus" update
    [ "$status" -eq 0 ]
    [[ "$output" == *"sudo nivuus update"* ]]
}

@test "nivuus update ne télécharge rien" {
    # Un faux curl/wget qui journalise : s'il est appelé, le test le dit.
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\necho appelé >> %s/reseau\n' "$TMP" > "$TMP/bin/curl"
    cp "$TMP/bin/curl" "$TMP/bin/wget"; chmod +x "$TMP/bin/curl" "$TMP/bin/wget"
    PATH="$TMP/bin:$PATH" NIVUUS_UID=1000 "$ROOT/bin/nivuus" update >/dev/null
    [ ! -f "$TMP/reseau" ]
}
