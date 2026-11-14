#!/usr/bin/env bats

# A shell with no terminal attached (a script, a cron job, an agent harness
# running `zsh -i -c` on pipes) must run the system's own commands. An alias
# or function under a standard name changes what `ip route`, `ping host` or
# `df` do for every caller that did not choose it.

setup() {
    NIVUUS_SHELL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export NIVUUS_SHELL_DIR

    # Optional tools whose presence turns on colouring aliases. They are
    # appended to PATH, so a real binary always wins and a missing one still
    # exists for `command -v`: the colouring branches are exercised either way.
    _optional="$BATS_TEST_TMPDIR/optional-bin"
    mkdir -p "$_optional"
    local tool
    for tool in grc eza bat rg; do
        printf '#!/bin/sh\nexit 0\n' > "$_optional/$tool"
        chmod +x "$_optional/$tool"
    done

    _home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$_home"
    printf 'source %q\n' "$NIVUUS_SHELL_DIR/.zshrc" > "$_home/.zshrc"
}

# Standard command names (iproute2, procps, coreutils, diffutils, util-linux,
# iputils, ...). A name missing on this machine is given a stand-in at the end
# of PATH, so "is it shadowed?" is asked about every one of them.
_STANDARD_COMMANDS="ip w top ping df du ps diff free ls cat less tail tree
grep egrep fgrep mount dig netstat traceroute systemctl journalctl rg vim"

@test "without a terminal, standard command names are not aliases or functions" {
    local name
    for name in $_STANDARD_COMMANDS; do
        if ! command -v "$name" >/dev/null 2>&1; then
            printf '#!/bin/sh\nexit 0\n' > "$_optional/$name"
            chmod +x "$_optional/$name"
        fi
    done

    run env HOME="$_home" ZDOTDIR="$_home" NIVUUS_NO_COMPILE=1 \
        ENABLE_AUTOUPDATE=false TERM=xterm-256color PATH="$PATH:$_optional" \
        zsh -i -c '
for name in '"$(echo $_STANDARD_COMMANDS)"'; do
    kind=$(whence -w -- $name)
    case $kind in
        *": alias"|*": function") print -r -- "SHADOWED $(whence -v -- $name)" ;;
    esac
done
print -r -- LOADED
' </dev/null 2>/dev/null

    [[ "$output" == *LOADED* ]]
    if [[ "$output" == *SHADOWED* ]]; then
        printf '%s\n' "$output" | grep SHADOWED >&2
        return 1
    fi
}

@test "python and pip shortcuts never hide an installed python or pip" {
    local stand_in="$BATS_TEST_TMPDIR/python-bin"
    mkdir -p "$stand_in"
    printf '#!/bin/sh\nexit 0\n' > "$stand_in/python"
    printf '#!/bin/sh\nexit 0\n' > "$stand_in/pip"
    chmod +x "$stand_in/python" "$stand_in/pip"

    run env PATH="$stand_in:$PATH" zsh -c "
source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' 2>/dev/null
whence -w python pip
"
    [[ "$output" == *"python: command"* ]]
    [[ "$output" == *"pip: command"* ]]
}

@test "the IP shortcut has a name that shadows nothing and reports both addresses" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/15-aliases.zsh' 2>/dev/null && alias myips"
    [ "$status" -eq 0 ]
    [[ "$output" == *myip* ]]
    [[ "$output" == *localip* ]]
}
