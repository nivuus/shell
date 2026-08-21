# Détection de plateforme. Ne connaît pas le système de fichiers cible.
# Les chemins système sont paramétrables pour rester testables.

: "${NIVUUS_DOCKERENV:=/.dockerenv}"
: "${NIVUUS_CGROUP:=/proc/1/cgroup}"
: "${NIVUUS_OS_RELEASE:=/etc/os-release}"
: "${NIVUUS_PROC_VERSION:=/proc/version}"
: "${NIVUUS_ETC_SHELLS:=/etc/shells}"
: "${NIVUUS_BREW_ARM:=/opt/homebrew}"
: "${NIVUUS_BREW_INTEL:=/usr/local}"

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

nivuus_is_wsl() {
    [ -n "${WSL_DISTRO_NAME:-}" ] && return 0
    [ -n "${WSL_INTEROP:-}" ] && return 0
    grep -qi 'microsoft\|wsl' "$NIVUUS_PROC_VERSION" 2>/dev/null && return 0
    return 1
}

nivuus_is_ssh() {
    [ -n "${SSH_CONNECTION:-}" ] && return 0
    [ -n "${SSH_CLIENT:-}" ] && return 0
    [ -n "${SSH_TTY:-}" ] && return 0
    return 1
}

# « Pas d'endroit où installer une police » plutôt que « pas d'écran » :
# macOS et WSL ont toujours un terminal hôte, même sans $DISPLAY côté Unix.
nivuus_is_headless() {
    [ "$(nivuus_detect_os)" = "macos" ] && return 1
    nivuus_is_wsl && return 1
    [ -n "${DISPLAY:-}" ] && return 1
    [ -n "${WAYLAND_DISPLAY:-}" ] && return 1
    return 0
}

# Ordre délibéré : la surcharge explicite de l'utilisateur passe AVANT
# toute heuristique, dans les deux sens.
nivuus_should_minimal() {
    [ -n "${NIVUUS_NO_MINIMAL:-}" ] && return 1
    [ -n "${NIVUUS_MINIMAL:-}" ] && return 0
    nivuus_is_container && return 0
    nivuus_is_tty || return 0
    nivuus_is_ssh && return 0
    nivuus_is_headless && return 0
    return 1
}

# Première affectation non commentée de la clé demandée dans un fichier
# style os-release. awk plutôt qu'un `source` : ce fichier appartient au
# système, on ne l'exécute pas.
_nivuus_os_release_key() {
    local key="$1"
    [ -r "$NIVUUS_OS_RELEASE" ] || return 0
    awk -F= -v k="$key" '
        /^[[:space:]]*#/ { next }
        $1 == k { sub(/^[^=]*=/, "", $0); gsub(/^["\047]|["\047]$/, "", $0); print; exit }
    ' "$NIVUUS_OS_RELEASE" 2>/dev/null
}

nivuus_detect_distro() {
    local id=''
    if [ "$(nivuus_detect_os)" = "macos" ]; then
        printf 'macos\n'
        return 0
    fi
    id="$(_nivuus_os_release_key ID)"
    [ -n "$id" ] || id='unknown'
    printf '%s\n' "$id"
}

nivuus_detect_distro_like() {
    [ "$(nivuus_detect_os)" = "macos" ] && return 0
    _nivuus_os_release_key ID_LIKE
}

nivuus_detect_arch() {
    case "$(uname -m)" in
        arm64|aarch64) printf 'arm64\n' ;;
        x86_64|amd64)  printf 'x86_64\n' ;;
        *)             uname -m ;;
    esac
}

nivuus_brew_prefix() {
    local p
    if command -v brew >/dev/null 2>&1; then
        p="$(brew --prefix 2>/dev/null)"
        [ -n "$p" ] && { printf '%s\n' "$p"; return 0; }
    fi
    for p in "$NIVUUS_BREW_ARM" "$NIVUUS_BREW_INTEL"; do
        if [ -x "$p/bin/brew" ]; then
            printf '%s\n' "$p"
            return 0
        fi
    done
    return 1
}

# Le zsh de Homebrew est préféré au /bin/zsh d'Apple : c'est celui que
# l'utilisateur macOS met à jour, et celui qu'il attend comme shell de
# connexion. C'est aussi celui qui n'est PAS dans /etc/shells par défaut --
# d'où nivuus_shell_is_listed juste en dessous.
nivuus_zsh_path() {
    local prefix
    prefix="$(nivuus_brew_prefix 2>/dev/null)" || prefix=''
    if [ -n "$prefix" ] && [ -x "$prefix/bin/zsh" ]; then
        printf '%s\n' "$prefix/bin/zsh"
        return 0
    fi
    command -v zsh 2>/dev/null || return 1
}

nivuus_shell_is_listed() {
    local shell_path="$1"
    [ -r "$NIVUUS_ETC_SHELLS" ] || return 1
    grep -qxF "$shell_path" "$NIVUUS_ETC_SHELLS" 2>/dev/null
}

# $NIVUUS_LOGIN_SHELL_FILE : crochet de test. Quand il est défini, il fait
# autorité -- c'est aussi ce que le faux `chsh` des tests écrit, et ce que
# l'empreinte de réversibilité relit (tests/helpers/fingerprint.bash).
nivuus_current_login_shell() {
    local user shell_path=''
    if [ -n "${NIVUUS_LOGIN_SHELL_FILE:-}" ]; then
        if [ -f "$NIVUUS_LOGIN_SHELL_FILE" ]; then
            head -n1 "$NIVUUS_LOGIN_SHELL_FILE"
        else
            printf '%s\n' "${SHELL:-}"
        fi
        return 0
    fi
    user="$(id -un 2>/dev/null)"
    if [ -n "$user" ] && command -v getent >/dev/null 2>&1; then
        shell_path="$(getent passwd "$user" 2>/dev/null | awk -F: 'NR==1 {print $NF}')"
    fi
    if [ -z "$shell_path" ] && [ "$(nivuus_detect_os)" = "macos" ] \
        && command -v dscl >/dev/null 2>&1; then
        shell_path="$(dscl . -read "/Users/$user" UserShell 2>/dev/null | awk 'NR==1 {print $2}')"
    fi
    [ -n "$shell_path" ] || shell_path="${SHELL:-}"
    printf '%s\n' "$shell_path"
}
