#!/bin/sh
# =============================================================================
# GARDE 2 — le scénario de la démo est rejoué pour de vrai, sans enregistrer.
# =============================================================================
# Ce que les trois autres gardes ne peuvent pas faire : vérifier que le FLUX
# marche encore, pas seulement que les commandes existent. C'est le garde qui
# compte -- il rend impossible de montrer un flux qui ne marche plus.
#
# Rejouable en local, à l'identique, par un simple `tools/demo/replay-check.sh`.
# Toute la logique de preuve est ici, rien dans le YAML : même modèle que
# tests/ci/run-target.sh.
#
# DEUX SUBSTITUTIONS ASSUMÉES, et leurs raisons :
#
#  1. Le `curl … | sh` du scénario est rejoué depuis l'ARBRE MONTÉ, pas depuis
#     GitHub. Rejouer le vrai one-liner installerait la DERNIÈRE RELEASE : le
#     garde deviendrait aveugle à la branche qu'il est censé garder, et
#     dépendrait d'un service tiers. Ce qui est vérifié reste le même flux,
#     sur le code présent.
#  2. Le shell du rejeu tourne avec TERM=dumb. Ce n'est PAS du confort : avec
#     un TERM qui supporte les titres, `config/20-terminal-title.zsh` accroche
#     un hook `chpwd` qui écrit une séquence OSC sur la sortie standard. Or
#     `_ai_gemini_cli_call` capture `$(cd "$workspace" && agy ...)` : la
#     séquence se retrouve DANS la réponse, `jq` échoue, et l'appel IA est
#     rapporté en erreur. C'est un défaut du produit, pas de la démo -- ce
#     garde l'a trouvé le jour de sa naissance. Il est consigné dans
#     tools/demo/README.md ; le corriger appartient à config/, hors du
#     périmètre de ce chantier. Conséquence assumée : ce garde ne verra pas
#     une régression de CE défaut-là.
#  3. `exec zsh` n'est pas rejoué tel quel : en non-interactif il remplacerait
#     le shell, lirait une entrée vide et sortirait en 0 -- le rejeu passerait
#     au vert sans avoir exécuté une seule ligne suivante. La suite est donc
#     exécutée dans un zsh neuf qui source le ~/.zshrc écrit par
#     l'installation. C'est ce que « exec zsh » veut dire à l'écran.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCENARIO="${NIVUUS_DEMO_SCENARIO:-$ROOT/tools/demo/scenario.txt}"
IMAGE="${NIVUUS_DEMO_IMAGE:-nivuus-demo:local}"
TAB="$(printf '\t')"

echo "== Construction du conteneur de tournage =="
docker build -q -t "$IMAGE" -f "$ROOT/tools/demo/Dockerfile" "$ROOT/tools/demo"

work="$(mktemp -d)"
part1="$work/part1.sh"
part2="$work/part2.zsh"
: > "$part1"
: > "$part2"

# Avant « exec zsh » on est dans un sh ; après, dans un shell Nivuus.
target="$part1"
grep -vE '^[[:space:]]*(#|$)' "$SCENARIO" | while IFS="$TAB" read -r _ genre cmd; do
    case "$genre" in
        type) continue ;;
        unknown)
            first="$(printf '%s' "$cmd" | awk '{print $1}')"
            printf 'command -v %s >/dev/null 2>&1 && { echo "la demo pretend que %s est introuvable, or elle existe" >&2; exit 1; }\n' \
                   "$first" "$first" >> "$target"
            continue ;;
    esac
    case "$cmd" in
        "exec zsh")
            echo "__SWITCH__" >> "$part1"
            target="$part2"
            continue ;;
        *raw.githubusercontent.com*install.sh*)
            printf 'sh /opt/nivuus-src/install.sh --non-interactive\n' >> "$target"
            continue ;;
    esac
    printf '%s\n' "$cmd" >> "$target"
done

# Le pipeline ci-dessus tourne dans un sous-shell : on relit les fichiers.
sed -i '/^__SWITCH__$/d' "$part1"

runner="$work/run.sh"
cat > "$runner" <<'RUNEOF'
#!/bin/sh
set -eu
sh -e /demo-replay/part1.sh
exec env TERM=dumb zsh -e -c '. "$HOME/.zshrc"; . /demo-replay/part2.zsh'
RUNEOF
chmod +x "$runner"

echo "== Rejeu non interactif du scénario =="
out="$(mktemp)"
set +e
docker run --rm --hostname demo \
    -v "$ROOT:/opt/nivuus-src:ro" \
    -v "$work:/demo-replay:ro" \
    "$IMAGE" sh /demo-replay/run.sh > "$out" 2>&1
rc=$?
set -e
cat "$out"

if [ "$rc" -ne 0 ]; then
    echo "REJEU EN ECHEC (code $rc) : la demo montre un flux qui ne marche plus." >&2
    rm -rf "$work"
    exit "$rc"
fi

# Un code 0 ne suffit pas : une commande peut réussir en imprimant son échec.
# Le « command not found » du plan t=13-19s est ATTENDU, une fois.
if [ "$(grep -ci 'command not found' "$out" || true)" -gt 1 ] \
   || grep -qiE 'no such file|permission denied|traceback' "$out"; then
    echo "motif d'echec dans la sortie du rejeu." >&2
    rm -rf "$work"
    exit 1
fi

rm -f "$out"
rm -rf "$work"
echo "== Rejeu conforme =="
