#!/bin/sh
# =============================================================================
# L'image sociale, dérivée d'une FRAME de la démo. Manuel, comme la démo.
# =============================================================================
# Pourquoi dérivée et non dessinée : une image dessinée peut montrer ce que le
# produit ne fait pas. Une frame du .cast ne le peut pas.
#
# La frame retenue est celle du dernier plan -- l'empreinte de $HOME identique
# après désinstallation. C'est l'argument ; c'est donc lui qu'on met sur la
# carte que voient tous ceux qui ne cliquent pas.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CAST="$ROOT/docs/assets/demo.cast"
AT="${NIVUUS_SOCIAL_AT:-34}"     # secondes ; le dernier plan
OUT="$ROOT/docs/assets/social.png"

[ -f "$CAST" ] || { echo "demo.cast absent : lance tools/demo/record.sh" >&2; exit 1; }

tmp="$(mktemp -d)"
npx --yes svg-term-cli --in "$CAST" --out "$tmp/frame.svg" \
    --window --width 100 --height 20 --at "$((AT * 1000))"

# 1280x640 : le format que GitHub attend pour une social preview.
if command -v resvg >/dev/null 2>&1; then
    resvg --width 1280 --height 640 "$tmp/frame.svg" "$OUT"
elif command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w 1280 -h 640 -o "$OUT" "$tmp/frame.svg"
else
    echo "resvg ou rsvg-convert requis pour produire le PNG" >&2; exit 1
fi
rm -rf "$tmp"

ls -l "$OUT"
cat <<'EOF'

Televersement MANUEL, une seule fois : Settings > General > Social preview.
L'image sociale n'est exposee par aucune API GitHub -- c'est la seule action
de ce chantier qui n'est ni versionnee ni testable. Le fichier, lui, est
versionne : si GitHub la perd, on la reteleverse sans la refabriquer.
EOF
