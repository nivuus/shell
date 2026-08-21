#!/bin/sh
# install.sh — porte d'entrée unique de Nivuus Shell.
#
# Deux modes, un seul fichier, une seule URL :
#   voisin    : un noyau (bin/nivuus + lib/) est présent à côté de ce
#               script, on lui délègue -- c'est le cas du checkout et de
#               l'archive de release déjà extraite.
#   amorçage  : ce script est seul (« curl … | sh »), on résout la version,
#               on télécharge l'archive de release, on la VÉRIFIE, on
#               l'extrait dans un temporaire et on délègue au noyau extrait.
#
# POSIX sh strict : ce fichier doit tourner sous dash, BusyBox ash et
# bash 3.2. « curl | sh » ne choisit pas le shell de l'utilisateur.
# Pas de tableaux, pas de variables de fonction, pas de crochets doubles,
# pas de variable magique de source bash.
set -eu

# Plancher de version, resynchronisé par .github/workflows/release.yml.
# Sert uniquement quand l'API GitHub est injoignable ou a rendu son quota.
NIVUUS_PINNED_VERSION="3.0.0"

usage() {
    cat <<'USAGE'
install.sh — installe Nivuus Shell

Usage :
  curl -fsSL https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh | sh
  ./install.sh [options]                      (depuis une archive extraite ou un checkout)

Options :
  --non-interactive   N'attend aucune réponse.
  --dry-run           N'écrit rien ; affiche ce qui serait fait.
  --prefix DIR        Répertoire d'installation (défaut : ~/.nivuus-shell).
  --minimal           Mode serveur / container : pas de chsh, pas d'extras.
  --no-minimal        Force le mode complet.
  --with-deps         Propose UNE commande groupée pour les dépendances.
  --no-backup         Accepté sans effet : le manifeste sauvegarde toujours.
  --verify-key EMPR   Épingle l'empreinte du trousseau de signature.
  --health-check      Lance « nivuus doctor » après l'installation.
  --system            Indisponible dans cette version (sort en erreur).
  --help              Affiche ceci.

Désinstallation :
  nivuus uninstall            (retire tout ce que Nivuus a écrit)
  nivuus uninstall --purge    (retire aussi l'état interne de Nivuus)

Variables d'environnement :
  NIVUUS_VERSION            Version à installer (défaut : dernière release).
  NIVUUS_RELEASE_BASE_URL   Base des artefacts de release (tests, miroirs).
  NIVUUS_GITHUB_API         Base de l'API GitHub.
USAGE
}

# Racine du noyau voisin, ou échec s'il n'y en a pas.
#
# Exige que $0 soit lui-même un fichier lisible : sous « curl … | sh », $0
# vaut « sh » et n'est pas un fichier, donc on ne prendra jamais par erreur
# le répertoire courant pour une installation source -- y compris quand le
# one-liner est lancé depuis un checkout de Nivuus.
nivuus_local_root() {
    [ -f "$0" ] || return 1
    case "$0" in
        */*) _d="${0%/*}" ;;
        *)   _d="." ;;
    esac
    [ -f "$_d/bin/nivuus" ] || return 1
    [ -f "$_d/lib/manifest.sh" ] || return 1
    ( cd "$_d" && pwd )
}

# Remplacé par le vrai amorçage en Task 4 de ce chantier.
nivuus_bootstrap() {
    printf '%s\n' "Aucun noyau Nivuus à côté de ce script, et l'amorçage n'est pas encore disponible." >&2
    printf '%s\n' "Extrais l'archive de release et relance ./install.sh depuis son répertoire." >&2
    return 1
}

nivuus_die() {
    printf '%s\n' "$*" >&2
    exit 1
}

# Récupère $1 vers le fichier $2.
#
# Ordre : file:// par copie, puis curl, puis wget. Aucun repli silencieux :
# si aucun client n'est disponible, on dit quoi faire à la main plutôt que
# de sortir en 0 avec un fichier vide.
nivuus_fetch() {
    _url="$1"; _dest="$2"
    case "$_url" in
        file://*)
            # curl sait lire file://, wget pas toujours. Une copie est
            # portable et rend la couverture des tests hors réseau
            # indépendante du client HTTP présent sur la machine.
            _src="${_url#file://}"
            [ -f "$_src" ] || return 1
            cp "$_src" "$_dest" || return 1
            return 0
            ;;
    esac
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$_dest" "$_url" || { rm -f "$_dest"; return 1; }
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$_dest" "$_url" || { rm -f "$_dest"; return 1; }
    else
        printf '%s\n' "Ni curl ni wget n'est disponible : impossible de télécharger" >&2
        printf '%s\n' "  $_url" >&2
        printf '%s\n' "Installe curl ou wget, ou télécharge l'archive de release à la main" >&2
        printf '%s\n' "puis lance ./install.sh depuis son répertoire (voir doc/INSTALL.md)." >&2
        return 127
    fi
    return 0
}

nivuus_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        printf '%s\n' "Aucun outil sha256 (sha256sum ou shasum) : l'archive ne peut pas être vérifiée." >&2
        printf '%s\n' "Nivuus n'installe pas ce qu'il ne peut pas vérifier." >&2
        return 1
    fi
}

# Crochet de test : sourcé avec NIVUUS_SOURCE_ONLY, ce fichier ne définit
# que ses fonctions. C'est la seule façon de tester nivuus_fetch et
# nivuus_sha256 sans réseau ni installation -- et c'est aussi ce qui rend
# possible de constater le rouge sur chacune d'elles séparément.
# « return » hors fonction est valide dans un fichier SOURCÉ et une erreur
# dans un fichier exécuté ; le « || : » protège du second cas.
[ -n "${NIVUUS_SOURCE_ONLY:-}" ] && return 0 2>/dev/null || :

# --- Traduction des anciens flags --------------------------------------
#
# Pas de tableau en POSIX sh : on fait tourner les paramètres positionnels
# autour d'une sentinelle. Tout ce qui est avant « -- » est d'origine, tout
# ce qui est après est traduit ; à la sortie de la boucle il ne reste que
# le traduit.
RUN_DOCTOR=''
set -- "$@" --
while [ "$1" != "--" ]; do
    arg="$1"; shift
    case "$arg" in
        --system)
            printf '%s\n' "L'installation système (--system) n'est pas encore disponible dans cette version." >&2
            printf '%s\n' "Utilise l'installation utilisateur (sans --system) en attendant." >&2
            exit 1
            ;;
        --non-interactive) set -- "$@" --yes ;;
        --health-check)    RUN_DOCTOR=1 ;;
        --no-backup)       : ;;   # accepté, sans effet : le manifeste sauvegarde toujours
        --dry-run|--minimal|--no-minimal|--with-deps|--yes|-y)
            set -- "$@" "$arg" ;;
        --prefix)
            [ "$1" != "--" ] || { printf "L'option --prefix attend un chemin.\n" >&2; exit 2; }
            val="$1"; shift
            set -- "$@" --prefix "$val" ;;
        # Ajoutée par le chantier « signature ». Elle doit traverser la
        # réécriture POSIX, pas disparaître avec elle.
        --verify-key)
            [ "$1" != "--" ] || { printf "L'option --verify-key attend une empreinte.\n" >&2; exit 2; }
            val="$1"; shift
            set -- "$@" --verify-key "$val" ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'Option inconnue : %s\n' "$arg" >&2; exit 2 ;;
    esac
done
shift    # retire la sentinelle

ROOT="$(nivuus_local_root || true)"
if [ -z "$ROOT" ]; then
    nivuus_bootstrap "$@"
    exit $?
fi

"$ROOT/bin/nivuus" install "$@"

if [ -n "$RUN_DOCTOR" ]; then
    "$ROOT/bin/nivuus" doctor
fi
