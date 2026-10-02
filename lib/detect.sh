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
# Privileges and system-wide install.
# Every system path or identity can be overridden by an environment variable
# so the tests never need to be root nor touch /etc.
# ---------------------------------------------------------------------------

: "${NIVUUS_UID:=${EUID:-$(id -u)}}"
: "${NIVUUS_ETC_DIR:=/etc}"
: "${NIVUUS_SYSTEM_PREFIX:=/usr/local/share/nivuus-shell}"
: "${NIVUUS_SYSTEM_STATE_DIR:=/var/lib/nivuus}"

nivuus_is_root() {
    [ "${NIVUUS_UID:-$(id -u)}" -eq 0 ]
}

# The human user behind sudo, if any (the current user otherwise).
nivuus_invoking_user() {
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        printf '%s\n' "$SUDO_USER"
    else
        id -un
    fi
}

# Is sudo usable without asking anything? (-n: never prompts)
nivuus_sudo_available() {
    command -v sudo >/dev/null 2>&1 || return 1
    sudo -n true >/dev/null 2>&1
}

# The global zshrc every user reads. Debian, Ubuntu, Arch and Alpine build
# zsh with /etc/zsh as its configuration directory; Fedora, openSUSE and
# macOS read /etc/zshrc. The presence of the /etc/zsh directory decides.
# NIVUUS_SYSTEM_ZSHRC forces a path (tests, exotic setups).
nivuus_system_zshrc() {
    if [ -n "${NIVUUS_SYSTEM_ZSHRC:-}" ]; then
        printf '%s\n' "$NIVUUS_SYSTEM_ZSHRC"
    elif [ -d "$NIVUUS_ETC_DIR/zsh" ]; then
        printf '%s\n' "$NIVUUS_ETC_DIR/zsh/zshrc"
    else
        printf '%s\n' "$NIVUUS_ETC_DIR/zshrc"
    fi
}

# The platform's package manager, or an empty string.
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
