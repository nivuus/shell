# shellcheck shell=bash
# lib/deps.sh
# Dépendances : quoi installer, sous quel nom, avec quelle commande.
# Fonctions pures (stdout uniquement) : rien ici n'exécute un gestionnaire
# de paquets. L'exécution vit dans lib/steps.sh.

# Requis : sans eux Nivuus ne démarre pas.
# shellcheck disable=SC2034  # lus par lib/steps.sh et bin/nivuus
NIVUUS_DEPS_REQUIRED="zsh git curl"
# Optionnels : chaque module se dégrade proprement sans eux.
# shellcheck disable=SC2034
NIVUUS_DEPS_OPTIONAL="jq fzf eza bat fd ripgrep timg grc git-delta"

# L'outil $1 est-il présent ? Tient compte des noms Debian (batcat, fdfind).
nivuus_dep_present() {
    local tool="$1"
    case "$tool" in
        bat)       command -v bat >/dev/null 2>&1 || command -v batcat >/dev/null 2>&1 ;;
        fd)        command -v fd  >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1 ;;
        ripgrep)   command -v rg >/dev/null 2>&1 ;;
        git-delta) command -v delta >/dev/null 2>&1 ;;
        *)         command -v "$tool" >/dev/null 2>&1 ;;
    esac
}

# Parmi $@, les outils absents (séparés par des espaces).
nivuus_deps_missing() {
    local tool out=''
    for tool in "$@"; do
        nivuus_dep_present "$tool" || out="$out $tool"
    done
    printf '%s\n' "${out# }"
}

# Nom du paquet fournissant l'outil $2 chez le gestionnaire $1.
# Vide si le gestionnaire ne le fournit pas.
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

# Commande d'installation (une ligne, prête à être exécutée via eval ou
# affichée) pour les paquets $2... chez le gestionnaire $1. brew n'est
# jamais préfixé de sudo : il refuse de tourner en root.
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

# Rafraîchissement de l'index, quand le gestionnaire en a besoin avant
# d'installer. Vide sinon.
nivuus_pkg_refresh_cmd() {
    case "$1" in
        apt-get) printf 'apt-get update -qq\n' ;;
        apk)     printf 'apk update -q\n' ;;
        *)       printf '\n' ;;
    esac
}

# Le gestionnaire $1 doit-il être lancé avec des privilèges root ?
nivuus_pkg_needs_root() {
    [ "$1" != "brew" ]
}
