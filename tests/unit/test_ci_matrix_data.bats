#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    MATRIX="$ROOT/.github/matrix.json"
    command -v jq >/dev/null 2>&1 || skip "jq indisponible"
}

@test "matrix.json is valid JSON" {
    run jq empty "$MATRIX"
    [ "$status" -eq 0 ]
}

@test "every container target has id, image and label" {
    run jq -e 'all(.containers[]; has("id") and has("image") and has("label"))' "$MATRIX"
    [ "$status" -eq 0 ]
}

@test "the spec's container targets are all present" {
    for image in ubuntu:22.04 ubuntu:24.04 debian:12 archlinux:latest fedora:41 alpine:3.20; do
        run jq -e --arg i "$image" 'any(.containers[]; .image == $i)' "$MATRIX"
        [ "$status" -eq 0 ] || { echo "cible manquante: $image"; false; }
    done
}

@test "the spec's runner targets are all present" {
    for r in ubuntu-latest macos-latest; do
        run jq -e --arg r "$r" 'any(.runners[]; .["runs-on"] == $r)' "$MATRIX"
        [ "$status" -eq 0 ] || { echo "runner manquant: $r"; false; }
    done
}

@test "ids are unique and usable as job names" {
    run jq -e '[.containers[].id] | (length == (unique | length))' "$MATRIX"
    [ "$status" -eq 0 ]
    run jq -e 'all(.containers[].id; test("^[a-z0-9-]+$"))' "$MATRIX"
    [ "$status" -eq 0 ]
}
