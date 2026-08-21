# Étapes d'installation, chacune idempotente.
# N'écrit jamais en direct : tout passe par lib/manifest.sh.

nivuus_step_copy_tree() {
    local src="$1" dst="$2" rel
    nivuus_mkdir_p "$dst"

    # Répertoires copiés récursivement, en excluant .zwc et .git.
    # `< <(find ...)` plutôt que `find ... | while ...` : un pipe mettrait la
    # boucle dans une sous-shell, où un `return` (ou toute autre erreur)
    # resterait local à cette sous-shell et serait perdu à sa sortie -- une
    # panne d'écriture (disque plein, EPERM) au milieu de la copie serait
    # rapportée comme un succès.
    local d f
    for d in config themes bin plugins lib; do
        [ -d "$src/$d" ] || continue
        while IFS= read -r f; do
            rel="${f#"$src"/}"
            nivuus_install_file "$f" "$dst/$rel" || return 1
        done < <(find "$src/$d" -type f \
            ! -name '*.zwc' \
            ! -path '*/.git/*')
    done

    # Fichiers à la racine.
    for f in .zshrc .vimrc.nord; do
        if [ -f "$src/$f" ]; then
            nivuus_install_file "$src/$f" "$dst/$f" || return 1
        fi
    done
    return 0
}

nivuus_step_write_zshrc() {
    local target="$1" install_dir="$2" merged

    local fw
    fw="$(nivuus_zshrc_detect_framework "$target")"
    if [ -n "$fw" ]; then
        log_warn "Ton .zshrc charge déjà : $(printf '%s' "$fw" | tr '\n' ' ')"
        log_warn "Deux prompts risquent de se marcher dessus. Nivuus n'y touche pas."
    fi

    merged="$(nivuus_zshrc_merge "$target" "$install_dir")" || return 1
    printf '%s\n' "$merged" | nivuus_write_file "$target"
}

nivuus_step_write_version() {
    local src="$1" dst="$2"
    [ -f "$src/.version" ] || return 0
    nivuus_install_file "$src/.version" "$dst/.version"
}

# Conservé comme façade : lib/deps.sh porte désormais la politique.
nivuus_step_check_required_deps() { nivuus_deps_check_required "$@"; }
