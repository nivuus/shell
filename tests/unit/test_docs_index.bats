#!/usr/bin/env bats
#
# Un index qui oublie la moitié des pages est pire qu'aucun index : il fait
# croire que ce qui n'y est pas n'existe pas. doc/README.md liste aujourd'hui
# 6 fichiers sur 10, et oublie exactement ceux des trois derniers chantiers.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    DOC="$ROOT/doc"
    INDEX="$DOC/README.md"
    README="$ROOT/README.md"
}

@test "doc/TESTING.md décrit les quatre niveaux de test" {
    for niveau in unit integration e2e performance; do
        grep -qF "tests/$niveau" "$DOC/TESTING.md" \
            || { echo "niveau non documenté : $niveau"; false; }
    done
}

@test "doc/TESTING.md ne recopie aucun compte de tests" {
    # Un chiffre recopié périme au commit suivant. Le compte fait autorité
    # dans tests/baseline-counts.tsv, et bin/test-count l'imprime.
    run grep -nE '\b[0-9]{3,4} (tests|tests unitaires)\b' "$DOC/TESTING.md"
    [ "$status" -ne 0 ] || { echo "compte recopié : $output"; false; }
    grep -qF 'bin/test-count' "$DOC/TESTING.md"
}

@test "doc/TESTING.md dit comment la CI lance les suites" {
    grep -qF 'tests/ci/bats-run.sh' "$DOC/TESTING.md"
    # Les exclusions par défaut sont la chose qu'on découvre le plus tard,
    # et toujours en se demandant pourquoi un test « ne tourne pas ».
    grep -qE 'docker|network' "$DOC/TESTING.md"
}
