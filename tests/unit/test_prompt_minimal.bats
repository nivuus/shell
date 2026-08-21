#!/usr/bin/env bats

setup() { ROOT="${BATS_TEST_DIRNAME}/../.."; }

load_prompt() {   # load_prompt "<env>" "<expr>"
    run zsh -c "export NIVUUS_SHELL_DIR='$ROOT'; $1 \
                source '$ROOT/themes/nord.zsh'; source '$ROOT/config/05-prompt.zsh'; $2"
}

@test "the prompt glyphs are Unicode by default" {
    load_prompt "" 'print -r -- "$NIVUUS_GLYPH_GIT_CLEAN$NIVUUS_GLYPH_JOB_STOPPED"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"●"* ]]
    [[ "$output" == *"⏸"* ]]
}

@test "NIVUUS_MINIMAL falls back to pure ASCII glyphs" {
    load_prompt "export NIVUUS_MINIMAL=1;" \
        'print -r -- "$NIVUUS_GLYPH_GIT_CLEAN|$NIVUUS_GLYPH_GIT_DIRTY|$NIVUUS_GLYPH_JOB_RUNNING|$NIVUUS_GLYPH_JOB_STOPPED"'
    [ "$status" -eq 0 ]
    [[ "$output" != *"●"* ]]
    [[ "$output" != *"○"* ]]
    [[ "$output" != *"▶"* ]]
    [[ "$output" != *"⏸"* ]]
}

@test "the glyphs stay user-overridable" {
    load_prompt "export NIVUUS_GLYPH_GIT_CLEAN=OK;" 'print -r -- "$NIVUUS_GLYPH_GIT_CLEAN"'
    [ "$output" = "OK" ]
}

@test "git_prompt_info uses the ASCII glyph under NIVUUS_MINIMAL" {
    run zsh -c "export NIVUUS_SHELL_DIR='$ROOT'; export NIVUUS_MINIMAL=1; \
                source '$ROOT/themes/nord.zsh'; source '$ROOT/config/05-prompt.zsh'; \
                cd '$ROOT'; git_prompt_info"
    [ "$status" -eq 0 ]
    [[ "$output" != *"●"* && "$output" != *"○"* ]]
}
