# shellcheck shell=bash
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

# $3 (optionnel) : position du bloc, "top" (défaut) ou "bottom" -- voir
# nivuus_zshrc_merge.
nivuus_step_write_zshrc() {
    local target="$1" install_dir="$2" position="${3:-top}" merged

    local fw
    fw="$(nivuus_zshrc_detect_framework "$target")"
    if [ -n "$fw" ]; then
        log_warn "Ton .zshrc charge déjà : $(printf '%s' "$fw" | tr '\n' ' ')"
        log_warn "Deux prompts risquent de se marcher dessus. Nivuus n'y touche pas."
    fi

    merged="$(nivuus_zshrc_merge "$target" "$install_dir" "$position")" || return 1
    printf '%s\n' "$merged" | nivuus_write_file "$target"
}

nivuus_step_write_version() {
    local src="$1" dst="$2"
    [ -f "$src/.version" ] || return 0
    nivuus_install_file "$src/.version" "$dst/.version"
}

nivuus_step_check_required_deps() {
    local missing='' c
    for c in zsh git curl; do
        command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
    done
    [ -n "$missing" ] || return 0

    log_error "Dépendances requises manquantes :$missing"
    if command -v apt-get >/dev/null 2>&1; then
        log_error "Installe-les avec : sudo apt-get install$missing"
    elif command -v dnf >/dev/null 2>&1; then
        log_error "Installe-les avec : sudo dnf install$missing"
    elif command -v pacman >/dev/null 2>&1; then
        log_error "Installe-les avec : sudo pacman -S$missing"
    elif command -v brew >/dev/null 2>&1; then
        log_error "Installe-les avec : brew install$missing"
    else
        log_error "Installe-les avec ton gestionnaire de paquets :$missing"
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Paquets système
# ---------------------------------------------------------------------------

# Exécute une commande de gestionnaire de paquets ($2, une ligne produite par
# lib/deps.sh) avec les privilèges qu'elle demande. Jamais de sudo pour brew,
# qui refuse de tourner en root : si on EST root (sudo), on redescend vers
# l'utilisateur humain.
_nivuus_pkg_run() {
    local mgr="$1" cmd="$2" who
    if nivuus_pkg_needs_root "$mgr"; then
        if nivuus_is_root; then
            DEBIAN_FRONTEND=noninteractive eval "$cmd"
        else
            command -v sudo >/dev/null 2>&1 || { log_error "sudo introuvable : lance « $cmd » en root."; return 1; }
            eval "sudo env DEBIAN_FRONTEND=noninteractive $cmd"
        fi
    else
        if nivuus_is_root; then
            who="$(nivuus_invoking_user)"
            [ "$who" != "root" ] || { log_warn "brew ne tourne pas en root : « $cmd » ignoré."; return 1; }
            eval "sudo -u '$who' $cmd"
        else
            eval "$cmd"
        fi
    fi
}

# Rafraîchit l'index des paquets, une seule fois par processus.
_nivuus_pkg_refresh() {
    local mgr="$1" cmd
    [ -z "${_NIVUUS_PKG_REFRESHED:-}" ] || return 0
    _NIVUUS_PKG_REFRESHED=1
    cmd="$(nivuus_pkg_refresh_cmd "$mgr")"
    [ -n "$cmd" ] || return 0
    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        log_dry "$cmd"
    else
        _nivuus_pkg_run "$mgr" "$cmd" >/dev/null 2>&1 || log_warn "« $cmd » a échoué, on tente l'installation quand même."
    fi
    return 0
}

# Installe les outils manquants parmi $2... avec le gestionnaire de paquets
# de la plateforme, et journalise chaque paquet posé (PKG : jamais
# désinstallé, voir lib/manifest.sh).
#   $1 = required : tout ou rien, échec = retour 1 avec la commande à lancer.
#   $1 = optional : paquet par paquet, un paquet indisponible n'arrête rien.
nivuus_step_install_packages() {
    local level="$1"; shift
    local missing mgr pkgs='' tool pkg cmd
    missing="$(nivuus_deps_missing "$@")"
    [ -n "$missing" ] || return 0

    mgr="$(nivuus_pkg_manager)"
    if [ -z "$mgr" ]; then
        if [ "$level" = required ]; then
            log_error "Dépendances requises manquantes : $missing"
            log_error "Aucun gestionnaire de paquets reconnu : installe-les à la main, puis relance."
            return 1
        fi
        log_warn "Outils optionnels absents (aucun gestionnaire de paquets reconnu) : $missing"
        return 0
    fi

    # shellcheck disable=SC2086  # $missing est une liste séparée par des espaces
    for tool in $missing; do
        pkg="$(nivuus_pkg_name "$mgr" "$tool")"
        if [ -n "$pkg" ]; then
            pkgs="$pkgs $pkg"
        elif [ "$level" = required ]; then
            log_error "$mgr ne fournit pas « $tool » : installe-le à la main, puis relance."
            return 1
        else
            log_info "$tool n'est pas packagé pour $mgr : ignoré."
        fi
    done
    pkgs="${pkgs# }"
    [ -n "$pkgs" ] || return 0

    _nivuus_pkg_refresh "$mgr"

    if [ "$level" = required ]; then
        # shellcheck disable=SC2086
        cmd="$(nivuus_pkg_install_cmd "$mgr" $pkgs)"
        if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
            log_dry "$cmd"
        else
            log_info "Installation des dépendances requises : $pkgs"
            if ! _nivuus_pkg_run "$mgr" "$cmd"; then
                log_error "L'installation des dépendances a échoué. Lance toi-même : sudo $cmd"
                return 1
            fi
        fi
        # shellcheck disable=SC2086
        for pkg in $pkgs; do nivuus_manifest_record PKG "$pkg" '-' "$mgr"; done
        [ -n "${NIVUUS_DRY_RUN:-}" ] || log_ok "Dépendances installées : $pkgs"
        return 0
    fi

    # shellcheck disable=SC2086
    for pkg in $pkgs; do
        cmd="$(nivuus_pkg_install_cmd "$mgr" "$pkg")"
        if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
            log_dry "$cmd"
            nivuus_manifest_record PKG "$pkg" '-' "$mgr"
            continue
        fi
        if _nivuus_pkg_run "$mgr" "$cmd" >/dev/null 2>&1; then
            nivuus_manifest_record PKG "$pkg" '-' "$mgr"
            log_ok "Outil installé : $pkg"
        else
            log_warn "Paquet indisponible ici, ignoré : $pkg"
        fi
    done
    return 0
}

# ---------------------------------------------------------------------------
# Shell de connexion
# ---------------------------------------------------------------------------

: "${NIVUUS_LOGIN_DEFS:=/etc/login.defs}"

# Entrées passwd, une par ligne. NIVUUS_PASSWD (tests) > getent > /etc/passwd.
_nivuus_passwd_entries() {
    if [ -n "${NIVUUS_PASSWD:-}" ]; then
        cat "$NIVUUS_PASSWD"
    elif command -v getent >/dev/null 2>&1; then
        getent passwd
    else
        cat "$NIVUUS_ETC_DIR/passwd"
    fi
}

# Shell de connexion actuel de l'utilisateur $1 (vide si inconnu).
nivuus_user_shell() {
    local user="$1"
    if [ -z "${NIVUUS_PASSWD:-}" ] && [ "$(nivuus_detect_os)" = macos ]; then
        dscl . -read "/Users/$user" UserShell 2>/dev/null | awk '{print $2}'
        return 0
    fi
    _nivuus_passwd_entries | awk -F: -v u="$user" '$1 == u { print $7; exit }'
}

# Le zsh à donner comme shell de connexion : doit figurer dans /etc/shells,
# sinon chsh le refuse (le cas macOS + Homebrew). On préfère le zsh du PATH
# s'il y est listé, à défaut n'importe quel zsh listé et présent ; sinon, en
# root, on l'ajoute à /etc/shells (journalisé en MODIFY, donc réversible).
nivuus_login_shell_candidate() {
    local zsh_path shells line
    zsh_path="$(command -v zsh)" || return 1
    shells="$NIVUUS_ETC_DIR/shells"
    if grep -qxF "$zsh_path" "$shells" 2>/dev/null; then
        printf '%s\n' "$zsh_path"; return 0
    fi
    while IFS= read -r line; do
        case "$line" in
            /*zsh) [ -x "$line" ] && { printf '%s\n' "$line"; return 0; } ;;
        esac
    done < "$shells" 2>/dev/null
    nivuus_is_root || return 1
    { [ -f "$shells" ] && cat "$shells"; printf '%s\n' "$zsh_path"; } | nivuus_write_file "$shells" || return 1
    printf '%s\n' "$zsh_path"
}

# Fait de zsh le shell de connexion de $1, et journalise l'ancien (CHSH).
# Ne touche à rien si c'est déjà zsh. Jamais bloquant : un échec se résout
# en un conseil, pas en une installation interrompue.
nivuus_step_chsh() {
    local user="$1" target current
    current="$(nivuus_user_shell "$user")"
    case "$current" in *zsh) return 0 ;; esac
    target="$(nivuus_login_shell_candidate)" || {
        log_warn "zsh n'est pas listé dans $NIVUUS_ETC_DIR/shells : shell de connexion de $user inchangé."
        return 0
    }
    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        log_dry "chsh -s $target $user"
        nivuus_manifest_record CHSH "$user" "$target" "${current:--}"
        return 0
    fi
    if nivuus_is_root; then
        chsh -s "$target" "$user" >/dev/null 2>&1
    elif [ "$user" = "$(id -un)" ]; then
        if ! nivuus_is_tty; then
            log_info "Pour faire de zsh ton shell de connexion : chsh -s $target"
            return 0
        fi
        log_info "Mot de passe demandé par chsh pour faire de zsh ton shell de connexion :"
        chsh -s "$target"
    else
        log_warn "Changer le shell de $user demande root : sudo chsh -s $target $user"
        return 0
    fi || {
        log_warn "chsh a échoué pour $user. À la main : chsh -s $target $user"
        return 0
    }
    nivuus_manifest_record CHSH "$user" "$target" "${current:--}"
    log_ok "Shell de connexion de $user : zsh"
}

# Comptes humains de la machine : UID dans [UID_MIN, UID_MAX] de
# /etc/login.defs (1000..60000 à défaut) plus root, avec un répertoire
# personnel existant et un shell de connexion réel (listé dans /etc/shells :
# exclut nologin, false et les comptes de service).
nivuus_human_users() {
    local min max user home shell
    min="$(awk '$1 == "UID_MIN" { print $2 }' "$NIVUUS_LOGIN_DEFS" 2>/dev/null)"
    max="$(awk '$1 == "UID_MAX" { print $2 }' "$NIVUUS_LOGIN_DEFS" 2>/dev/null)"
    : "${min:=1000}" "${max:=60000}"
    _nivuus_passwd_entries | awk -F: -v min="$min" -v max="$max" \
        '($3 == 0 || ($3 >= min && $3 <= max)) { print $1 ":" $3 ":" $6 ":" $7 }' \
    | while IFS=: read -r user _ home shell; do
        [ -d "$home" ] || continue
        [ -n "$shell" ] || continue
        grep -qxF "$shell" "$NIVUUS_ETC_DIR/shells" 2>/dev/null || continue
        printf '%s\n' "$user"
    done
}

# Mode système : zsh pour tous les comptes humains.
nivuus_step_chsh_all_users() {
    local user
    if [ "$(nivuus_detect_os)" = macos ]; then
        log_info "macOS : zsh est déjà le shell par défaut, rien à changer."
        return 0
    fi
    while IFS= read -r user; do
        [ -n "$user" ] || continue
        nivuus_step_chsh "$user"
    done < <(nivuus_human_users)
    return 0
}
