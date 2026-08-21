#!/usr/bin/env bats
#
# Une preuve qui ne tourne nulle part est une preuve qui n'existe pas. Ces
# tests vérifient que le script de preuve système est réellement câblé, et
# que les invariants ne peuvent pas disparaître discrètement.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    MATRIX="$ROOT/.github/matrix.json"
    WF="$ROOT/.github/workflows"
}

@test "les cinq cibles système sont marquées dans matrix.json" {
    command -v jq >/dev/null 2>&1 || skip "jq indisponible"
    n="$(jq '[.containers[] | select(.system == true)] | length' "$MATRIX")"
    [ "$n" -eq 5 ]
    for id in debian-12 ubuntu-2404 fedora-41 alpine-320 arch; do
        jq -e --arg i "$id" '.containers[] | select(.id == $i and .system == true)' "$MATRIX" >/dev/null
    done
}

@test "la matrice nightly exécute run-system-target.sh" {
    grep -q "run-system-target.sh" "$WF/matrix.yml"
}

@test "le job système filtre sur la clé system, il ne rejoue pas toute la matrice" {
    grep -q "select(.system" "$WF/matrix.yml"
}

@test "la couche PR exécute les suites système SANS conteneur" {
    grep -q "test_lib_system.bats" "$WF/tests.yml"
    grep -q "test_system_privileges.bats" "$WF/tests.yml"
    grep -q "test_zshrc_reentrancy.bats" "$WF/tests.yml"
    # Aucun useradd ni docker dans le job de PR : la couche PR reste
    # entièrement non privilégiée.
    run grep -nE 'useradd|docker run' "$WF/tests.yml"
    [ "$status" -ne 0 ]
}

@test "tests.yml vérifie mécaniquement la présence des invariants système" {
    grep -q "INVARIANT n° 1" "$WF/tests.yml"
    grep -q "INVARIANT n° 2" "$WF/tests.yml"
    grep -q "INVARIANT n° 4" "$WF/tests.yml"
    grep -q "INVARIANT: la garde n'est PAS exportée" "$WF/tests.yml"
}

@test "le garde-fou de la signature n'a pas été remplacé, seulement étendu" {
    grep -q "a forged archive with SHA256SUMS re-signed by an attacker key is REFUSED" "$WF/tests.yml"
}

@test "le script système n'est exécuté que dans un conteneur, jamais sur un runner nu" {
    # Il écrit dans /etc et /usr/local : un runner n'est pas jetable.
    grep -q "container:" "$WF/matrix.yml"
    # Le script n'est EXÉCUTÉ qu'une fois, dans le job « system », qui
    # déclare une image de conteneur. (On compte les lignes qui le lancent,
    # pas celles qui le nomment : un commentaire n'exécute rien.)
    n="$(grep -c 'run: \./tests/ci/run-system-target\.sh' "$WF/matrix.yml")"
    [ "$n" -eq 1 ]
}

@test "aucun workflow n'installe de paquet hors du BOOTSTRAP documenté" {
    # La règle du dépôt : tout passe par tests/ci/install-deps.sh et
    # l'action composite setup-tests. Le job système ne fait pas exception.
    run bash -c "grep -nE '(apt-get|apk add|dnf|pacman) ' '$WF/matrix.yml' | grep -v BOOTSTRAP"
    [ "$status" -ne 0 ]
}
