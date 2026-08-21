#!/usr/bin/env bats
#
# Lint maison des workflows. Objet : empêcher la CI de redevenir artisanale.
# Ces règles sont des invariants du plan de phase 4, pas des préférences.
#
# Périmètre : les workflows qui exécutent la suite de tests Nivuus.
# Deux workflows en sont exclus, et la raison est de fond, pas de confort :
#   - verify-tools-probe.yml   : sa raison d'être est de MESURER une image nue
#                                puis d'observer ce que `zsh git curl` y amène.
#                                Passer par install-deps.sh détruirait la mesure.
#   - verify-latest-release.yml: canari qui vérifie une release publiée avec un
#                                zsh système ; il n'exécute aucun test bats.
# Ils appartiennent au chantier « signature des releases ».

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    WF="$ROOT/.github/workflows"
    # Workflows de test possédés par le plan de phase 4.
    TEST_WORKFLOWS="tests.yml matrix.yml uninstall-verified.yml"
}

test_workflow_files() {
    for f in $TEST_WORKFLOWS; do
        [ -f "$WF/$f" ] && printf '%s\n' "$WF/$f"
    done
}

@test "no workflow installs packages itself — everything goes through install-deps.sh" {
    # On tolère les lignes de commentaire et le bootstrap documenté d'un
    # conteneur sans git, marqué par le mot-clé BOOTSTRAP.
    offenders=""
    for f in $(test_workflow_files); do
        while IFS= read -r line; do
            case "$line" in
                *BOOTSTRAP*) continue ;;
                \#*) continue ;;
                *) : ;;
            esac
            trimmed="${line#"${line%%[! ]*}"}"
            case "$trimmed" in
                \#*) continue ;;
            esac
            case "$line" in
                *apt-get*install*|*"apk add"*|*"pacman -S"*|*dnf*install*|*"brew install"*)
                    offenders="$offenders$f: $line
" ;;
            esac
        done < "$f"
    done
    [ -z "$offenders" ] || { echo "$offenders"; false; }
}

@test "no workflow clones bats-core itself" {
    for f in $(test_workflow_files); do
        run grep -n "bats-core" "$f"
        [ "$status" -ne 0 ] || { echo "$f clone bats-core"; false; }
    done
}

@test "the composite action exists and calls install-deps.sh" {
    [ -f "$ROOT/.github/actions/setup-tests/action.yml" ]
    grep -q "tests/ci/install-deps.sh" "$ROOT/.github/actions/setup-tests/action.yml"
}

@test "every job that runs bats uses the composite action" {
    # Un job qui lance bats sans setup-tests utiliserait un bats non épinglé.
    missing=""
    for f in $(test_workflow_files); do
        grep -q "bats " "$f" || continue
        grep -q "./.github/actions/setup-tests" "$f" || missing="$missing $f"
    done
    [ -z "$missing" ] || { echo "sans setup-tests:$missing"; false; }
}

@test "the signature suites survived the refactor, on all three platforms" {
    # Garde-fou de non-régression du chantier « signature des releases » :
    # ces suites ont été ajoutées à tests.yml APRÈS la rédaction du plan de
    # phase 4. Les perdre dans un refactor de CI serait une régression muette.
    f="$WF/tests.yml"
    for suite in tests/unit/test_keys_repo.bats \
                 tests/unit/test_autoupdate_sha256.bats \
                 tests/unit/test_release_signature.bats \
                 tests/unit/test_autoupdate_download.bats \
                 tests/unit/test_autoupdate_hard_refusal.bats \
                 tests/unit/test_lib_keys.bats \
                 tests/unit/test_lib_steps_keys.bats \
                 tests/unit/test_lib_steps_verify_tools.bats \
                 tests/e2e/test_update_signature.bats \
                 tests/e2e/test_install_keys.bats \
                 tests/e2e/test_verify_key.bats; do
        grep -qF "$suite" "$f" || { echo "suite de signature perdue: $suite"; false; }
    done
    # Les deux invariants de sécurité, et le cas Alpine « aucun outil ».
    grep -qF "INVARIANT: a forged archive with SHA256SUMS re-signed by an attacker key is REFUSED" "$f"
    grep -qF "INVARIANT: no verification tool at all is REFUSED" "$f"
    grep -qF "install-verify-tools.sh" "$f"
}

@test "no workflow parses a bats plan line with sed" {
    # Le comptage historique relançait TOUTE la suite pour lire « 1..N ».
    # bin/test-count le fait avec `bats --count`, qui n'exécute rien.
    for f in $(test_workflow_files); do
        run grep -n "sed 's/1" "$f"
        [ "$status" -ne 0 ] || { echo "$f compte les tests avec sed"; false; }
    done
}

@test "the fragile absolute threshold is gone, replaced by a ratchet" {
    grep -q "bin/test-count --check" "$WF/tests.yml"
    run grep -n "Test count below minimum" "$WF/tests.yml"
    [ "$status" -ne 0 ]
}
