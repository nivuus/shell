#!/usr/bin/env bats
# Locale handling of config/01-environment.zsh: the person's locale is
# theirs, the shell never overrides it.

setup() {
    NIVUUS_SHELL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export NIVUUS_SHELL_DIR
}

# Print LANG / LC_ALL / LC_CTYPE after loading the module in a clean
# environment holding only the variables given as arguments.
_locale_after_load() {
    run env -i HOME="$BATS_TEST_TMPDIR" PATH=/usr/bin:/bin "$@" zsh -f -c "
source '$NIVUUS_SHELL_DIR/config/01-environment.zsh'
print -r -- \"LANG=\$LANG LC_ALL=\${LC_ALL-<unset>} LC_CTYPE=\${LC_CTYPE-<unset>}\""
}

@test "the person's LANG is kept and LC_ALL is not forced" {
    _locale_after_load LANG=ja_JP.UTF-8
    [ "$status" -eq 0 ]
    [ "$output" = "LANG=ja_JP.UTF-8 LC_ALL=<unset> LC_CTYPE=<unset>" ]
}

@test "a per-category locale is not overridden" {
    _locale_after_load LANG=fr_FR.UTF-8 LC_TIME=de_DE.UTF-8
    [ "$status" -eq 0 ]
    [ "$output" = "LANG=fr_FR.UTF-8 LC_ALL=<unset> LC_CTYPE=<unset>" ]
    run env -i LANG=fr_FR.UTF-8 LC_TIME=de_DE.UTF-8 zsh -f -c "source '$NIVUUS_SHELL_DIR/config/01-environment.zsh'; print -r -- \$LC_TIME"
    [ "$output" = "de_DE.UTF-8" ]
}

@test "an LC_ALL set by the person is left as it is" {
    _locale_after_load LC_ALL=ar_EG.UTF-8
    [ "$status" -eq 0 ]
    [ "$output" = "LANG= LC_ALL=ar_EG.UTF-8 LC_CTYPE=<unset>" ]
}

@test "with no locale at all, only a language-neutral UTF-8 one is set" {
    _locale_after_load
    [ "$status" -eq 0 ]
    [ "$output" = "LANG=C.UTF-8 LC_ALL=<unset> LC_CTYPE=<unset>" ]
}
