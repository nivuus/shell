#!/usr/bin/env bats

# The inline AI suggestion is rendered by zle -F handlers (spinner, then
# typewriter). Those handlers are silently never serviced when the widget that
# registers them was itself reached from a `zsh/sched` callback, which is how
# the debounce timer used to fire: the suggestion was generated and then never
# displayed. Nothing short of driving a real interactive zsh on a pty catches
# that, so this test does exactly that, with the backend call stubbed out.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TESTDIR="$BATS_TEST_TMPDIR/inline"
    mkdir -p "$TESTDIR"

    cat > "$TESTDIR/.zshrc" <<EOF
export NIVUUS_SHELL_DIR="$REPO_ROOT"
source "$REPO_ROOT/.zshrc"

# Stub the backend: no network, and a marker no history entry can produce.
_ai_generate() { print -r -- "\${1}ZZZTEST" }

# Dump POSTDISPLAY on demand, so the test reads what is on screen without
# having to parse terminal escape sequences.
_ai_test_dump() { print -r -- "POSTDISPLAY=[\$POSTDISPLAY]" >> "$TESTDIR/dump" }
zle -N _ai_test_dump
bindkey '^T' _ai_test_dump
EOF

    cat > "$TESTDIR/drive.zsh" <<EOF
zmodload zsh/zpty
zpty -b Z env -i \\
    HOME="\$HOME" PATH="\$PATH" TERM=xterm-256color \\
    ZDOTDIR="$TESTDIR" \\
    ENABLE_AI_SUGGESTIONS=true \\
    ENABLE_AI_AUTO_DEBOUNCE=true \\
    AI_DEBOUNCE_DELAY=1 \\
    AI_SUGGESTION_MIN_CHARS=3 \\
    ENABLE_AI_TERMINAL_TITLES=false \\
    ENABLE_AI_COMMAND_NOT_FOUND=false \\
    zsh -i
sleep 10
zpty -w -n Z "qqq"
sleep 4
zpty -w -n Z \$'\\x14'
sleep 1
zpty -d Z
EOF

    : > "$TESTDIR/dump"
}

@test "inline suggestion is displayed after the debounce delay" {
    if ! command -v zsh >/dev/null 2>&1; then
        skip "zsh not available"
    fi

    run timeout 60 zsh "$TESTDIR/drive.zsh"

    [ -s "$TESTDIR/dump" ]
    # POSTDISPLAY holds the ghost text, i.e. the suffix past what was typed.
    grep -q "POSTDISPLAY=\[ZZZTEST\]" "$TESTDIR/dump"
}

@test "debounce timer does not use zsh/sched" {
    # A sched callback poisons zle -F for the rest of the line; the timer has
    # to stay on a file descriptor handler.
    run grep -nE '^[[:space:]]*(sched\b|zmodload zsh/sched)' "$REPO_ROOT/config/19-ai-suggestions.zsh"
    [ "$status" -ne 0 ]
}
