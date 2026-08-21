# tests/helpers/release.bash
# Fabrique une release Nivuus locale, servie par file://, dans EXACTEMENT le
# format que .github/workflows/release.yml publie :
#   - nivuus-shell-v<version>.tar.gz : tar -czf … . , donc pas de répertoire
#     racine, .git et *.zwc exclus ;
#   - SHA256SUMS : « <somme>  nivuus-shell-v<version>.tar.gz », sans « ./ ».
# Toute divergence avec release.yml se verrait ici et nulle part ailleurs :
# c'est la raison d'être de tests/unit/test_helper_release.bats.

_release_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

make_release() {
    local src="$1" outdir="$2" version="$3" dir archive
    dir="$outdir/v$version"
    archive="nivuus-shell-v${version}.tar.gz"
    mkdir -p "$dir"
    # --exclude AVANT la liste de fichiers : exigé par bsdtar (macOS) autant
    # que par GNU tar. Les mêmes exclusions que release.yml, plus rien.
    tar --exclude='./.git' --exclude='*.zwc' --exclude='./release-assets' \
        --exclude='./.github' -czf "$dir/$archive" -C "$src" .
    # On écrit la ligne à la main plutôt que « sha256sum *.tar.gz » : le glob
    # produit « ./nom » ou « nom » selon le shell et la version, et le client
    # d'amorçage cherche une correspondance exacte sur le nom.
    printf '%s  %s\n' "$(_release_sha256 "$dir/$archive")" "$archive" > "$dir/SHA256SUMS"
}

# Réponse minimale de l'API GitHub, servie elle aussi par file://.
# Le client (install.sh comme config/20-autoupdate.zsh) n'en lit qu'un champ.
make_release_api() {
    local api="$1" repo="$2" version="$3" dir
    dir="$api/repos/$repo/releases"
    mkdir -p "$dir"
    printf '{"tag_name": "v%s"}\n' "$version" > "$dir/latest"
}

# Modifie l'archive APRÈS coup : SHA256SUMS reste authentique et cohérent
# avec lui-même, mais ne décrit plus le contenu livré. C'est le scénario
# « CDN empoisonné » et c'est le seul que l'empreinte seule peut attraper.
#
# L'archive falsifiée reste une archive PARFAITEMENT VALIDE : y ajouter des
# octets en fin de fichier la rendrait illisible, et le client la
# refuserait alors à l'extraction -- ce qui ferait passer les tests
# d'invariant sans que la vérification d'empreinte y soit pour quoi que ce
# soit. Un attaquant, lui, sert une archive qui s'extrait très bien.
tamper_release() {
    local outdir="$1" version="$2" archive work
    archive="$outdir/v$version/nivuus-shell-v${version}.tar.gz"
    work="$(mktemp -d)"
    tar -xzf "$archive" -C "$work"
    printf 'charge utile malveillante\n' > "$work/PAYLOAD"
    tar -czf "$archive" -C "$work" .
    rm -rf "$work"
}
