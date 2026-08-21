#!/usr/bin/env bats

load '../helpers/portable'

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

@test "merge is idempotent even when the whole file was re-saved as CRLF" {
    # A Windows-side editor on WSL can re-save the entire file with CRLF
    # line endings, block markers included. grep -qF (state) still matches
    # a substring so it correctly reports "present", but strip used to
    # compare $0 to the marker with strict equality: the trailing \r never
    # matched, the block was never stripped, and it doubled on every
    # subsequent install.
    nivuus_zshrc_block "$DIR" > "$TMP/.zshrc"
    printf 'export MINE=42\n' >> "$TMP/.zshrc"
    pt_to_crlf "$TMP/.zshrc"

    run nivuus_zshrc_state "$TMP/.zshrc"
    [ "$output" = "present" ]

    nivuus_zshrc_merge "$TMP/.zshrc" "$DIR" > "$TMP/twice"
    run grep -c ">>> nivuus shell >>>" "$TMP/twice"
    [ "$output" = "1" ]

    cp "$TMP/twice" "$TMP/.zshrc"
    nivuus_zshrc_merge "$TMP/.zshrc" "$DIR" > "$TMP/thrice"
    run grep -c ">>> nivuus shell >>>" "$TMP/thrice"
    [ "$output" = "1" ]
}

@test "strip on a CRLF file removes the block despite the trailing \\r" {
    nivuus_zshrc_block "$DIR" > "$TMP/.zshrc"
    printf 'export KEEP=1\n' >> "$TMP/.zshrc"
    pt_to_crlf "$TMP/.zshrc"

    run nivuus_zshrc_strip "$TMP/.zshrc"
    [[ "$output" != *"nivuus shell"* ]]
    [[ "$output" == *"export KEEP=1"* ]]
}

@test "state on an empty file is absent, not corrupt" {
    : > "$TMP/.zshrc"
    run nivuus_zshrc_state "$TMP/.zshrc"
    [ "$output" = "absent" ]
}

@test "merge on an empty file yields the block alone" {
    : > "$TMP/.zshrc"
    run nivuus_zshrc_merge "$TMP/.zshrc" "$DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *">>> nivuus shell >>>"* ]]
}

@test "strip on an empty file is a no-op" {
    : > "$TMP/.zshrc"
    run nivuus_zshrc_strip "$TMP/.zshrc"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
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

@test "the block carries NIVUUS_MINIMAL only when asked" {
    run bash -c "source '$LIB/zshrc.sh'; nivuus_zshrc_block /opt/nivuus"
    [[ "$output" != *"NIVUUS_MINIMAL"* ]]
    run bash -c "source '$LIB/zshrc.sh'; nivuus_zshrc_block /opt/nivuus 1"
    [[ "$output" == *"export NIVUUS_MINIMAL=1"* ]]
}

# --- Compatibilité ascendante : la strophe que v3.0.0 écrivait ----------
# (git show v3.0.0:install.sh, lignes 257-261 : aucun marqueur, donc
# classée « absent » par nivuus_zshrc_state.)

@test "la strophe v3.0.0 est reconnue" {
    cat > "$TMP/zshrc" <<'EOS'
# Nivuus Shell Configuration
export NIVUUS_SHELL_DIR="/home/u/.nivuus-shell"
source "$NIVUUS_SHELL_DIR/.zshrc"
EOS
    run nivuus_zshrc_legacy_present "$TMP/zshrc"
    [ "$status" -eq 0 ]
}

@test "un .zshrc quelconque n'est PAS pris pour la strophe v3.0.0" {
    printf 'alias ll="ls -la"\nexport EDITOR=vim\n' > "$TMP/zshrc"
    run nivuus_zshrc_legacy_present "$TMP/zshrc"
    [ "$status" -ne 0 ]
}

@test "sans l'en-tête, la strophe n'est pas reconnue" {
    printf 'export NIVUUS_SHELL_DIR="/x"\nsource "$NIVUUS_SHELL_DIR/.zshrc"\n' > "$TMP/zshrc"
    run nivuus_zshrc_legacy_present "$TMP/zshrc"
    [ "$status" -ne 0 ]
}

@test "un .zshrc déjà géré par bloc n'est pas traité comme legacy" {
    nivuus_zshrc_block "/x" > "$TMP/zshrc"
    printf '# Nivuus Shell Configuration\n' >> "$TMP/zshrc"
    run nivuus_zshrc_legacy_present "$TMP/zshrc"
    [ "$status" -ne 0 ]
}

@test "strip_legacy retire les trois lignes et RIEN d'autre" {
    cat > "$TMP/zshrc" <<'EOS'
# mes réglages
export EDITOR=vim
# Nivuus Shell Configuration
export NIVUUS_SHELL_DIR="/home/u/.nivuus-shell"
source "$NIVUUS_SHELL_DIR/.zshrc"
alias ll="ls -la"
EOS
    run nivuus_zshrc_strip_legacy "$TMP/zshrc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"export EDITOR=vim"* ]]
    [[ "$output" == *'alias ll="ls -la"'* ]]
    [[ "$output" == *"# mes réglages"* ]]
    [[ "$output" != *"NIVUUS_SHELL_DIR"* ]]
    [[ "$output" != *"Nivuus Shell Configuration"* ]]
}

@test "merge sur un .zshrc v3.0.0 ne produit qu'UNE source de Nivuus" {
    cat > "$TMP/zshrc" <<'EOS'
# Nivuus Shell Configuration
export NIVUUS_SHELL_DIR="/ancien"
source "$NIVUUS_SHELL_DIR/.zshrc"
EOS
    run nivuus_zshrc_merge "$TMP/zshrc" "/nouveau" ""
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c 'NIVUUS_SHELL_DIR/.zshrc')" -eq 1 ]
    [[ "$output" == *"/nouveau"* ]]
    [[ "$output" != *"/ancien"* ]]
}
