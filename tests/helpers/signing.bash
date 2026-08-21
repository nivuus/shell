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
