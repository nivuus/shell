#!/bin/sh
# =============================================================================
# GARDE 4 — péremption de la démo par version mineure.
# =============================================================================
# Usage : check-freshness.sh [patch|minor|major]
#
# Une démo enregistrée deux mineures plus tôt montre un produit que le lecteur
# ne recevra pas. Sur les patchs, la règle ne s'applique pas : le coût serait
# constant pour un bénéfice nul.
#
# À réévaluer après trois releases mineures (décision actée n° 4) : si
# réenregistrer devient pénible, c'est la règle qu'on discute, pas le commit
# qui bute dessus.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STAMP="${NIVUUS_DEMO_STAMP:-$ROOT/docs/assets/demo.stamp}"
BUMP="${1:-minor}"

case "$BUMP" in
    patch) echo "bump=patch : la demo n'est pas soumise a peremption."; exit 0 ;;
esac

if [ ! -f "$STAMP" ]; then
    cat >&2 <<EOF
Release refusee : aucune demo n'est enregistree ($STAMP absent).

Une version mineure sans demo est un choix ; il doit etre vu ici, pas decouvert
apres coup. Enregistre-la :

    tools/demo/record.sh
    tools/demo/render.sh

(Un patch n'est pas concerne par cette regle.)
EOF
    exit 1
fi

stamped="$(sed -n 's/^version=//p' "$STAMP" | head -n1)"
current="$(cat "$ROOT/.version")"
[ -n "$stamped" ] || { echo "le tampon ne porte pas de version" >&2; exit 1; }

minor_of() { printf '%s' "$1" | cut -d. -f1,2; }

if [ "$(minor_of "$stamped")" != "$(minor_of "$current")" ]; then
    cat >&2 <<EOF
Release refusee : la demo date de la version $stamped, le projet est en $current.

Une mineure ne sort pas avec une demo d'une generation precedente : elle
montrerait un produit que personne ne recevra. Reenregistre-la :

    tools/demo/record.sh
    tools/demo/render.sh

(Un patch n'est pas concerne par cette regle.)
EOF
    exit 1
fi

echo "demo a jour : $stamped ~ $current"
