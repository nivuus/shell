# Détection de plateforme. Ne connaît pas le système de fichiers cible.
# Les chemins système sont paramétrables pour rester testables.

: "${NIVUUS_DOCKERENV:=/.dockerenv}"
: "${NIVUUS_CGROUP:=/proc/1/cgroup}"
: "${NIVUUS_OS_RELEASE:=/etc/os-release}"

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
