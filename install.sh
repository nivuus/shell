#!/usr/bin/env bash
# install.sh — wrapper rétrocompatible autour de « nivuus install ».
# La logique vit dans bin/nivuus et lib/. Ce fichier ne fait que traduire
# les anciennes options.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGS=()
RUN_DOCTOR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --system)
            printf '%s\n' "L'installation système (--system) n'est pas encore disponible dans cette version." >&2
            printf '%s\n' "Utilise l'installation utilisateur (sans --system) en attendant." >&2
            exit 1
            ;;
        --non-interactive) ARGS+=(--yes) ;;
        --health-check)    RUN_DOCTOR=1 ;;
        --no-backup)       : ;;   # accepté, sans effet : le manifeste sauvegarde toujours
        --dry-run)          ARGS+=(--dry-run) ;;
        --minimal)           ARGS+=(--minimal) ;;
        --with-deps)       ARGS+=(--with-deps) ;;
        --no-minimal)      ARGS+=(--no-minimal) ;;
        --prefix)
            shift
            [ $# -gt 0 ] || { printf "L'option --prefix attend un chemin.\n" >&2; exit 2; }
            ARGS+=(--prefix "$1") ;;
        --help|-h)          exec "$ROOT/bin/nivuus" help ;;
        *) printf 'Option inconnue : %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

# Les tableaux vides ne peuvent pas être développés avec "${ARGS[@]}" sous
# `set -u` avant bash 4.4 (« unbound variable »). On teste donc le nombre
# d'éléments — cette expansion-là est sûre sur toutes les versions — avant
# de développer le tableau.
if [ "${#ARGS[@]}" -gt 0 ]; then
    "$ROOT/bin/nivuus" install "${ARGS[@]}"
else
    "$ROOT/bin/nivuus" install
fi

if [ -n "$RUN_DOCTOR" ]; then
    "$ROOT/bin/nivuus" doctor
fi
