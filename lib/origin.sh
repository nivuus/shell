# lib/origin.sh
# D'où vient cette installation ? Ce module ne connaît rien d'autre.
#
# Source de vérité : $dir/.nivuus-origin, fichier texte clé=valeur posé par
# la recette de paquet et par elle seule. Son ABSENCE vaut « source »,
# c'est-à-dire le comportement d'aujourd'hui : c'est ce qui garantit qu'une
# régression de ce module ne peut pas atteindre le canal principal.
#
# POSIX strict (BusyBox ash, bash 3.2) : ni [[ ]], ni tableaux, ni bashismes.

nivuus_origin_field() {
    local dir="$1" key="$2" value
    [ -r "$dir/.nivuus-origin" ] || return 1
    value="$(sed -n "s/^$key=//p" "$dir/.nivuus-origin" 2>/dev/null | head -n1)"
    [ -n "$value" ] || return 1
    printf '%s\n' "$value"
}

# Toujours 0, toujours une valeur : « source » ou « package ». Une valeur
# inconnue vaut source (permissif) -- la sûreté, dans ce cas, est portée par
# nivuus_origin_tree_writable, qui est indépendant du marqueur.
nivuus_origin() {
    local value
    value="$(nivuus_origin_field "$1" origin 2>/dev/null || printf 'source')"
    case "$value" in
        package) printf 'package\n' ;;
        *)       printf 'source\n' ;;
    esac
}

nivuus_origin_is_package() { [ "$(nivuus_origin "$1")" = "package" ]; }

nivuus_origin_channel() {
    nivuus_origin_field "$1" channel 2>/dev/null || printf 'unknown\n'
}

# La commande affichée est DÉRIVÉE du champ channel=, jamais devinée à partir
# du chemin d'installation ni du gestionnaire présent sur la machine.
nivuus_origin_update_command() {
    local dir="$1" channel pkg
    channel="$(nivuus_origin_channel "$dir")"
    pkg="$(nivuus_origin_field "$dir" package 2>/dev/null || printf 'nivuus-shell')"
    case "$channel" in
        homebrew) printf 'brew upgrade %s\n' "$pkg" ;;
        aur)      printf '%s\n' "yay -Syu $pkg   (ou paru -Syu $pkg, selon ton assistant AUR)" ;;
        deb)      printf '%s\n' "apt upgrade $pkg   (ou, pour un .deb téléchargé à la main, la page de release du projet)" ;;
        *)        printf '%s\n' "la commande de mise à jour de ton gestionnaire de paquets" ;;
    esac
}

# Garde-fou SECONDAIRE, indépendant du marqueur : il couvre le cas « un tiers
# a empaqueté Nivuus sans poser le marqueur », qui arrivera, parce que l'AUR
# et les taps sont ouverts à tous. Inopérant en root -- c'est assumé, et
# c'est pour ça que le marqueur existe en plus. Le marqueur porte le MESSAGE,
# le garde-fou porte la SÛRETÉ ; aucun des deux ne suffit seul.
nivuus_origin_tree_writable() { [ -d "$1" ] && [ -w "$1" ]; }
