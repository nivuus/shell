#!/usr/bin/env bats
#
# tests/helpers/release.bash fabrique la release que trois suites
# consomment. Si chacune la fabriquait à sa façon, une divergence de format
# avec .github/workflows/release.yml ne se verrait nulle part -- et c'est
# précisément cette divergence qui casserait le one-liner en production.
# Le format est donc décrit une fois, et vérifié ici.

load '../helpers/release'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/src/bin" "$TMP/src/config"
    printf '#!/bin/sh\necho noyau\n' > "$TMP/src/bin/nivuus"
    printf 'echo core\n' > "$TMP/src/config/00-core.zsh"
    printf 'bytecode\n' > "$TMP/src/config/00-core.zsh.zwc"
    mkdir -p "$TMP/src/.git"; printf 'ref\n' > "$TMP/src/.git/HEAD"
}

teardown() { rm -rf "$TMP"; }

@test "make_release produit l'archive et les sommes aux noms attendus" {
    make_release "$TMP/src" "$TMP/rel" 9.9.9
    [ -f "$TMP/rel/v9.9.9/nivuus-shell-v9.9.9.tar.gz" ]
    [ -f "$TMP/rel/v9.9.9/SHA256SUMS" ]
}

@test "SHA256SUMS nomme l'archive SANS préfixe ./ (format release.yml)" {
    make_release "$TMP/src" "$TMP/rel" 9.9.9
    run cat "$TMP/rel/v9.9.9/SHA256SUMS"
    [[ "$output" == *"  nivuus-shell-v9.9.9.tar.gz"* ]]
    [[ "$output" != *"./nivuus-shell"* ]]
}

@test "l'archive n'a PAS de répertoire racine (format release.yml)" {
    make_release "$TMP/src" "$TMP/rel" 9.9.9
    run tar -tzf "$TMP/rel/v9.9.9/nivuus-shell-v9.9.9.tar.gz"
    [[ "$output" == *"./bin/nivuus"* || "$output" == *"bin/nivuus"* ]]
    # Aucune entrée du type « nivuus-shell-9.9.9/bin/nivuus »
    [[ "$output" != *"nivuus-shell-9.9.9/"* ]]
}

@test "l'archive exclut .git et les .zwc (format release.yml)" {
    make_release "$TMP/src" "$TMP/rel" 9.9.9
    run tar -tzf "$TMP/rel/v9.9.9/nivuus-shell-v9.9.9.tar.gz"
    [[ "$output" != *".git/"* ]]
    [[ "$output" != *".zwc"* ]]
}

@test "la somme annoncée est celle de l'archive" {
    make_release "$TMP/src" "$TMP/rel" 9.9.9
    expected="$(awk '{print $1}' "$TMP/rel/v9.9.9/SHA256SUMS")"
    actual="$( { sha256sum "$TMP/rel/v9.9.9/nivuus-shell-v9.9.9.tar.gz" 2>/dev/null \
                 || shasum -a 256 "$TMP/rel/v9.9.9/nivuus-shell-v9.9.9.tar.gz"; } | awk '{print $1}')"
    [ "$expected" = "$actual" ]
}

@test "tamper_release casse la correspondance sans toucher aux sommes" {
    make_release "$TMP/src" "$TMP/rel" 9.9.9
    before="$(cat "$TMP/rel/v9.9.9/SHA256SUMS")"
    tamper_release "$TMP/rel" 9.9.9
    [ "$(cat "$TMP/rel/v9.9.9/SHA256SUMS")" = "$before" ]
    expected="$(awk '{print $1}' "$TMP/rel/v9.9.9/SHA256SUMS")"
    actual="$( { sha256sum "$TMP/rel/v9.9.9/nivuus-shell-v9.9.9.tar.gz" 2>/dev/null \
                 || shasum -a 256 "$TMP/rel/v9.9.9/nivuus-shell-v9.9.9.tar.gz"; } | awk '{print $1}')"
    [ "$expected" != "$actual" ]
}

@test "make_release_api écrit une réponse latest exploitable" {
    make_release_api "$TMP/api" fake/nivuus 9.9.9
    [ -f "$TMP/api/repos/fake/nivuus/releases/latest" ]
    run cat "$TMP/api/repos/fake/nivuus/releases/latest"
    [[ "$output" == *'"tag_name"'* ]]
    [[ "$output" == *'v9.9.9'* ]]
}
