# tests/helpers/signing.bash
# Helpers partagés par les suites de signature.
# Aucune clé réelle ici : tout est généré à la volée dans setup().

# Construit un PATH minimal ne contenant QUE les outils nommés.
# Sert à simuler « sha256sum absent », « openssl absent », etc.
# Les symlinks pointent vers les vrais binaires : on retire des outils,
# on n'en simule aucun.
mkfakepath() {
    local dir="$1"; shift
    mkdir -p "$dir"
    local t p
    for t in "$@"; do
        p="$(command -v "$t" 2>/dev/null)" || continue
        ln -sf "$p" "$dir/$t"
    done
    printf '%s\n' "$dir"
}

# Exécute du code zsh avec config/20-autoupdate.zsh chargé.
# ENABLE_AUTOUPDATE=false empêche le bloc de vérification automatique de
# partir en arrière-plan pendant les tests.
zsh_autoupdate() {
    ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$ROOT" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; $1"
}

# Génère un jeu de clés éphémère complet dans $1.
# Produit : priv.pem / pub.pem (ECDSA P-256), id / id.pub (Ed25519),
# et un keys/ prêt à être passé en paramètre à _nivuus_verify_signature.
gen_keyset() {
    local dir="$1" name="${2:-nivuus-test}"
    mkdir -p "$dir/keys"
    openssl ecparam -name prime256v1 -genkey -noout -out "$dir/priv.pem" 2>/dev/null
    openssl ec -in "$dir/priv.pem" -pubout -out "$dir/keys/$name.pem" 2>/dev/null
    ssh-keygen -q -t ed25519 -N '' -f "$dir/id" -C "$name"
    printf 'nivuus-release %s\n' "$(cat "$dir/id.pub")" > "$dir/keys/allowed_signers"
    : > "$dir/keys/revoked"
}

# Signe $2 avec le jeu de $1, dépose les signatures dans $3.
#
# `ssh-keygen -Y sign X` écrit « X.sig » et n'a pas d'option de sortie
# portable — exactement le nom que `openssl dgst -out` vise aussi. La
# sonde de la Task 2 s'est fait piéger par cette collision ; on signe donc
# le SSHSIG depuis une COPIE, puis on renomme.
sign_sums() {
    local keydir="$1" sums="$2" outdir="$3"
    mkdir -p "$outdir"
    openssl dgst -sha256 -sign "$keydir/priv.pem" \
        -out "$outdir/SHA256SUMS.sig" "$sums"

    local copy="$outdir/.sshsig-input"
    cp "$sums" "$copy"
    rm -f "$copy.sig"
    ssh-keygen -Y sign -q -f "$keydir/id" -n nivuus-release "$copy" 2>/dev/null
    if [ -f "$copy.sig" ]; then
        mv "$copy.sig" "$outdir/SHA256SUMS.sshsig"
    fi
    rm -f "$copy"
    return 0
}
