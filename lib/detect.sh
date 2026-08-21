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
