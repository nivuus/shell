#!/usr/bin/env bats

load '../helpers/signing'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    ZSH_BIN="$(command -v zsh)"
    TMP="$(mktemp -d)"
    find "$ROOT/config" -name '*.zwc' -delete 2>/dev/null || true

    gen_keyset "$TMP/legit"
    gen_keyset "$TMP/evil"

    # Un répertoire temporaire de téléchargement, tel que
    # _nivuus_download_release le produit.
    DL="$TMP/dl"; mkdir -p "$DL"
    printf 'archive authentique\n' > "$DL/nivuus-shell.tar.gz"
    # SHA256SUMS décrit l'archive sous son nom VERSIONNÉ.
    sum="$( { sha256sum "$DL/nivuus-shell.tar.gz" 2>/dev/null \
              || shasum -a 256 "$DL/nivuus-shell.tar.gz"; } | awk '{print $1}' )"
    printf '%s  nivuus-shell-v9.9.9.tar.gz\n' "$sum" > "$DL/SHA256SUMS"
    sign_sums "$TMP/legit" "$DL/SHA256SUMS" "$DL"
}

teardown() { rm -rf "$TMP"; }

vrel() {
    zsh_autoupdate "_nivuus_verify_release '$DL' '$1' '$TMP/legit/keys'; echo rc=\$?"
}

@test "a fully valid release verifies" {
    run vrel 9.9.9
    [[ "$output" == *"rc=0"* ]]
}

@test "signature is checked BEFORE the digest" {
    # SHA256SUMS non signé mais cohérent avec l'archive : accepter
    # reviendrait à faire confiance à une somme non authentifiée.
    rm -f "$DL/SHA256SUMS.sig" "$DL/SHA256SUMS.sshsig"
    run vrel 9.9.9
    [[ "$output" == *"rc=1"* ]]
}

@test "case 4: forged archive with an authentic signed SHA256SUMS is refused on the digest" {
    printf 'charge utile malveillante\n' > "$DL/nivuus-shell.tar.gz"
    run vrel 9.9.9
    [[ "$output" == *"rc=1"* ]]
}

@test "case 3 end-to-end: forged archive + attacker-signed SHA256SUMS is refused" {
    printf 'charge utile malveillante\n' > "$DL/nivuus-shell.tar.gz"
    sum="$( { sha256sum "$DL/nivuus-shell.tar.gz" 2>/dev/null \
              || shasum -a 256 "$DL/nivuus-shell.tar.gz"; } | awk '{print $1}' )"
    printf '%s  nivuus-shell-v9.9.9.tar.gz\n' "$sum" > "$DL/SHA256SUMS"
    sign_sums "$TMP/evil" "$DL/SHA256SUMS" "$DL"
    run vrel 9.9.9
    [[ "$output" == *"rc=1"* ]]
}

@test "cross-version replay: a signed SHA256SUMS for another version is refused" {
    # Signature valide, archive valide, mais la ligne cherchée est celle
    # de la version demandée : elle n'y est pas.
    run vrel 8.8.8
    [[ "$output" == *"rc=1"* ]]
}

@test "no verification tool returns 2, not 0" {
    fake="$(mkfakepath "$TMP/bin" awk zsh grep cat sha256sum shasum)"
    run env PATH="$fake" ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; \
            _nivuus_verify_release '$DL' 9.9.9 '$TMP/legit/keys'; echo rc=\$?"
    [[ "$output" == *"rc=2"* ]]
}

@test "NIVUUS_VERIFY_CHECKSUMS=false does NOT disable signature verification" {
    rm -f "$DL/SHA256SUMS.sig" "$DL/SHA256SUMS.sshsig"
    run env ENABLE_AUTOUPDATE=false NIVUUS_VERIFY_CHECKSUMS=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; \
            _nivuus_verify_release '$DL' 9.9.9 '$TMP/legit/keys'; echo rc=\$?"
    [[ "$output" == *"rc=1"* ]]
}

@test "NIVUUS_VERIFY_CHECKSUMS=false only skips the digest step" {
    # Signature valide, archive falsifiée : l'utilisateur a explicitement
    # renoncé à l'étape d'empreinte, la signature reste exigée et valide.
    printf 'contenu different\n' > "$DL/nivuus-shell.tar.gz"
    run env ENABLE_AUTOUPDATE=false NIVUUS_VERIFY_CHECKSUMS=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; \
            _nivuus_verify_release '$DL' 9.9.9 '$TMP/legit/keys'; echo rc=\$?"
    [[ "$output" == *"rc=0"* ]]
}
