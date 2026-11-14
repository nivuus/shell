#!/usr/bin/env bats

# A shell with no terminal (a script, an agent harness running `zsh -i -c`
# with every descriptor on a pipe) must not get output it did not ask for:
# hooks that print banners or terminal-title escapes would end up in the
# caller's standard output, mixed with the data it is reading.

bats_require_minimum_version 1.5.0

load "${BATS_TEST_DIRNAME}/../helpers/pty"

setup() {
    NIVUUS_SHELL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export NIVUUS_SHELL_DIR
    _home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$_home"
    printf 'source %q\n' "$NIVUUS_SHELL_DIR/.zshrc" > "$_home/.zshrc"

    # A directory every project hook reacts to.
    _project="$BATS_TEST_TMPDIR/project"
    mkdir -p "$_project/venv/bin"
    printf '{"name":"demo"}\n' > "$_project/package.json"
    printf 'requests\n' > "$_project/requirements.txt"
    printf 'VIRTUAL_ENV=%s/venv\n' "$_project" > "$_project/venv/bin/activate"
}

@test "cd into a project and back prints nothing on stdout without a terminal" {
    run --separate-stderr env HOME="$_home" ZDOTDIR="$_home" NIVUUS_NO_COMPILE=1 \
        TERM=xterm-256color ENABLE_PYTHON_AUTO_ACTIVATE=true \
        zsh -i -c "cd ${_project@Q}; cd /" </dev/null
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then
        printf 'unexpected stdout: %q\n' "$output" >&2
        return 1
    fi
}

@test "at a terminal, the updater says in one line why it skips a development checkout" {
    pty_run "export HOME=${_home@Q} NIVUUS_SHELL_DIR=${NIVUUS_SHELL_DIR@Q}
source '$NIVUUS_SHELL_DIR/config/00-core.zsh'
source '$NIVUUS_SHELL_DIR/config/20-autoupdate.zsh'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"development checkout"* ]]
    [ "$(printf '%s\n' "$output" | grep -c "development checkout")" -eq 1 ]
}
