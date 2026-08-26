#!/usr/bin/env bats

# bats-core ne fournit pas fail() : on la definit.
fail() { printf '%s\n' "$1" >&2; return 1; }

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    # Le périmètre de la charte, et lui seul (spec § 2.1). Le prompt, les
    # thèmes et la colorisation des outils tiers sont explicitement dehors :
    # ne jamais ajouter un fichier ici sans modifier la spec d'abord.
    SCOPE=(
        lib/charte.sh
        lib/log.sh
        lib/steps.sh
        lib/manifest.sh
        lib/zshrc.sh
        bin/nivuus
        bin/healthcheck
        bin/benchmark
        bin/test
        config/09-ai-core.zsh
        config/22-ai-errors.zsh
        config/24-ai-command-not-found.zsh
    )
}

@test "aucun dim (SGR 2) dans le perimetre" {
    cd "$ROOT"
    # Couvre \033, \e, \33, \x1b/\x1B et %F{8} (prompt zsh). Le "2" doit
    # etre immediatement avant le "m" pour ne pas prendre 38;5;22m pour un
    # dim (bug de la premiere version de ce test).
    run grep -nE '(\\033|\\e|\\33|\\x1b|\\x1B)\[([0-9;]*;)?2m|%F\{8\}' "${SCOPE[@]}"
    [ "$status" -ne 0 ] || fail "dim ou %F{8} trouve : $output"
}

@test "aucun code ANSI-256 achromatique dans le perimetre" {
    cd "$ROOT"
    # 232 a 255 (rampe de gris xterm-256) et l'indice 8 (bright-black),
    # en avant-plan (38;5;) comme en fond (48;5;), plus les formes prompt
    # zsh %F{...} et %K{...}. La borne ([^0-9]|$) evite qu'un indice legitime
    # comme 25 (dans 38;5;25m) ne soit pris pour le debut de 25x.
    run grep -nE '(38|48);5;(8|23[2-9]|24[0-9]|25[0-5])([^0-9]|$)|%[FK]\{(8|23[2-9]|24[0-9]|25[0-5])\}' "${SCOPE[@]}"
    [ "$status" -ne 0 ] || fail "gris ANSI-256 trouve : $output"
}

@test "aucun SGR bright-black (90/100) dans le perimetre" {
    cd "$ROOT"
    # 90 = avant-plan bright-black, 100 = fond bright-black : l'autre
    # facon standard d'ecrire un gris en SGR, hors du champ des codes 256.
    run grep -nE '\[(0;|1;)?(90|100)m' "${SCOPE[@]}"
    [ "$status" -ne 0 ] || fail "SGR bright-black trouve : $output"
}

@test "aucun gris via terminfo (tput dim / tput setaf 0|8) dans le perimetre" {
    cd "$ROOT"
    # Mecanisme distinct des codes ANSI bruts : invisible a toute regex sur
    # \033/\e/38;5;... Les fichiers bash purs du perimetre (bin/nivuus,
    # bin/healthcheck, bin/benchmark) sont precisement ceux qui emploieraient
    # cette forme.
    run grep -nE 'tput +(dim|setaf +(0|8))' "${SCOPE[@]}"
    [ "$status" -ne 0 ] || fail "gris via tput trouve : $output"
}

@test "aucune palette de theme en dur dans le perimetre" {
    cd "$ROOT"
    # Ancre en debut de ligne (espaces/tabulations tolerees devant),
    # guillemet simple ou double optionnel, \033 / \e / \x1b.
    run grep -nE '^[[:space:]]*(RED|GREEN|YELLOW|BLUE|NC)=["'"'"']?\\(033|e|x1b)' "${SCOPE[@]}"
    [ "$status" -ne 0 ] || fail "palette ANSI redeclaree : $output"
}

@test "tous les fichiers du perimetre existent" {
    cd "$ROOT"
    for f in "${SCOPE[@]}"; do
        [ -f "$f" ] || fail "fichier du perimetre absent : $f"
    done
}
