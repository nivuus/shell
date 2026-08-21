#!/usr/bin/env bats
# Un paquet ne livre AUCUN .zwc et n'en compile aucun (spec § 3.2). Le budget
# de 300 ms doit donc tenir sans bytecode -- sinon le repli « cache par
# utilisateur » devient obligatoire. Ce test est le garde-fou de cette
# décision : il échoue le jour où le mode paquet passe au-dessus du budget.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TMP="$(mktemp -d)"
    command -v zsh >/dev/null || skip "zsh absent"
    rm -f "$ROOT"/config/*.zwc "$ROOT"/.zshrc.zwc
}

teardown() { rm -rf "$TMP"; rm -f "$ROOT"/config/*.zwc; }

# Moyenne de 5 démarrages complets, en millisecondes (entier).
startup_ms_no_zwc() {
    zsh -c "
        zmodload zsh/datetime
        export NIVUUS_SHELL_DIR='$ROOT'
        export NIVUUS_NO_COMPILE=1
        typeset total=0 i start end
        for i in {1..5}; do
            start=\$EPOCHREALTIME
            source '$ROOT/.zshrc' >/dev/null 2>&1
            end=\$EPOCHREALTIME
            total=\$(( total + (end - start) * 1000 ))
        done
        printf '%d' \$(( total / 5 ))
    "
}

@test "CRITICAL: startup stays under 300ms with no bytecode at all" {
    [ -z "${CI:-}" ] || skip "mesure de temps non fiable sur runner partagé (voir bin/benchmark en local)"
    local ms
    ms="$(startup_ms_no_zwc)"
    echo "startup sans .zwc : ${ms}ms (budget : 300ms)"
    [ "$ms" -lt 300 ]
}

@test "the measured figure is recorded in doc/PACKAGING.md" {
    # La spec fait de la mesure un LIVRABLE, pas un exercice : le chiffre
    # doit être publié, daté et attribué à une plateforme.
    grep -q 'sans bytecode' "$ROOT/doc/PACKAGING.md"
    grep -qE '[0-9]+ *ms' "$ROOT/doc/PACKAGING.md"
}

@test "no .zwc is committed to the repository" {
    run git -C "$ROOT" ls-files '*.zwc'
    [ -z "$output" ]
}
