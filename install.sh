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

: "${NIVUUS_GITHUB_REPO:=maximeallanic/nivuus-shell}"
: "${NIVUUS_GITHUB_API:=https://api.github.com}"
: "${NIVUUS_RELEASE_BASE_URL:=https://github.com/$NIVUUS_GITHUB_REPO/releases/download}"

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

# Version à installer : ce que l'utilisateur demande, sinon la dernière
# release publiée, sinon le plancher épinglé dans ce fichier.
#
# Le plancher n'est pas de la redondance : l'API GitHub non authentifiée
# est limitée à 60 requêtes/h et par IP, ce qui est atteint tous les jours
# derrière un NAT d'entreprise ou sur un runner partagé. Sans plancher, le
# one-liner y devient un tirage au sort.
nivuus_resolve_version() {
    if [ -n "${NIVUUS_VERSION:-}" ]; then
        printf '%s\n' "$NIVUUS_VERSION"
        return 0
    fi
    _api_tmp="$(mktemp "${TMPDIR:-/tmp}/nivuus-api.XXXXXX")" || return 1
    if nivuus_fetch "$NIVUUS_GITHUB_API/repos/$NIVUUS_GITHUB_REPO/releases/latest" "$_api_tmp"; then
        # tr avant sed : le motif reste sans double crochet, que le test
        # « aucun bashisme » interdit dans ce fichier.
        _tag="$(tr '\t' ' ' < "$_api_tmp" \
                | sed -n 's/.*"tag_name" *: *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n1)"
    else
        _tag=''
    fi
    rm -f "$_api_tmp"
    if [ -n "$_tag" ]; then
        printf '%s\n' "$_tag"
    else
        printf '%s\n' "Dernière version indisponible (réseau ou quota d'API) ; repli sur la version épinglée $NIVUUS_PINNED_VERSION." >&2
        printf '%s\n' "$NIVUUS_PINNED_VERSION"
    fi
}

# Télécharge, vérifie, extrait, délègue, nettoie. Aucun git, aucun dépôt
# laissé derrière, aucun temporaire qui survit -- y compris sur un refus.
nivuus_bootstrap() {
    _version="$(nivuus_resolve_version)" || nivuus_die "Impossible de déterminer la version à installer."
    [ -n "$_version" ] || nivuus_die "Impossible de déterminer la version à installer."
    _archive="nivuus-shell-v${_version}.tar.gz"
    _base="$NIVUUS_RELEASE_BASE_URL/v${_version}"

    NIVUUS_BOOT_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nivuus-boot.XXXXXX")" \
        || nivuus_die "Impossible de créer un répertoire temporaire."
    # Le nettoyage est posé AVANT le premier téléchargement : un refus, un
    # Ctrl-C ou une coupure réseau ne doivent pas laisser 50 Mo derrière.
    trap 'rm -rf "$NIVUUS_BOOT_TMP"' EXIT
    trap 'rm -rf "$NIVUUS_BOOT_TMP"; exit 130' INT
    trap 'rm -rf "$NIVUUS_BOOT_TMP"; exit 143' TERM HUP

    printf '%s\n' "Téléchargement de Nivuus Shell v${_version}…"
    nivuus_fetch "$_base/$_archive" "$NIVUUS_BOOT_TMP/$_archive" \
        || nivuus_die "Téléchargement impossible : $_base/$_archive"
    nivuus_fetch "$_base/SHA256SUMS" "$NIVUUS_BOOT_TMP/SHA256SUMS" \
        || nivuus_die "Sommes de contrôle indisponibles pour la v${_version}. Installation refusée."

    # Vérification fail-closed : pas d'option pour la désactiver. Ce qui
    # n'est pas vérifiable n'est pas installé.
    _expected="$(awk -v a="$_archive" '$2 == a || $2 == "./" a { print $1; exit }' "$NIVUUS_BOOT_TMP/SHA256SUMS")"
    [ -n "$_expected" ] || nivuus_die "Aucune somme de contrôle pour $_archive. Installation refusée."
    _actual="$(nivuus_sha256 "$NIVUUS_BOOT_TMP/$_archive")" \
        || nivuus_die "Installation refusée : l'archive n'a pas pu être vérifiée."
    if [ "$_expected" != "$_actual" ]; then
        printf '%s\n' "Empreinte de l'archive incorrecte. Installation refusée." >&2
        printf '%s\n' "  attendue : $_expected" >&2
        printf '%s\n' "  obtenue  : $_actual" >&2
        exit 1
    fi
    printf '%s\n' "Empreinte vérifiée."

    mkdir -p "$NIVUUS_BOOT_TMP/src"
    tar -xzf "$NIVUUS_BOOT_TMP/$_archive" -C "$NIVUUS_BOOT_TMP/src" \
        || nivuus_die "Archive illisible. Installation refusée."

    # Les archives de release n'ont pas de répertoire racine ; celles que
    # GitHub génère automatiquement en ont un. On accepte les deux formes,
    # sans deviner : on cherche le noyau.
    _src="$NIVUUS_BOOT_TMP/src"
    if [ ! -f "$_src/bin/nivuus" ]; then
        _inner="$(find "$NIVUUS_BOOT_TMP/src" -mindepth 1 -maxdepth 1 -type d | head -n1)"
        if [ -n "$_inner" ] && [ -f "$_inner/bin/nivuus" ]; then
            _src="$_inner"
        fi
    fi
    if [ ! -f "$_src/bin/nivuus" ]; then
        printf '%s\n' "La release v${_version} ne contient pas bin/nivuus : elle est antérieure au nouvel installeur." >&2
        printf '%s\n' "Installe une version plus récente (n'épingle pas NIVUUS_VERSION), ou consulte doc/INSTALL.md." >&2
        exit 1
    fi
    chmod +x "$_src/bin/"* 2>/dev/null || :

    # bin/nivuus est en bash (décision du spec) ; l'amorçage, lui, est POSIX.
    # Si bash manque, on donne la commande exacte -- calculée par lib/deps.sh
    # de l'archive, qui est exécutable sous ash depuis la phase 3 -- et on ne
    # l'exécute jamais.
    if ! command -v bash >/dev/null 2>&1; then
        printf '%s\n' "bash est requis pour l'installeur Nivuus et n'est pas présent." >&2
        if [ -f "$_src/lib/log.sh" ] && [ -f "$_src/lib/deps.sh" ]; then
            # shellcheck source=/dev/null
            . "$_src/lib/log.sh"; . "$_src/lib/deps.sh"
            printf '%s\n' "Installe-le puis relance :" >&2
            printf '  %s\n' "$(nivuus_pkg_install_cmd bash)" >&2
        fi
        exit 1
    fi

    # « exec » est interdit ici : il annulerait le trap et laisserait le
    # temporaire derrière. On appelle, on garde le code de retour, on laisse
    # le trap faire son travail.
    #
    # Sous « curl … | sh », l'entrée standard est le script lui-même :
    # l'installeur ne doit surtout pas y lire. S'il existe un terminal, on
    # lui donne ; sinon on répond oui d'avance, explicitement.
    # Le test d'ouverture se fait dans un SOUS-SHELL : une erreur de
    # redirection sur un utilitaire spécial fait sortir le shell entier
    # (POSIX), ce qui tuerait l'amorçage au lieu de le faire basculer.
    if [ -t 0 ]; then
        if "$_src/bin/nivuus" install "$@"; then _rc=0; else _rc=$?; fi
    elif ( : < /dev/tty ) 2>/dev/null; then
        if "$_src/bin/nivuus" install "$@" < /dev/tty; then _rc=0; else _rc=$?; fi
    else
        if "$_src/bin/nivuus" install --yes "$@"; then _rc=0; else _rc=$?; fi
    fi
    if [ -n "$RUN_DOCTOR" ] && [ "$_rc" -eq 0 ]; then
        "$_src/bin/nivuus" doctor || :
    fi
    return "$_rc"
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
