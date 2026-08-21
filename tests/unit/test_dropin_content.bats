#!/usr/bin/env bats
#
# Le contenu du drop-in porte trois décisions : il cède à l'utilisateur, il
# se déclare (pour être vérifiable), et il ne casse rien si l'arbre part.
# Toutes trois se prouvent sur du texte, sans root et sans zsh.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local" NIVUUS_ETC_DIR="$TMP/etc"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/detect.sh"; . "$ROOT/lib/system.sh"
}

teardown() { rm -rf "$TMP"; }

@test "le drop-in cède à l'utilisateur qui a son propre bloc" {
    run nivuus_system_dropin_content
    [[ "$output" == *">>> nivuus shell >>>"* ]]
    [[ "$output" == *"grep -qs"* ]]
    [[ "$output" == *'${ZDOTDIR:-$HOME}/.zshrc'* ]]
}

@test "le drop-in ne s'applique qu'aux shells interactifs" {
    run nivuus_system_dropin_content
    [[ "$output" == *"-o interactive"* ]]
}

@test "le drop-in se déclare : NIVUUS_ACTIVATED_BY=system" {
    run nivuus_system_dropin_content
    [[ "$output" == *"NIVUUS_ACTIVATED_BY=system"* ]]
}

@test "le drop-in porte la garde : un arbre absent ne casse aucun shell" {
    run nivuus_system_dropin_content
    [[ "$output" == *'[ -r '* ]]
}

@test "le drop-in pointe vers l'arbre système, jamais vers un \$HOME" {
    run nivuus_system_dropin_content
    [[ "$output" == *"$TMP/usr/local/share/nivuus-shell"* ]]
    [[ "$output" != *'/home/'* ]]
}

@test "le drop-in est du zsh valide" {
    command -v zsh >/dev/null 2>&1 || skip "zsh indisponible"
    nivuus_system_dropin_content > "$TMP/dropin.zsh"
    run zsh -n "$TMP/dropin.zsh"
    [ "$status" -eq 0 ]
}

@test "le drop-in n'agit QUE dans un shell interactif (exécuté, pas relu)" {
    command -v zsh >/dev/null 2>&1 || skip "zsh indisponible"
    nivuus_system_dropin_content > "$TMP/dropin.zsh"
    # Non interactif : rien ne doit être posé.
    run zsh -c "source '$TMP/dropin.zsh'; print -r -- \"\${NIVUUS_ACTIVATED_BY:-none}\""
    [ "${lines[-1]}" = "none" ]
}

@test "la ligne du rc global est UNE ligne, et elle est reconnaissable" {
    run nivuus_system_rc_line
    [ "${#lines[@]}" -eq 1 ]
    [[ "$output" == *"10-nivuus.zsh"* ]]
    [[ "$output" == *"nivuus"* ]]
}

@test "la ligne du rc global est gardée elle aussi" {
    # Le drop-in peut disparaître (retrait partiel, image immuable) : la
    # ligne restée dans un conffile ne doit jamais casser un shell.
    run nivuus_system_rc_line
    [[ "$output" == *"[ -r "* ]]
}

@test "la ligne du rc global est du zsh valide" {
    command -v zsh >/dev/null 2>&1 || skip "zsh indisponible"
    nivuus_system_rc_line > "$TMP/ligne.zsh"
    run zsh -n "$TMP/ligne.zsh"
    [ "$status" -eq 0 ]
}
