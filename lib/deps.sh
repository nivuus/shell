# lib/deps.sh
# Constate les dépendances et PROPOSE une commande. N'en exécute jamais
# aucune : c'est la seule garantie qui rend « pas de sudo surprise »
# vérifiable en test (voir tests/unit/test_lib_deps.bats).
# Sourcé, jamais exécuté : ne fixe pas set -euo pipefail.

NIVUUS_DEPS_REQUIRED='zsh git curl'
NIVUUS_DEPS_RECOMMENDED='fzf'
NIVUUS_DEPS_OPTIONAL='bat eza grc'

# brew en dernier : sur une machine Linux avec Linuxbrew, le gestionnaire
# système reste le bon choix pour zsh/git/curl.
nivuus_pkg_manager() {
    local m
    for m in apt-get dnf yum pacman apk zypper brew; do
        if command -v "$m" >/dev/null 2>&1; then
            printf '%s\n' "$m"
            return 0
        fi
    done
    return 1
}

nivuus_sudo_prefix() {
    local mgr="${1:-}"
    [ "$mgr" = "brew" ] && return 0          # Homebrew refuse d'être lancé en root
    [ "$(id -u 2>/dev/null)" = "0" ] && return 0
    command -v sudo >/dev/null 2>&1 && printf 'sudo '
    return 0
}

nivuus_pkg_install_cmd() {
    local mgr sudo_p pkgs="$*"
    mgr="$(nivuus_pkg_manager)" || {
        printf 'installe %s avec le gestionnaire de paquets de ta plateforme\n' "$pkgs"
        return 0
    }
    sudo_p="$(nivuus_sudo_prefix "$mgr")"
    case "$mgr" in
        apt-get) printf '%sapt-get install -y %s\n' "$sudo_p" "$pkgs" ;;
        dnf)     printf '%sdnf install -y %s\n'     "$sudo_p" "$pkgs" ;;
        yum)     printf '%syum install -y %s\n'     "$sudo_p" "$pkgs" ;;
        pacman)  printf '%spacman -S --noconfirm %s\n' "$sudo_p" "$pkgs" ;;
        apk)     printf '%sapk add --no-cache %s\n' "$sudo_p" "$pkgs" ;;
        zypper)  printf '%szypper install -y %s\n'  "$sudo_p" "$pkgs" ;;
        brew)    printf 'brew install %s\n' "$pkgs" ;;
    esac
}

nivuus_deps_list() {
    case "$1" in
        required)    printf '%s\n' "$NIVUUS_DEPS_REQUIRED" ;;
        recommended) printf '%s\n' "$NIVUUS_DEPS_RECOMMENDED" ;;
        optional)    printf '%s\n' "$NIVUUS_DEPS_OPTIONAL" ;;
        *)           return 1 ;;
    esac
}

nivuus_deps_missing() {
    local level="$1" c list
    list="$(nivuus_deps_list "$level")" || return 1
    for c in $list; do
        command -v "$c" >/dev/null 2>&1 || printf '%s\n' "$c"
    done
    return 0
}

# Liste manquante en une seule ligne, sans `tr` : cette fonction doit rester
# vraie même avec un PATH vide (c'est précisément le cas où TOUT manque).
_nivuus_deps_missing_flat() {
    local c out=''
    for c in $(nivuus_deps_missing "$1"); do
        out="$out $c"
    done
    printf '%s' "${out# }"
}

nivuus_deps_check_required() {
    local missing
    missing="$(_nivuus_deps_missing_flat required)"
    [ -n "$missing" ] || return 0
    log_error "Dépendances requises manquantes : $missing"
    log_error "Installe-les avec :"
    log_error "  $(nivuus_pkg_install_cmd $missing)"
    return 1
}

nivuus_deps_suggest() {
    local level="$1" missing
    missing="$(_nivuus_deps_missing_flat "$level")"
    [ -n "$missing" ] || return 0
    case "$level" in
        recommended) log_info "Recommandé (Nivuus fonctionne sans, en mode dégradé) : $missing" ;;
        *)           log_info "Optionnel (confort supplémentaire) : $missing" ;;
    esac
    log_info "  $(nivuus_pkg_install_cmd $missing)"
    return 0
}
