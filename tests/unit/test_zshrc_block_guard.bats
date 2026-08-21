#!/usr/bin/env bats
# Le bloc écrit dans ~/.zshrc doit survivre à la disparition de l'arbre
# Nivuus : c'est le cas NORMAL après un « brew uninstall » ou un « apt purge »
# alors que des utilisateurs ont encore le bloc.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"
    . "$ROOT/lib/zshrc.sh"
}

teardown() { rm -rf "$TMP"; }

@test "the block guards its source line with a readability test" {
    run nivuus_zshrc_block "/usr/share/nivuus-shell"
    [ "$status" -eq 0 ]
    [[ "$output" == *'[ -r "$NIVUUS_SHELL_DIR/.zshrc" ] && source "$NIVUUS_SHELL_DIR/.zshrc"'* ]]
}

@test "the block NEVER contains a bare, unguarded source line" {
    run nivuus_zshrc_block "$HOME/.nivuus-shell"
    while IFS= read -r line; do
        [ "$line" != 'source "$NIVUUS_SHELL_DIR/.zshrc"' ]
    done <<< "$output"
}

@test "the guard is emitted in minimal mode too (one block, proven once)" {
    run nivuus_zshrc_block "/usr/share/nivuus-shell" 1
    [[ "$output" == *'[ -r "$NIVUUS_SHELL_DIR/.zshrc" ]'* ]]
    [[ "$output" == *'export NIVUUS_MINIMAL=1'* ]]
}

@test "a zsh reading the block with a MISSING tree prints nothing on stderr" {
    # LA propriété : arbre absent, bloc présent, shell silencieux.
    nivuus_zshrc_block "$TMP/nexistepas" > "$TMP/zshrc"
    run zsh -c "source '$TMP/zshrc' 2>'$TMP/err'; exit 0"
    [ "$status" -eq 0 ]
    [ ! -s "$TMP/err" ]
}

@test "a zsh reading the block with a PRESENT tree still sources it" {
    mkdir -p "$TMP/tree"
    printf 'export NIVUUS_PROOF=sourced\n' > "$TMP/tree/.zshrc"
    nivuus_zshrc_block "$TMP/tree" > "$TMP/zshrc"
    run zsh -c "source '$TMP/zshrc'; print -r -- \$NIVUUS_PROOF"
    [ "$status" -eq 0 ]
    [ "$output" = "sourced" ]
}

@test "an unreadable tree .zshrc is treated as absent, not as an error" {
    [ "$(id -u)" -ne 0 ] || skip "root lit tout"
    mkdir -p "$TMP/tree"
    printf 'echo nope\n' > "$TMP/tree/.zshrc"
    chmod 000 "$TMP/tree/.zshrc"
    nivuus_zshrc_block "$TMP/tree" > "$TMP/zshrc"
    run zsh -c "source '$TMP/zshrc' 2>'$TMP/err'; exit 0"
    [ ! -s "$TMP/err" ]
    chmod 644 "$TMP/tree/.zshrc"
}

@test "the block is still stripped cleanly by nivuus_zshrc_strip" {
    # La garde ne doit pas casser le retrait : c'est lui qui porte la
    # réversibilité bit-exacte.
    printf 'export MINE=1\n' > "$TMP/zshrc"
    { nivuus_zshrc_block "$TMP/tree"; cat "$TMP/zshrc"; } > "$TMP/merged"
    run nivuus_zshrc_strip "$TMP/merged"
    [ "$output" = "export MINE=1" ]
}
