#!/usr/bin/env bats

load '../helpers/signing'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    ZSH_BIN="$(command -v zsh)"
    TMP="$(mktemp -d)"
    find "$ROOT/config" -name '*.zwc' -delete 2>/dev/null || true

    # Jeu de clés légitime, éphémère. Jamais de vraie clé dans un test.
    gen_keyset "$TMP/legit"
    # Jeu de clés d'attaquant : mêmes propriétés, autre porteur.
    gen_keyset "$TMP/evil"

    # Une fausse release : une archive et son SHA256SUMS.
    mkdir -p "$TMP/rel"
    printf 'contenu authentique\n' > "$TMP/rel/nivuus-shell-v9.9.9.tar.gz"
    ( cd "$TMP/rel" && { sha256sum *.tar.gz 2>/dev/null || shasum -a 256 *.tar.gz; } > SHA256SUMS )
    sign_sums "$TMP/legit" "$TMP/rel/SHA256SUMS" "$TMP/rel"
}

teardown() { rm -rf "$TMP"; }

verify() {
    zsh_autoupdate "_nivuus_verify_signature '$1' '$2' '$3'; echo rc=\$?"
}

# ---------------------------------------------------------------------
# LES DEUX INVARIANTS DU CHANTIER
# ---------------------------------------------------------------------

@test "INVARIANT: a forged archive with SHA256SUMS re-signed by an attacker key is REFUSED" {
    # Scénario réel : l'attaquant remplace l'archive, régénère SHA256SUMS
    # pour qu'il décrive SON archive, et le signe avec SA clé. Tout est
    # cohérent — sauf que la clé n'est pas dans le trousseau.
    printf 'charge utile malveillante\n' > "$TMP/rel/nivuus-shell-v9.9.9.tar.gz"
    ( cd "$TMP/rel" && { sha256sum *.tar.gz 2>/dev/null || shasum -a 256 *.tar.gz; } > SHA256SUMS )
    sign_sums "$TMP/evil" "$TMP/rel/SHA256SUMS" "$TMP/rel"

    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=1"* ]]
}

@test "INVARIANT: no verification tool at all is REFUSED, never silently downgraded" {
    fake="$(mkfakepath "$TMP/bin" awk zsh cat grep)"
    run env PATH="$fake" ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; \
            _nivuus_verify_signature '$TMP/rel/SHA256SUMS' '$TMP/rel' '$TMP/legit/keys'; echo rc=\$?"
    # rc=2 : « aucun outil », distinct de rc=1 « invalide ». Jamais 0.
    [[ "$output" == *"rc=2"* ]]
    [[ "$output" != *"rc=0"* ]]
}

# ---------------------------------------------------------------------
# Le reste de la matrice du spec (§ 6)
# ---------------------------------------------------------------------

@test "case 1: intact SHA256SUMS with a valid signature is accepted" {
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=0"* ]]
}

@test "case 2: SHA256SUMS altered by one byte is refused" {
    printf 'x' >> "$TMP/rel/SHA256SUMS"
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=1"* ]]
}

@test "case 5: a missing .sig is refused (no SHA256 fallback)" {
    rm -f "$TMP/rel/SHA256SUMS.sig" "$TMP/rel/SHA256SUMS.sshsig"
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=1"* ]]
}

@test "case 6: a truncated or empty .sig is refused without stray zsh errors" {
    : > "$TMP/rel/SHA256SUMS.sig"
    rm -f "$TMP/rel/SHA256SUMS.sshsig"
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=1"* ]]
    [[ "$output" != *"parse error"* ]]
    [[ "$output" != *"no such file"* ]]
}

@test "case 6b: a non-binary garbage .sig is refused" {
    printf 'not a signature at all\n' > "$TMP/rel/SHA256SUMS.sig"
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=1"* ]]
}

@test "case 7: a valid signature of ANOTHER SHA256SUMS is refused (cross-version replay)" {
    mkdir -p "$TMP/other"
    printf 'autre release\n' > "$TMP/other/nivuus-shell-v8.8.8.tar.gz"
    ( cd "$TMP/other" && { sha256sum *.tar.gz 2>/dev/null || shasum -a 256 *.tar.gz; } > SHA256SUMS )
    sign_sums "$TMP/legit" "$TMP/other/SHA256SUMS" "$TMP/other"
    # Signature authentique... mais d'un autre contenu.
    cp "$TMP/other/SHA256SUMS.sig" "$TMP/rel/SHA256SUMS.sig"
    rm -f "$TMP/rel/SHA256SUMS.sshsig"
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=1"* ]]
}

@test "case 10: a revoked key is refused even though it is still in the store" {
    fp="$( { sha256sum "$TMP/legit/keys/nivuus-test.pem" 2>/dev/null \
             || shasum -a 256 "$TMP/legit/keys/nivuus-test.pem"; } | awk '{print $1}' )"
    printf 'sha256:%s\n' "$fp" > "$TMP/legit/keys/revoked"
    rm -f "$TMP/rel/SHA256SUMS.sshsig"
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=1"* ]]
}

@test "case 11: with two trusted keys, a signature from the second one is accepted (rotation)" {
    gen_keyset "$TMP/next" nivuus-next
    # Le trousseau du client contient les deux jeux : l'ancien et le
    # successeur pré-distribué.
    cp "$TMP/next/keys/nivuus-next.pem" "$TMP/legit/keys/"
    # La release est signée par le SUCCESSEUR.
    sign_sums "$TMP/next" "$TMP/rel/SHA256SUMS" "$TMP/rel"
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=0"* ]]
}

@test "an empty key store refuses everything" {
    mkdir -p "$TMP/emptykeys"
    : > "$TMP/emptykeys/revoked"
    run verify "$TMP/rel/SHA256SUMS" "$TMP/rel" "$TMP/emptykeys"
    [[ "$output" == *"rc=1"* ]]
}

@test "a missing SHA256SUMS is refused" {
    run verify "$TMP/nope" "$TMP/rel" "$TMP/legit/keys"
    [[ "$output" == *"rc=1"* ]]
}
