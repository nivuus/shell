#!/bin/sh
# =============================================================================
# demo.cast -> l'artefact affiché, + le tampon de fraîcheur (garde 3).
# =============================================================================
# Le format est une VARIABLE, pas une réécriture : si l'animation SVG ne joue
# pas dans le README rendu par GitHub, NIVUUS_DEMO_FORMAT=gif suffit. Le .cast
# reste la source ; seul ce script change de sortie.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ASSETS="$ROOT/docs/assets"
CAST="$ASSETS/demo.cast"
FORMAT="${NIVUUS_DEMO_FORMAT:-svg}"

[ -f "$CAST" ] || { echo "demo.cast absent : lance d'abord tools/demo/record.sh" >&2; exit 1; }

sha() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

case "$FORMAT" in
    svg)
        ARTEFACT="$ASSETS/demo.svg"
        npx --yes svg-term-cli --in "$CAST" --out "$ARTEFACT" \
            --window --width 100 --height 28
        ;;
    gif)
        # Repli défini d'avance (spec § 3.1) : budget relevé à 2 Mo.
        ARTEFACT="$ASSETS/demo.gif"
        agg --cols 100 --rows 28 "$CAST" "$ARTEFACT"
        ;;
    *) echo "format inconnu: $FORMAT (svg|gif)" >&2; exit 2 ;;
esac

cat > "$ASSETS/demo.stamp" <<EOF
# Tampon de fraîcheur de la démo — GARDE 3.
# Recalculé et comparé par tests/e2e/test_demo_scenario.bats sur chaque PR.
# Modifier scenario.txt sans relancer record.sh puis render.sh fait rougir la CI.
scenario_sha256=$(sha "$ROOT/tools/demo/scenario.txt")
cast_sha256=$(sha "$CAST")
artefact=docs/assets/$(basename "$ARTEFACT")
artefact_sha256=$(sha "$ARTEFACT")
version=$(cat "$ROOT/.version")
format=$FORMAT
EOF

ls -l "$ARTEFACT"
echo "Tampon écrit : $ASSETS/demo.stamp"
