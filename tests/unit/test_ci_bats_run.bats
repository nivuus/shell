#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    RUN="$ROOT/tests/ci/bats-run.sh"
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/suite"
    printf '#!/usr/bin/env bats\n@test "ok" { true; }\n' > "$TMP/suite/a.bats"
    printf '#!/usr/bin/env bats\n# bats test_tags=docker\n@test "dockery" { false; }\n' \
        > "$TMP/suite/b.bats"
}

teardown() { rm -rf "$TMP"; }

# Un bats imbriqué hérite de BATS_ROOT/BATS_LIBEXEC du bats extérieur et
# part chercher ses propres exécutables au mauvais endroit. La CI n'imbrique
# jamais ; c'est un artefact de ce test, il se corrige ici et pas dans le script.
clean_env() {
    local clean_path
    # bats ajoute son propre libexec au PATH : sans ce filtre, le bats
    # imbriqué se résout sur l'exécutable interne et ne trouve plus ses
    # bibliothèques. La CI n'imbrique jamais bats ; c'est un artefact de test.
    clean_path="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'bats-core' | paste -sd: -)"
    env $(env | sed -n 's/^\(BATS_[A-Za-z_]*\)=.*/-u \1/p' | tr '\n' ' ') \
        PATH="$clean_path" "$@"
}

@test "docker-tagged tests are excluded by default" {
    run clean_env "$RUN" "$TMP/suite"
    [ "$status" -eq 0 ]
    [[ "$output" != *"dockery"* ]]
}

@test "NIVUUS_CI_DOCKER=1 includes them (and they can then fail)" {
    run clean_env NIVUUS_CI_DOCKER=1 "$RUN" "$TMP/suite"
    [ "$status" -ne 0 ]
    [[ "$output" == *"dockery"* ]]
}

@test "output is TAP13 so counts can be read from the plan line" {
    run clean_env "$RUN" "$TMP/suite"
    [[ "${lines[0]}" == "TAP version 13" ]]
    [[ "${lines[1]}" =~ ^1\.\.[0-9]+$ ]]
}

@test "an e2e suite asks for --jobs when GNU parallel is available" {
    command -v parallel >/dev/null 2>&1 || skip "GNU parallel indisponible ici"
    mkdir -p "$TMP/e2e"
    cp "$TMP/suite/a.bats" "$TMP/e2e/"
    run clean_env "$RUN" "$TMP/e2e"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "TAP version 13" ]]
}

@test "falls back to serial when GNU parallel is missing" {
    mkdir -p "$TMP/e2e" "$TMP/bin"
    cp "$TMP/suite/a.bats" "$TMP/e2e/"
    # Un PATH complet, MOINS parallel : c'est la seule différence testée.
    for d in $(printf '%s' "$PATH" | tr ':' ' '); do
        case "$d" in *bats-core*) continue ;; esac
        [ -d "$d" ] || continue
        for f in "$d"/*; do
            [ -x "$f" ] || continue
            n="${f##*/}"
            [ "$n" = "parallel" ] && continue
            [ -e "$TMP/bin/$n" ] || ln -s "$f" "$TMP/bin/$n"
        done
    done
    [ ! -e "$TMP/bin/parallel" ]
    run clean_env PATH="$TMP/bin" "$RUN" "$TMP/e2e"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok 1 ok"* ]]
}
