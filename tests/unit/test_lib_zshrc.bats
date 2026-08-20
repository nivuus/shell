#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"
    source "$LIB/zshrc.sh"
    TMP="$(mktemp -d)"
    DIR="/home/u/.nivuus-shell"
}

teardown() { rm -rf "$TMP"; }

@test "state is missing when the file does not exist" {
    run nivuus_zshrc_state "$TMP/nope"
    [ "$output" = "missing" ]
}

@test "state is absent for a zshrc without the block" {
    printf 'export FOO=1\n' > "$TMP/.zshrc"
    run nivuus_zshrc_state "$TMP/.zshrc"
    [ "$output" = "absent" ]
}

@test "state is present when both markers exist" {
    nivuus_zshrc_block "$DIR" > "$TMP/.zshrc"
    run nivuus_zshrc_state "$TMP/.zshrc"
    [ "$output" = "present" ]
}

@test "state is corrupt when the closing marker is missing" {
    printf '# >>> nivuus shell >>>\nsource x\n' > "$TMP/.zshrc"
    run nivuus_zshrc_state "$TMP/.zshrc"
    [ "$output" = "corrupt" ]
}

@test "block references the install dir and .zsh_local" {
    run nivuus_zshrc_block "$DIR"
    [[ "$output" == *"$DIR"* ]]
    [[ "$output" == *".zsh_local"* ]]
}

@test "merge into a missing file yields the block alone" {
    run nivuus_zshrc_merge "$TMP/nope" "$DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *">>> nivuus shell >>>"* ]]
}

@test "merge inserts the block at the top, preserving user content" {
    printf 'export FOO=1\nalias ll=ls\n' > "$TMP/.zshrc"
    nivuus_zshrc_merge "$TMP/.zshrc" "$DIR" > "$TMP/out"
    run head -1 "$TMP/out"
    [ "$output" = "# >>> nivuus shell >>>" ]
    run grep -c "export FOO=1" "$TMP/out"
    [ "$output" = "1" ]
    run grep -c "alias ll=ls" "$TMP/out"
    [ "$output" = "1" ]
}

@test "merge is idempotent: twice yields exactly one block" {
    printf 'export FOO=1\n' > "$TMP/.zshrc"
    nivuus_zshrc_merge "$TMP/.zshrc" "$DIR" > "$TMP/once"
    cp "$TMP/once" "$TMP/.zshrc"
    nivuus_zshrc_merge "$TMP/.zshrc" "$DIR" > "$TMP/twice"
    run grep -c ">>> nivuus shell >>>" "$TMP/twice"
    [ "$output" = "1" ]
    run diff "$TMP/once" "$TMP/twice"
    [ "$status" -eq 0 ]
}

@test "merge replaces only the block content, leaving the rest intact" {
    { printf '# >>> nivuus shell >>>\nOLD CONTENT\n# <<< nivuus shell <<<\n'; \
      printf 'export KEEP=1\n'; } > "$TMP/.zshrc"
    nivuus_zshrc_merge "$TMP/.zshrc" "$DIR" > "$TMP/out"
    run grep -c "OLD CONTENT" "$TMP/out"
    [ "$status" -ne 0 ]
    run grep -c "export KEEP=1" "$TMP/out"
    [ "$output" = "1" ]
}

@test "merge refuses a corrupt file" {
    printf '# >>> nivuus shell >>>\nbroken\n' > "$TMP/.zshrc"
    run nivuus_zshrc_merge "$TMP/.zshrc" "$DIR"
    [ "$status" -eq 1 ]
}

@test "merge handles a file with no trailing newline" {
    printf 'export FOO=1' > "$TMP/.zshrc"
    nivuus_zshrc_merge "$TMP/.zshrc" "$DIR" > "$TMP/out"
    run grep -c "export FOO=1" "$TMP/out"
    [ "$output" = "1" ]
}

@test "strip removes the block and restores the original content" {
    printf 'export FOO=1\n' > "$TMP/orig"
    nivuus_zshrc_merge "$TMP/orig" "$DIR" > "$TMP/.zshrc"
    nivuus_zshrc_strip "$TMP/.zshrc" > "$TMP/back"
    run diff "$TMP/orig" "$TMP/back"
    [ "$status" -eq 0 ]
}

@test "strip on a file without the block is a no-op" {
    printf 'export FOO=1\n' > "$TMP/.zshrc"
    nivuus_zshrc_strip "$TMP/.zshrc" > "$TMP/out"
    run diff "$TMP/.zshrc" "$TMP/out"
    [ "$status" -eq 0 ]
}

@test "detect_framework finds oh-my-zsh" {
    printf 'source $ZSH/oh-my-zsh.sh\n' > "$TMP/.zshrc"
    run nivuus_zshrc_detect_framework "$TMP/.zshrc"
    [[ "$output" == *"oh-my-zsh"* ]]
}

@test "detect_framework finds starship" {
    printf 'eval "$(starship init zsh)"\n' > "$TMP/.zshrc"
    run nivuus_zshrc_detect_framework "$TMP/.zshrc"
    [[ "$output" == *"starship"* ]]
}

@test "detect_framework outputs nothing for a plain zshrc" {
    printf 'export FOO=1\n' > "$TMP/.zshrc"
    run nivuus_zshrc_detect_framework "$TMP/.zshrc"
    [ "$output" = "" ]
}
