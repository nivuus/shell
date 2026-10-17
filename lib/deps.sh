# shellcheck shell=bash
# lib/deps.sh
# Dependencies: what to install, under which package name, with which command.
# Pure functions (stdout only): nothing here runs a package manager. The
# execution lives in lib/steps.sh.
# Sourced by the bash installer and by zsh (config/18-autosuggestions.zsh,
# config/98-syntax.zsh at every startup, config/11-files.zsh for its hint):
# it stays within the syntax both shells share and forks nothing when
# sourced. nivuus_pkg_hint_cmd needs lib/detect.sh.

# Required: Nivuus does not start without them.
# shellcheck disable=SC2034  # read by lib/steps.sh and bin/nivuus
NIVUUS_DEPS_REQUIRED="zsh git curl"
# Optional: every module degrades gracefully without them.
# zsh-autosuggestions and zsh-syntax-highlighting are zsh plugins, not
# commands: nivuus_dep_present looks for them where the config modules load
# them from (nivuus_plugin_find).
# shellcheck disable=SC2034
NIVUUS_DEPS_OPTIONAL="jq fzf eza bat fd ripgrep timg grc git-delta zsh-autosuggestions zsh-syntax-highlighting"

# Sets REPLY to the path of zsh plugin $1's entry file and returns 0, or
# returns 1 if it is not installed in any known location.
# Locations: Debian/Ubuntu/Fedora (/usr/share), Arch and Alpine
# (/usr/share/zsh/plugins), Homebrew (Intel /usr/local, Apple Silicon
# /opt/homebrew), manual clones. NIVUUS_PLUGIN_ROOT replaces the whole list,
# for tests.
nivuus_plugin_find() {
    local name="$1" root
    if [ -n "${NIVUUS_PLUGIN_ROOT:-}" ]; then
        set -- "$NIVUUS_PLUGIN_ROOT"
    else
        set -- /usr/share /usr/share/zsh/plugins /usr/local/share \
            /opt/homebrew/share "$HOME/.local/share" "$HOME/.zsh"
    fi
    for root in "$@"; do
        if [ -f "$root/$name/$name.zsh" ]; then
            REPLY="$root/$name/$name.zsh"
            return 0
        fi
    done
    return 1
}

# Is tool $1 present? Knows the Debian names (batcat, fdfind).
nivuus_dep_present() {
    local tool="$1"
    case "$tool" in
        bat)       command -v bat >/dev/null 2>&1 || command -v batcat >/dev/null 2>&1 ;;
        fd)        command -v fd  >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1 ;;
        ripgrep)   command -v rg >/dev/null 2>&1 ;;
        git-delta) command -v delta >/dev/null 2>&1 ;;
        zsh-autosuggestions|zsh-syntax-highlighting) nivuus_plugin_find "$tool" ;;
        *)         command -v "$tool" >/dev/null 2>&1 ;;
    esac
}

# The absent tools among $@ (space-separated).
nivuus_deps_missing() {
    local tool out=''
    for tool in "$@"; do
        nivuus_dep_present "$tool" || out="$out $tool"
    done
    printf '%s\n' "${out# }"
}

# Name of the package providing tool $2 with package manager $1.
# Empty when the manager does not ship it.
nivuus_pkg_name() {
    local mgr="$1" tool="$2"
    case "$tool" in
        fd)
            case "$mgr" in
                apt-get|dnf|yum) printf 'fd-find\n' ;;
                *)               printf 'fd\n' ;;
            esac ;;
        git-delta)
            case "$mgr" in
                apk) printf 'delta\n' ;;
                *)   printf 'git-delta\n' ;;
            esac ;;
        grc)
            case "$mgr" in
                apk|zypper) printf '\n' ;;
                *)          printf 'grc\n' ;;
            esac ;;
        timg)
            case "$mgr" in
                yum|zypper) printf '\n' ;;
                *)          printf 'timg\n' ;;
            esac ;;
        *) printf '%s\n' "$tool" ;;
    esac
}

# Install command (one line, ready to be eval'd or displayed) for packages
# $2... with package manager $1. brew is never prefixed with sudo: it refuses
# to run as root.
nivuus_pkg_install_cmd() {
    local mgr="$1"; shift
    case "$mgr" in
        apt-get) printf 'apt-get install -y --no-install-recommends %s\n' "$*" ;;
        dnf)     printf 'dnf install -y %s\n' "$*" ;;
        yum)     printf 'yum install -y %s\n' "$*" ;;
        pacman)  printf 'pacman -S --noconfirm --needed %s\n' "$*" ;;
        zypper)  printf 'zypper --non-interactive install %s\n' "$*" ;;
        apk)     printf 'apk add %s\n' "$*" ;;
        brew)    printf 'brew install %s\n' "$*" ;;
        *)       printf '\n' ;;
    esac
}

# Index refresh, for the managers that need one before installing. Empty
# otherwise.
nivuus_pkg_refresh_cmd() {
    case "$1" in
        apt-get) printf 'apt-get update -qq\n' ;;
        apk)     printf 'apk update -q\n' ;;
        *)       printf '\n' ;;
    esac
}

# Must package manager $1 run with root privileges?
nivuus_pkg_needs_root() {
    [ "$1" != "brew" ]
}

# The command a person runs to install tools $2... with package manager $1,
# for hints: their package names, prefixed with sudo when the manager needs
# root and we are not root. Tools the manager does not ship are left out;
# empty when none is left or the manager is unknown.
nivuus_pkg_hint_cmd() {
    local mgr="$1" tool pkg pkgs='' cmd
    shift
    for tool in "$@"; do
        pkg="$(nivuus_pkg_name "$mgr" "$tool")"
        [ -z "$pkg" ] || pkgs="$pkgs $pkg"
    done
    # One argument holding every name: nivuus_pkg_install_cmd joins with
    # "$*", and zsh would not word-split an unquoted $pkgs.
    [ -n "$pkgs" ] && cmd="$(nivuus_pkg_install_cmd "$mgr" "${pkgs# }")"
    if [ -n "${cmd:-}" ] && nivuus_pkg_needs_root "$mgr" && ! nivuus_is_root; then
        cmd="sudo $cmd"
    fi
    printf '%s\n' "${cmd:-}"
}
