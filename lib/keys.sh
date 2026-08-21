# lib/keys.sh
# Identité du trousseau de confiance : lister et résumer les clés
# publiques installées. POSIX / bash 3.2 : sourcé par bin/nivuus et par
# bin/healthcheck.
#
# Aucune vérification de signature ici — c'est le rôle du client zsh
# (config/20-autoupdate.zsh). Ce module ne répond qu'à une question :
# « quelles clés cette installation considère-t-elle comme de
# confiance ? »

# Une ligne « <fichier> <sha256> » par artefact public, triée.
nivuus_keyset_list() {
    local keys_dir f
    keys_dir="$1"
    [ -d "$keys_dir" ] || return 1
    for f in "$keys_dir"/*.pem; do
        [ -f "$f" ] || continue
        printf '%s %s\n' "$(basename "$f")" "$(nivuus_hash_file "$f")"
    done | LC_ALL=C sort
    if [ -f "$keys_dir/allowed_signers" ]; then
        printf '%s %s\n' allowed_signers "$(nivuus_hash_file "$keys_dir/allowed_signers")"
    fi
}

# Empreinte unique du jeu : c'est CE que l'utilisateur compare quand il
# utilise --verify-key. Volontairement calculée sur les clés seules :
# « revoked » relève de la politique et peut changer sans que l'identité
# du jeu change — sinon la moindre révocation invaliderait l'empreinte
# que les utilisateurs ont notée.
nivuus_keyset_fingerprint() {
    local keys_dir tmp digest
    keys_dir="$1"
    [ -d "$keys_dir" ] || return 1
    tmp="$(mktemp)"
    nivuus_keyset_list "$keys_dir" > "$tmp"
    if [ ! -s "$tmp" ]; then rm -f "$tmp"; return 1; fi
    digest="$(nivuus_hash_file "$tmp")"
    rm -f "$tmp"
    printf '%s\n' "$digest"
}

nivuus_keyset_verify() {
    local keys_dir expected actual
    keys_dir="$1"; expected="$2"
    actual="$(nivuus_keyset_fingerprint "$keys_dir")" || return 1
    [ "$actual" = "$expected" ]
}
