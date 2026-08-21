#!/bin/sh
# =============================================================================
# Pousse la description et les topics du dépôt depuis package.json.
# =============================================================================
# Aucune valeur ne doit exister uniquement dans l'UI web de GitHub : elle n'y
# est ni relisible en revue, ni testable, ni restaurable. package.json fait
# autorité ; ce script n'est qu'un transport.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/package.json"

command -v gh >/dev/null 2>&1 || {
    echo "gh (GitHub CLI) requis : https://cli.github.com" >&2; exit 1; }

description="$(sed -n 's/.*"description": "\(.*\)",*$/\1/p' "$PKG" | head -n1)"
[ -n "$description" ] || { echo "description absente de package.json" >&2; exit 1; }

# Les topics GitHub sont en minuscules, sans espace : les keywords de
# package.json respectent déjà cette forme.
topics="$(sed -n '/"keywords"/,/]/p' "$PKG" \
          | grep -oE '"[a-z0-9-]+"' | tr -d '"' | grep -v keywords)"

set -- --description "$description"
for t in $topics; do set -- "$@" --add-topic "$t"; done

echo "Description : $description"
echo "Topics      : $(printf '%s ' $topics)"
gh repo edit "$@"

cat <<'EOF'

Ce que gh ne peut pas faire, et qu'il faut donc faire a la main, une fois :

  L'IMAGE SOCIALE (social preview) n'est exposee par aucune API. Va dans
  Settings > General > Social preview et televerse docs/assets/social.png
  (produit par tools/demo/social.sh). C'est la seule action de ce chantier
  qui n'est ni versionnee ni testable -- elle est ecrite ici pour qu'elle ne
  soit pas oubliee.
EOF
