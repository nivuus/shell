#!/usr/bin/env bats

load '../helpers/signing'
load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    ZSH_BIN="$(command -v zsh)"
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
    find "$ROOT/config" -name '*.zwc' -delete 2>/dev/null || true

    # 1. Une installation existante, saine.
    "$NIVUUS" install --yes --prefix "$TMP/target" >/dev/null
    printf '3.0.0\n' > "$TMP/target/.version"

    # 2. Un trousseau éphémère, substitué à celui de l'installation :
    #    on ne signe jamais avec la vraie clé dans un test.
    gen_keyset "$TMP/legit"
    gen_keyset "$TMP/evil"
    mkdir -p "$TMP/target/keys"
    rm -f "$TMP/target/keys"/*.pem "$TMP/target/keys/allowed_signers"
    cp "$TMP/legit/keys"/* "$TMP/target/keys/"

    # 3. Une fausse release 9.9.9 servie par file://
    REL="$TMP/releases/v9.9.9"; mkdir -p "$REL"
    mkdir -p "$TMP/payload/config"
    printf 'echo NOUVELLE_VERSION\n' > "$TMP/payload/config/00-core.zsh"
    printf '9.9.9\n' > "$TMP/payload/.version"
    tar -czf "$REL/nivuus-shell-v9.9.9.tar.gz" -C "$TMP/payload" .
    ( cd "$REL" && { sha256sum *.tar.gz 2>/dev/null || shasum -a 256 *.tar.gz; } > SHA256SUMS )

    # 4. Une fausse API GitHub, elle aussi servie par file://
    API="$TMP/api/repos/fake/nivuus/releases"; mkdir -p "$API"
    printf '{"tag_name": "v9.9.9"}\n' > "$API/latest"

    export NIVUUS_RELEASE_BASE_URL="file://$TMP/releases"
    export NIVUUS_GITHUB_API="file://$TMP/api"
    export NIVUUS_GITHUB_REPO="fake/nivuus"
}

teardown() { rm -rf "$TMP"; }

update() {
    ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$TMP/target" \
    NIVUUS_RELEASE_BASE_URL="$NIVUUS_RELEASE_BASE_URL" \
    NIVUUS_GITHUB_API="$NIVUUS_GITHUB_API" NIVUUS_GITHUB_REPO="$NIVUUS_GITHUB_REPO" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; $1"
}

@test "nominal: a properly signed release installs and .version moves forward" {
    sign_sums "$TMP/legit" "$REL/SHA256SUMS" "$REL"
    run update "_nivuus_perform_update 9.9.9"
    [ "$status" -eq 0 ]
    [ "$(cat "$TMP/target/.version")" = "9.9.9" ]
    run grep -c NOUVELLE_VERSION "$TMP/target/config/00-core.zsh"
    [ "$output" = "1" ]
}

@test "INVARIANT: a tampered archive is refused AND the install is untouched" {
    sign_sums "$TMP/legit" "$REL/SHA256SUMS" "$REL"
    # L'archive est modifiée APRÈS signature : SHA256SUMS ne la décrit
    # plus, mais la signature de SHA256SUMS reste authentique.
    printf 'charge utile malveillante\n' > "$TMP/payload/config/00-core.zsh"
    tar -czf "$REL/nivuus-shell-v9.9.9.tar.gz" -C "$TMP/payload" .

    fs_fingerprint "$TMP/target" > "$TMP/before"
    run update "_nivuus_perform_update 9.9.9"
    [ "$status" -ne 0 ]
    fs_fingerprint "$TMP/target" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
    [ "$(cat "$TMP/target/.version")" = "3.0.0" ]
}

@test "INVARIANT: an attacker-signed SHA256SUMS is refused AND the install is untouched" {
    printf 'charge utile malveillante\n' > "$TMP/payload/config/00-core.zsh"
    tar -czf "$REL/nivuus-shell-v9.9.9.tar.gz" -C "$TMP/payload" .
    ( cd "$REL" && { sha256sum *.tar.gz 2>/dev/null || shasum -a 256 *.tar.gz; } > SHA256SUMS )
    sign_sums "$TMP/evil" "$REL/SHA256SUMS" "$REL"

    fs_fingerprint "$TMP/target" > "$TMP/before"
    run update "_nivuus_perform_update 9.9.9"
    [ "$status" -ne 0 ]
    fs_fingerprint "$TMP/target" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "INVARIANT: a client with no verification tool refuses and stays intact" {
    sign_sums "$TMP/legit" "$REL/SHA256SUMS" "$REL"
    fake="$(mkfakepath "$TMP/bin" curl tar awk grep cat mktemp rm cp find date zsh sha256sum shasum chmod)"
    fs_fingerprint "$TMP/target" > "$TMP/before"
    run env PATH="$fake" ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$TMP/target" \
        NIVUUS_RELEASE_BASE_URL="$NIVUUS_RELEASE_BASE_URL" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; _nivuus_perform_update 9.9.9"
    [ "$status" -ne 0 ]
    fs_fingerprint "$TMP/target" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "INVARIANT: signatures stripped from the release are refused, no SHA256 fallback" {
    sign_sums "$TMP/legit" "$REL/SHA256SUMS" "$REL"
    rm -f "$REL/SHA256SUMS.sig" "$REL/SHA256SUMS.sshsig"
    fs_fingerprint "$TMP/target" > "$TMP/before"
    run update "_nivuus_perform_update 9.9.9"
    [ "$status" -ne 0 ]
    fs_fingerprint "$TMP/target" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "the async path ignores NIVUUS_ALLOW_UNVERIFIED_UPDATE entirely" {
    rm -f "$REL/SHA256SUMS.sig" "$REL/SHA256SUMS.sshsig"
    fs_fingerprint "$TMP/target" > "$TMP/before"
    run env NIVUUS_ALLOW_UNVERIFIED_UPDATE=1 ENABLE_AUTOUPDATE=false \
        NIVUUS_SHELL_DIR="$TMP/target" NIVUUS_RELEASE_BASE_URL="$NIVUUS_RELEASE_BASE_URL" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; _nivuus_perform_update 9.9.9 < /dev/null"
    [ "$status" -ne 0 ]
    fs_fingerprint "$TMP/target" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "a refused update costs nothing: no backup is created before verification" {
    # ÉCART AU PLAN, assumé : les six tests ci-dessus passent SANS la
    # correction que la Task 14 réclame, parce qu'ils n'empreignent que
    # $NIVUUS_SHELL_DIR et que la sauvegarde, elle, vit dans $HOME. La
    # propriété que la Task 14 veut vraiment établir — « une release
    # refusée ne doit rien coûter et ne rien laisser derrière elle » —
    # n'était donc couverte par aucun test. Celui-ci la couvre : sans la
    # correction, ~50 Mo sont recopiés à CHAQUE tentative refusée, sur
    # toutes les machines, une fois par semaine.
    rm -f "$REL/SHA256SUMS.sig" "$REL/SHA256SUMS.sshsig"
    run update "_nivuus_perform_update 9.9.9"
    [ "$status" -ne 0 ]
    [ ! -d "$HOME/.config/nivuus-shell-backup" ]
}
