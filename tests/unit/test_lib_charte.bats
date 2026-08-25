#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    unset NO_COLOR COLORTERM COLORFGBG NIVUUS_CHARTE_MODE
}

# Le fichier est sourcé dans un sous-shell dont la sortie est capturée par
# bats, donc jamais un TTY. Les cas qui veulent des couleurs forcent la
# détection avec NIVUUS_CHARTE_TTY=1, prévue pour les tests.

@test "NO_COLOR vide les sept variables" {
    run bash -c "export NO_COLOR=1 NIVUUS_CHARTE_TTY=1; . '$LIB/charte.sh'
        printf '[%s|%s|%s|%s|%s|%s|%s]' \
            \"\$NIVUUS_C_DANGER\" \"\$NIVUUS_C_WARN\" \"\$NIVUUS_C_OK\" \
            \"\$NIVUUS_C_BUSY\" \"\$NIVUUS_C_TEXT\" \"\$NIVUUS_C_STRONG\" \
            \"\$NIVUUS_C_OFF\""
    [ "$output" = "[||||||]" ]
}

@test "sortie non-TTY vide les sept variables" {
    run bash -c ". '$LIB/charte.sh'
        printf '[%s|%s|%s|%s]' \"\$NIVUUS_C_DANGER\" \"\$NIVUUS_C_WARN\" \
            \"\$NIVUUS_C_OK\" \"\$NIVUUS_C_BUSY\""
    [ "$output" = "[|||]" ]
}

@test "COLORTERM=truecolor emet du 38;2" {
    run bash -c "export COLORTERM=truecolor NIVUUS_CHARTE_TTY=1; . '$LIB/charte.sh'
        printf '%s' \"\$NIVUUS_C_OK\""
    [[ "$output" == *"38;2;"* ]]
}

@test "sans COLORTERM le repli est du 38;5" {
    run bash -c "export NIVUUS_CHARTE_TTY=1; . '$LIB/charte.sh'
        printf '%s' \"\$NIVUUS_C_OK\""
    [[ "$output" == *"38;5;"* ]]
    [[ "$output" != *"38;2;"* ]]
}

@test "mode sombre par defaut, valeurs de charte" {
    run bash -c "export COLORTERM=truecolor NIVUUS_CHARTE_TTY=1; . '$LIB/charte.sh'
        printf '%s' \"\$NIVUUS_C_DANGER\""
    [[ "$output" == *"255;122;133"* ]]
}

@test "NIVUUS_CHARTE_MODE=light bascule sur la paire claire" {
    run bash -c "export COLORTERM=truecolor NIVUUS_CHARTE_MODE=light NIVUUS_CHARTE_TTY=1
        . '$LIB/charte.sh'; printf '%s' \"\$NIVUUS_C_DANGER\""
    [[ "$output" == *"193;31;46"* ]]
}

@test "COLORFGBG a fond clair bascule sur la paire claire" {
    run bash -c "export COLORTERM=truecolor COLORFGBG='0;15' NIVUUS_CHARTE_TTY=1
        . '$LIB/charte.sh'; printf '%s' \"\$NIVUUS_C_OK\""
    [[ "$output" == *"27;107;74"* ]]
}

@test "COLORFGBG a fond sombre reste sur la paire sombre" {
    run bash -c "export COLORTERM=truecolor COLORFGBG='15;0' NIVUUS_CHARTE_TTY=1
        . '$LIB/charte.sh'; printf '%s' \"\$NIVUUS_C_OK\""
    [[ "$output" == *"78;211;154"* ]]
}

@test "NIVUUS_CHARTE_MODE prime sur COLORFGBG" {
    run bash -c "export COLORTERM=truecolor COLORFGBG='15;0' NIVUUS_CHARTE_MODE=light
        export NIVUUS_CHARTE_TTY=1; . '$LIB/charte.sh'; printf '%s' \"\$NIVUUS_C_OK\""
    [[ "$output" == *"27;107;74"* ]]
}

@test "NIVUUS_C_TEXT est toujours vide, meme en couleur" {
    run bash -c "export COLORTERM=truecolor NIVUUS_CHARTE_TTY=1; . '$LIB/charte.sh'
        printf '[%s]' \"\$NIVUUS_C_TEXT\""
    [ "$output" = "[]" ]
}

@test "NIVUUS_C_STRONG est le gras seul, sans couleur" {
    run bash -c "export COLORTERM=truecolor NIVUUS_CHARTE_TTY=1; . '$LIB/charte.sh'
        printf '%s' \"\$NIVUUS_C_STRONG\" | cat -v"
    [ "$output" = '^[[1m' ]
}

@test "aucun gris n'est emis" {
    run bash -c "export NIVUUS_CHARTE_TTY=1; . '$LIB/charte.sh'
        printf '%s%s%s%s%s' \"\$NIVUUS_C_DANGER\" \"\$NIVUUS_C_WARN\" \
            \"\$NIVUUS_C_OK\" \"\$NIVUUS_C_BUSY\" \"\$NIVUUS_C_STRONG\""
    [[ "$output" != *"[2m"* ]]
    for grey in 232 240 244 246 250 255; do
        [[ "$output" != *"38;5;$grey"* ]]
    done
}

@test "NIVUUS_CHARTE_LOADED est pose" {
    run bash -c ". '$LIB/charte.sh'; printf '%s' \"\$NIVUUS_CHARTE_LOADED\""
    [ "$output" = "1" ]
}

@test "le fichier est sourcable par zsh" {
    run zsh -c "export COLORTERM=truecolor NIVUUS_CHARTE_TTY=1; . '$LIB/charte.sh'
        printf '%s' \"\$NIVUUS_C_OK\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"78;211;154"* ]]
}

@test "le fichier ne definit aucune fonction" {
    run bash -c "before=\$(declare -F | wc -l); . '$LIB/charte.sh'
        after=\$(declare -F | wc -l); [ \"\$before\" = \"\$after\" ]"
    [ "$status" -eq 0 ]
}

@test "charte.sh est sourcable sous set -u sans COLORFGBG" {
    run bash -c "unset COLORFGBG; set -euo pipefail; . '$LIB/charte.sh'"
    [ "$status" -eq 0 ]
}
