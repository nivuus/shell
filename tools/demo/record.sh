#!/bin/sh
# =============================================================================
# Enregistre la démo. À LA MAIN, jamais en CI (voir tools/demo/README.md).
# =============================================================================
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMAGE="${NIVUUS_DEMO_IMAGE:-nivuus-demo:local}"
OUT="$ROOT/docs/assets/demo.cast"

command -v docker >/dev/null 2>&1 || { echo "docker requis" >&2; exit 1; }

docker build -t "$IMAGE" -f "$ROOT/tools/demo/Dockerfile" "$ROOT/tools/demo"

# --tty : asciinema enregistre un vrai terminal, sinon le prompt ne s'affiche
# pas et l'enregistrement est un log, pas une démo. --interactive est ajouté
# quand l'appelant a bien une entrée de terminal ; en son absence (poste sans
# TTY, session automatisée) expect fournit déjà le pty dont la démo a besoin.
TTY_FLAGS="-t"
[ -t 0 ] && TTY_FLAGS="-it"

# shellcheck disable=SC2086
docker run --rm --hostname demo $TTY_FLAGS \
    -v "$ROOT:/opt/nivuus-src:ro" \
    -v "$ROOT/docs/assets:/out" \
    -v "$ROOT/tools/demo:/demo:ro" \
    "$IMAGE" sh -c '
        asciinema rec --cols 100 --rows 28 --idle-time-limit 2 --overwrite \
            --command "expect /demo/play.exp /demo/scenario.txt" \
            /out/demo.cast
    '

echo "Enregistré : $OUT"
echo
echo "RELIS-LE AVANT DE COMMITTER. Aucun test ne dira que la démo est devenue"
echo "laide, mal rythmée ou illisible : c'est le seul point que la CI ne couvre"
echo "pas, et c'est pour cela que cet enregistrement est manuel."
echo
echo "Puis : tools/demo/render.sh"
