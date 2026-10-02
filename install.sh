#!/usr/bin/env bash
# install.sh — wrapper rétrocompatible autour de « nivuus install ».
# La logique vit dans bin/nivuus et lib/. Ce fichier ne fait que traduire
# les anciennes options.
#
# Without a mode flag, "nivuus install" equips the whole machine (--system:
# dependencies, tools, global zshrc, every account's login shell) as soon as
# root or sudo is available, and falls back to --user otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGS=()
RUN_DOCTOR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --system)          ARGS+=(--system) ;;
        --user)            ARGS+=(--user) ;;
        --no-chsh)         ARGS+=(--no-chsh) ;;
        --non-interactive) ARGS+=(--yes) ;;
        --health-check)    RUN_DOCTOR=1 ;;
        --no-backup)       : ;;   # accepté, sans effet : le manifeste sauvegarde toujours
        --dry-run)          ARGS+=(--dry-run) ;;
        --minimal)           ARGS+=(--minimal) ;;
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
