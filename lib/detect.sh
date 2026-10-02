# shellcheck shell=bash
# Détection de plateforme. Ne connaît pas le système de fichiers cible.
# Les chemins système sont paramétrables pour rester testables.

: "${NIVUUS_DOCKERENV:=/.dockerenv}"
: "${NIVUUS_CGROUP:=/proc/1/cgroup}"

nivuus_detect_os() {
    case "$(uname -s)" in
        Darwin) printf 'macos\n' ;;
        *)      printf 'linux\n' ;;
    esac
}

nivuus_is_container() {
    [ -f "$NIVUUS_DOCKERENV" ] && return 0
    [ -n "${container:-}" ] && return 0
    grep -qE '(docker|lxc|containerd)' "$NIVUUS_CGROUP" 2>/dev/null && return 0
    return 1
}

nivuus_is_tty() {
    [ -t 0 ] && [ -t 1 ]
}

nivuus_should_minimal() {
    nivuus_is_container && return 0
    nivuus_is_tty || return 0
    return 1
}

# ---------------------------------------------------------------------------
# Privilèges et installation système.
# Tout chemin ou identité système est surchargeable par variable d'environnement
# pour que les tests n'aient jamais besoin d'être root ni de toucher /etc.
# ---------------------------------------------------------------------------

: "${NIVUUS_UID:=${EUID:-$(id -u)}}"
: "${NIVUUS_ETC_DIR:=/etc}"
: "${NIVUUS_SYSTEM_PREFIX:=/usr/local/share/nivuus-shell}"
: "${NIVUUS_SYSTEM_STATE_DIR:=/var/lib/nivuus}"

nivuus_is_root() {
    [ "${NIVUUS_UID:-$(id -u)}" -eq 0 ]
}

# L'utilisateur humain derrière un éventuel sudo (sinon l'utilisateur courant).
nivuus_invoking_user() {
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        printf '%s\n' "$SUDO_USER"
    else
        id -un
    fi
}

# sudo est-il utilisable sans rien demander ? (-n : jamais de prompt)
nivuus_sudo_available() {
    command -v sudo >/dev/null 2>&1 || return 1
    sudo -n true >/dev/null 2>&1
}

# Le .zshrc global lu par tous les utilisateurs. Debian, Ubuntu, Arch et
# Alpine compilent zsh avec /etc/zsh comme répertoire de configuration ;
# Fedora, openSUSE et macOS lisent /etc/zshrc. La présence du répertoire
# /etc/zsh tranche. NIVUUS_SYSTEM_ZSHRC force un chemin (tests, cas exotiques).
nivuus_system_zshrc() {
    if [ -n "${NIVUUS_SYSTEM_ZSHRC:-}" ]; then
        printf '%s\n' "$NIVUUS_SYSTEM_ZSHRC"
    elif [ -d "$NIVUUS_ETC_DIR/zsh" ]; then
        printf '%s\n' "$NIVUUS_ETC_DIR/zsh/zshrc"
    else
        printf '%s\n' "$NIVUUS_ETC_DIR/zshrc"
    fi
}

# Gestionnaire de paquets de la plateforme, ou chaîne vide.
nivuus_pkg_manager() {
    if [ -n "${NIVUUS_PKG_MANAGER:-}" ]; then
        printf '%s\n' "$NIVUUS_PKG_MANAGER"; return 0
    fi
    local m
    for m in apt-get dnf yum pacman zypper apk brew; do
        if command -v "$m" >/dev/null 2>&1; then
            printf '%s\n' "$m"; return 0
        fi
    done
    printf '\n'
}
