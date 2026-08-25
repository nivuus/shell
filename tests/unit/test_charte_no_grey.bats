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
    run grep -nE '\\033\[2m|\\e\[2m|%F\{8\}' "${SCOPE[@]}"
    [ "$status" -ne 0 ] || fail "dim ou %F{8} trouve : $output"
}

@test "aucun code ANSI-256 achromatique dans le perimetre" {
    cd "$ROOT"
    # 232 a 255 : la rampe de gris de la palette xterm-256.
    run grep -nE '(38;5;|%F\{)(23[2-9]|24[0-9]|25[0-5])' "${SCOPE[@]}"
    [ "$status" -ne 0 ] || fail "gris ANSI-256 trouve : $output"
}

@test "aucune palette de thememe en dur dans le perimetre" {
    cd "$ROOT"
    run grep -nE "^(RED|GREEN|YELLOW|BLUE|NC)='\\\\033" "${SCOPE[@]}"
    [ "$status" -ne 0 ] || fail "palette ANSI redeclaree : $output"
}

@test "tous les fichiers du perimetre existent" {
    cd "$ROOT"
    for f in "${SCOPE[@]}"; do
        [ -f "$f" ] || fail "fichier du perimetre absent : $f"
    done
}
