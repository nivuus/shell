#!/usr/bin/env bats

load '../helpers/release'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    SH="$ROOT/install.sh"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
    # Un TMPDIR à nous : c'est la seule façon d'affirmer « aucun temporaire
    # laissé derrière » sans se prononcer sur /tmp partagé avec le reste.
    export TMPDIR="$TMP/tmp"; mkdir -p "$TMPDIR"

    # Une copie isolée du script : sans noyau à côté, elle est forcément en
    # mode amorçage, quel que soit le répertoire courant.
    cp "$SH" "$TMP/install.sh"

    make_release "$ROOT" "$TMP/releases" 9.9.9
    make_release_api "$TMP/api" fake/nivuus 9.9.9
    export NIVUUS_RELEASE_BASE_URL="file://$TMP/releases"
    export NIVUUS_GITHUB_API="file://$TMP/api"
    export NIVUUS_GITHUB_REPO="fake/nivuus"
}

teardown() { rm -rf "$TMP"; }

boot() { run sh "$TMP/install.sh" "$@"; }

@test "amorçage nominal : installe depuis l'archive vérifiée" {
    boot --non-interactive --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ -f "$TMP/target/config/00-core.zsh" ]
    [ -f "$TMP/target/bin/nivuus" ]
}

@test "amorçage : aucun dépôt git derrière lui" {
    boot --non-interactive --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ ! -e "$TMP/target/.git" ]
    run find "$TMP/target" -maxdepth 3 -name '.git'
    [ -z "$output" ]
}

@test "amorçage : aucun répertoire temporaire laissé derrière" {
    boot --non-interactive --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    run find "$TMPDIR" -maxdepth 1 -name 'nivuus-boot.*'
    [ -z "$output" ]
}

@test "INVARIANT: archive falsifiée -> refus, rien d'écrit, rien de laissé" {
    tamper_release "$TMP/releases" 9.9.9
    boot --non-interactive --prefix "$TMP/target"
    [ "$status" -ne 0 ]
    [[ "$output" == *"mpreinte"* ]]
    [ ! -e "$TMP/target" ]
    [ ! -e "$HOME/.zshrc" ]
    run find "$TMPDIR" -maxdepth 1 -name 'nivuus-boot.*'
    [ -z "$output" ]
}

@test "INVARIANT: SHA256SUMS absent -> refus, pas de repli" {
    rm -f "$TMP/releases/v9.9.9/SHA256SUMS"
    boot --non-interactive --prefix "$TMP/target"
    [ "$status" -ne 0 ]
    [ ! -e "$TMP/target" ]
}

@test "INVARIANT: SHA256SUMS sans ligne pour cette archive -> refus" {
    printf 'deadbeef  autre-chose.tar.gz\n' > "$TMP/releases/v9.9.9/SHA256SUMS"
    boot --non-interactive --prefix "$TMP/target"
    [ "$status" -ne 0 ]
    [ ! -e "$TMP/target" ]
}

@test "la version vient de l'API quand NIVUUS_VERSION n'est pas posée" {
    # La 9.9.9 est retirée : si la résolution ignorait l'API, il ne
    # resterait aucune archive téléchargeable et l'amorçage échouerait.
    make_release "$ROOT" "$TMP/releases" 7.7.7
    make_release_api "$TMP/api" fake/nivuus 7.7.7
    rm -rf "$TMP/releases/v9.9.9"
    boot --non-interactive --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [[ "$output" == *"7.7.7"* ]]
    [ -f "$TMP/target/bin/nivuus" ]
}

@test "NIVUUS_VERSION l'emporte sur l'API" {
    make_release_api "$TMP/api" fake/nivuus 7.7.7
    run env NIVUUS_VERSION=9.9.9 sh "$TMP/install.sh" --non-interactive --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ -f "$TMP/target/bin/nivuus" ]
}

@test "API injoignable -> repli sur la version épinglée, avec un message" {
    run env NIVUUS_GITHUB_API="file://$TMP/api-absente" \
        NIVUUS_RELEASE_BASE_URL="file://$TMP/releases" \
        sh "$TMP/install.sh" --non-interactive --prefix "$TMP/target"
    # La version épinglée (3.0.0) n'a pas d'archive ici : l'échec est
    # attendu, mais il doit NOMMER la version et le repli, pas planter.
    [ "$status" -ne 0 ]
    [[ "$output" == *"3.0.0"* ]]
}

@test "archive antérieure au nouvel installeur -> message qui nomme la version" {
    # Une release qui ne contient pas bin/nivuus : exactement le cas de
    # v3.0.0 si quelqu'un l'épingle.
    mkdir -p "$TMP/vieux/config"
    printf 'echo vieux\n' > "$TMP/vieux/config/00-core.zsh"
    make_release "$TMP/vieux" "$TMP/releases" 3.0.0
    run env NIVUUS_VERSION=3.0.0 sh "$TMP/install.sh" --non-interactive --prefix "$TMP/target"
    [ "$status" -ne 0 ]
    [[ "$output" == *"3.0.0"* ]]
    [ ! -e "$TMP/target" ]
}

@test "--dry-run en amorçage : télécharge, vérifie, n'écrit rien" {
    boot --non-interactive --dry-run --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ ! -e "$TMP/target" ]
    [ ! -e "$HOME/.zshrc" ]
}

@test "bash absent : commande d'installation affichée, jamais exécutée" {
    mkdir -p "$TMP/bin"
    for c in sh cp mv rm mkdir cat tar find sed awk grep cut head chmod \
             mktemp sha256sum shasum dirname basename id uname gzip; do
        p="$(command -v "$c" 2>/dev/null)" || continue
        ln -sf "$p" "$TMP/bin/$c"
    done
    run env PATH="$TMP/bin" NIVUUS_VERSION=9.9.9 \
        NIVUUS_RELEASE_BASE_URL="file://$TMP/releases" \
        /bin/sh "$TMP/install.sh" --non-interactive --prefix "$TMP/target"
    [ "$status" -ne 0 ]
    [[ "$output" == *"bash"* ]]
    [ ! -e "$TMP/target" ]
}
