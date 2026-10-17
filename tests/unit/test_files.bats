#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Unit tests for the file listing module (config/11-files.zsh)
#
# These cover a regression class rather than a single bug: `ll`, `la` and `l`
# used to carry their portability fallback inside the alias body, as
# `ls ... || ls ... || ls ...`. A `||` chain is a command list, so whatever the
# caller appended — an argument, a pipe — attached to the last branch alone,
# while the first branch had already succeeded and short-circuited. The
# `2>/dev/null` on those branches also swallowed genuine errors.
#
# Each test below is one of the three symptoms.

setup() {
    LISTING_DIR="$BATS_TEST_TMPDIR/listing"
    mkdir -p "$LISTING_DIR"
    touch "$LISTING_DIR/alpha.txt" "$LISTING_DIR/beta.txt" "$LISTING_DIR/gamma.txt"
    export LISTING_DIR
}

# Run zsh code that USES an alias, not just one that inspects it.
#
# It has to go through a script file: `zsh -c '...'` parses its whole argument
# before running any of it, so an alias defined on one line of that argument is
# not yet known when a later line is parsed, and the command reads as "not
# found". A file is read incrementally, which is also how a real shell loads
# these modules.
run_zsh_script() {
    local script="$BATS_TEST_TMPDIR/script.zsh"
    {
        printf "source '%s/config/00-core.zsh'\n" "$NIVUUS_SHELL_DIR"
        printf "source '%s/config/11-files.zsh'\n" "$NIVUUS_SHELL_DIR"
        printf '%s\n' "$1"
    } > "$script"
    run zsh "$script"
}

@test "la lists the directory it is given, not the current one" {
    run_zsh_script "cd '$BATS_TEST_TMPDIR'
la listing"
    [ "$status" -eq 0 ]
    [[ "$output" == *"alpha.txt"* ]]
    [[ "$output" == *"gamma.txt"* ]]
}

@test "la pipes its whole listing, not just a fallback branch" {
    run_zsh_script "la '$LISTING_DIR' | wc -l"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3"* ]]
}

@test "la reports a missing path instead of silently listing something else" {
    run_zsh_script "la '$BATS_TEST_TMPDIR/no-such-directory'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no-such-directory"* ]]
}

@test "ll and l also honour their argument" {
    run_zsh_script "ll '$LISTING_DIR'
l '$LISTING_DIR'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"beta.txt"* ]]
}

@test "listing aliases resolve the colour flag once, without a || chain" {
    run_zsh_script "alias la ll l"
    [ "$status" -eq 0 ]
    [[ "$output" != *"||"* ]]
}

@test "the tree fallback is a function, never an alias ending in a pipe" {
    # An alias whose body ends in a pipe hands the caller's argument to `sed`,
    # so `tree src` drew the current directory and passed src to sed as an
    # extra script file. The fallback is a function for that reason.
    #
    # Asserted on the module source: the branch only runs where tree(1) is
    # missing, which is not the case on most machines running this suite, so a
    # behavioural test here would silently never execute.
    run grep -c "alias tree='find" "$NIVUUS_SHELL_DIR/config/11-files.zsh"
    [ "$output" -eq 0 ]

    run grep -c "^    tree() {" "$NIVUUS_SHELL_DIR/config/11-files.zsh"
    [ "$output" -eq 1 ]
}

@test "the modern tools hint takes its install command from lib/deps.sh" {
    # A dnf-only PATH, no plugin installed anywhere. HOME has already seen
    # today's hint, so the background run started at load time stays quiet.
    local bin="$BATS_TEST_TMPDIR/bin" home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$bin" "$home/.cache/nivuus-shell"
    printf '#!/bin/sh\n' > "$bin/dnf"; chmod +x "$bin/dnf"
    date +%Y%m%d > "$home/.cache/nivuus-shell/last-tool-suggestion"
    run env -u NIVUUS_PKG_MANAGER HOME="$home" NIVUUS_UID=1000 \
        NIVUUS_PLUGIN_ROOT="$BATS_TEST_TMPDIR/no-plugins" \
        zsh -fc "source '$NIVUUS_SHELL_DIR/config/11-files.zsh'
            path=('$bin'); _suggest_modern_tools"
    [ "$status" -eq 0 ]
    [[ "$output" == *"missing: eza bat fd ripgrep timg zsh-autosuggestions zsh-syntax-highlighting"* ]]
    [[ "$output" == *"sudo dnf install -y eza bat fd-find ripgrep timg zsh-autosuggestions zsh-syntax-highlighting"* ]]
}
