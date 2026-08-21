#!/usr/bin/env bats
#
# Un badge décoratif est pire que pas de badge : il transforme une absence de
# preuve en apparence de preuve. Ces tests rendent cela impossible.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    README="$ROOT/README.md"
    WF="$ROOT/.github/workflows"
}

badge_workflows() {   # imprime le nom de fichier de chaque workflow référencé par un badge
    grep -o 'actions/workflows/[a-z0-9._-]*/badge.svg' "$README" \
        | sed 's|actions/workflows/||; s|/badge.svg||' | LC_ALL=C sort -u
}

@test "every workflow badge points at a workflow file that exists" {
    n=0
    for wf in $(badge_workflows); do
        [ -f "$WF/$wf" ] || { echo "badge orphelin: $wf"; false; }
        n=$((n + 1))
    done
    [ "$n" -ge 3 ]
}

@test "every workflow badge is pinned to master" {
    # Sans ?branch=master, le badge montre le dernier run toutes branches.
    while IFS= read -r line; do
        case "$line" in *badge.svg*) ;; *) continue ;; esac
        [[ "$line" == *"badge.svg?branch=master"* ]] || { echo "non épinglé: $line"; false; }
    done < "$README"
}

@test "every badge-backing workflow cannot freeze: it runs on master by itself" {
    # Ce qui rend un badge menteur, c'est de FIGER : `?branch=master` affiche
    # le dernier run sur master, et s'il n'y en a plus jamais, le badge garde
    # sa dernière couleur pour l'éternité. Deux façons acceptables d'empêcher
    # cela : tourner sur `push: master`, ou tourner la nuit (les runs
    # programmés s'exécutent sur la branche par défaut). La matrice complète
    # ne peut pas tourner sur push -- le budget CI du spec l'interdit -- donc
    # c'est le nightly qui la tient à jour, à moins de 24 h de retard.
    for wf in $(badge_workflows); do
        on_push=0; on_schedule=0
        grep -q "push:" "$WF/$wf" && grep -q "master" "$WF/$wf" && on_push=1
        grep -q "schedule:" "$WF/$wf" && on_schedule=1
        [ "$on_push" -eq 1 ] || [ "$on_schedule" -eq 1 ] \
            || { echo "$wf ne tourne ni sur push master ni la nuit : badge figé"; false; }
    done
}

@test "no badge-backing workflow can swallow a failure" {
    for wf in $(badge_workflows); do
        # Les commentaires ne comptent pas : ils EXPLIQUENT l'interdit.
        run grep -n "continue-on-error" "$(sed 's/[[:space:]]*#.*$//' "$WF/$wf" > "$BATS_TEST_TMPDIR/$wf.nc"; echo "$BATS_TEST_TMPDIR/$wf.nc")"
        [ "$status" -ne 0 ] || { echo "$wf: continue-on-error"; false; }
    done
}

@test "the uninstall badge is backed by the reversibility test" {
    grep -q "uninstall-verified.yml/badge.svg" "$README"
    grep -q "tests/e2e/test_reversibility.bats" "$WF/uninstall-verified.yml"
}

@test "the tested-platforms table matches .github/matrix.json exactly" {
    command -v jq >/dev/null 2>&1 || skip "jq indisponible"
    for label in $(jq -r '(.containers[], .runners[]) | .label | gsub(" "; "_")' "$ROOT/.github/matrix.json"); do
        want="$(printf '%s' "$label" | tr '_' ' ')"
        grep -qF "$want" "$README" || { echo "cible absente du README: $want"; false; }
    done
}

@test "the startup badge states the budget that is actually enforced" {
    budget="$(grep -o 'NIVUUS_STARTUP_BUDGET_MS:-[0-9]*' "$ROOT/tests/performance/test_startup.bats" \
              | head -1 | sed 's/.*-//')"
    [ -n "$budget" ]
    grep -q "startup-<${budget}ms" "$README" || {
        echo "le badge n'annonce pas le budget appliqué (${budget}ms)"; false; }
}

@test "no legacy badge syntax remains" {
    # `workflows/Tests/badge.svg` : ancienne forme, non épinglable à une branche.
    run grep -n "workflows/Tests/badge.svg" "$README"
    [ "$status" -ne 0 ]
}
