# Étapes d'installation, chacune idempotente.
# N'écrit jamais en direct : tout passe par lib/manifest.sh.

nivuus_step_copy_tree() {
    local src="$1" dst="$2" rel
    nivuus_mkdir_p "$dst"

    # Répertoires copiés récursivement, en excluant .zwc et .git.
    local d f list
    list="$(mktemp)"
    for d in config themes bin plugins lib; do
        [ -d "$src/$d" ] || continue
        # Fichier temporaire plutôt qu'une substitution de processus
        # (bash-only, et interdite par tests/unit/test_lib_posix.bats) ou
        # qu'un `find ... | while` : le pipe mettrait la boucle dans un
        # sous-shell,
        # où un `return 1` sur échec d'écriture (disque plein, EPERM) serait
        # perdu à la sortie du sous-shell et l'installation se croirait
        # réussie. Le fichier temporaire préserve les deux propriétés :
        # POSIX, et pas de sous-shell.
        find "$src/$d" -type f ! -name '*.zwc' ! -path '*/.git/*' > "$list"
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            rel="${f#"$src"/}"
            if ! nivuus_install_file "$f" "$dst/$rel"; then
                rm -f "$list"
                return 1
            fi
        done < "$list"
    done
    rm -f "$list"

    # Fichiers à la racine.
    for f in .zshrc .vimrc.nord; do
        if [ -f "$src/$f" ]; then
            nivuus_install_file "$src/$f" "$dst/$f" || return 1
        fi
    done
    return 0
}

nivuus_step_write_zshrc() {
    local target="$1" install_dir="$2" minimal="${3:-}" merged

    local fw
    fw="$(nivuus_zshrc_detect_framework "$target")"
    if [ -n "$fw" ]; then
        log_warn "Ton .zshrc charge déjà : $(printf '%s' "$fw" | tr '\n' ' ')"
        log_warn "Deux prompts risquent de se marcher dessus. Nivuus n'y touche pas."
    fi

    merged="$(nivuus_zshrc_merge "$target" "$install_dir" "$minimal")" || return 1
    printf '%s\n' "$merged" | nivuus_write_file "$target"
}

nivuus_step_write_version() {
    local src="$1" dst="$2"
    [ -f "$src/.version" ] || return 0
    nivuus_install_file "$src/.version" "$dst/.version"
}

# Conservé comme façade : lib/deps.sh porte désormais la politique.
nivuus_step_check_required_deps() { nivuus_deps_check_required "$@"; }

# Change le shell de connexion -- une mutation système comme une autre,
# donc journalisée AVANT d'agir. Ne retourne jamais autre chose que 0 :
# l'installation elle-même a réussi, le shell de connexion est un confort.
nivuus_step_chsh() {
    local zsh_path="${1:-}" current
    [ -n "$zsh_path" ] || zsh_path="$(nivuus_zsh_path 2>/dev/null || true)"
    if [ -z "$zsh_path" ]; then
        log_warn "zsh introuvable : shell de connexion inchangé."
        return 0
    fi

    current="$(nivuus_current_login_shell)"
    if [ "$current" = "$zsh_path" ]; then
        log_info "zsh est déjà ton shell de connexion."
        return 0
    fi

    # LE cas qui casse macOS + Homebrew : /opt/homebrew/bin/zsh n'est pas
    # dans /etc/shells, chsh refuse. On ne modifie PAS /etc/shells nous-mêmes
    # (fichier système, sudo non demandé) : on donne la commande exacte.
    if ! nivuus_shell_is_listed "$zsh_path"; then
        log_warn "$zsh_path n'est pas listé dans $NIVUUS_ETC_SHELLS : chsh le refuserait."
        log_warn "Pour l'autoriser puis changer de shell, lance ces deux commandes :"
        log_warn "  echo $zsh_path | sudo tee -a $NIVUUS_ETC_SHELLS"
        log_warn "  chsh -s $zsh_path"
        return 0
    fi

    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        log_dry "chsh -s $zsh_path (shell actuel : $current)"
        return 0
    fi

    nivuus_manifest_record CHSH "$HOME" '-' "$current"
    if chsh -s "$zsh_path" >/dev/null 2>&1; then
        log_ok "Shell de connexion : $zsh_path (ouvre un nouveau terminal pour l'appliquer)"
    else
        log_warn "chsh a échoué. Change-le à la main avec : chsh -s $zsh_path"
    fi
    return 0
}
