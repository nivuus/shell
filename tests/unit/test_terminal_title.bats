#!/usr/bin/env bats

# Unit tests for AI terminal titles (config/20-terminal-title.zsh)
#
# `_terminal_title_preexec` runs on every command, BEFORE it executes. Any
# second it spends there is a second the user stares at a frozen terminal. A
# backend that is slow, unreachable, or answering with an error (an agy model
# slug that got retired, say) must therefore never be waited on inline.

setup() {
    export TERM=xterm-256color
    export ENABLE_AI_TERMINAL_TITLES=true
    export AI_TITLE_CACHE_DIR="$BATS_TEST_TMPDIR/titles"
    unset NIVUUS_TERMINAL_TITLE_LOADED
}

# Source the module with the AI backend stubbed to take $1 seconds.
# Title-setting escape sequences go to /dev/null so only our markers surface.
_preamble() {
    local delay="${1:-5}"
    echo '
zmodload zsh/datetime
unset NIVUUS_TERMINAL_TITLE_LOADED
export TERM=xterm-256color
export ENABLE_AI_TERMINAL_TITLES=true
export AI_TITLE_CACHE_DIR="'"$AI_TITLE_CACHE_DIR"'"
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-core.zsh" >/dev/null 2>&1
source "'"$NIVUUS_SHELL_DIR"'/config/20-terminal-title.zsh" >/dev/null 2>&1
_ai_credentials_ok() { return 0 }
_ai_api_call() { sleep '"$delay"'; print -r -- "ROCKET Slow Title" }
exec 3>&1 1>/dev/null
say() { print -r -- "$@" >&3 }
'
}

@test "preexec does not block on a slow AI backend" {
    run zsh -c "$(_preamble 5)
s=\$EPOCHREALTIME
_terminal_title_preexec 'make build'
say \"ELAPSED \$(printf '%.2f' \$((EPOCHREALTIME - s)))\"
"
    [ "$status" -eq 0 ]
    local elapsed="${output##*ELAPSED }"
    # The whole point: preexec hands control back immediately.
    (( $(echo "$elapsed < 1.0" | bc -l) )) || {
        echo "preexec blocked for ${elapsed}s (backend took 5s)" >&2
        false
    }
}

@test "a title generated in the background lands on a later prompt" {
    run zsh -c "$(_preamble 2)
_terminal_title_preexec 'make build'
# Not ready yet: the backend needs 2s, preexec returned at once.
_terminal_title_precmd
say \"IMMEDIATE=[\$_AI_TITLE_CURRENT]\"
for i in {1..60}; do
    sleep 0.25
    _terminal_title_precmd
    [[ -n \"\$_AI_TITLE_CURRENT\" ]] && break
done
say \"EVENTUAL=[\$_AI_TITLE_CURRENT]\"
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"IMMEDIATE=[]"* ]]
    [[ "$output" == *"EVENTUAL=[ROCKET Slow Title]"* ]]
}

@test "a failing backend leaves no stale title and still does not block" {
    run zsh -c "$(_preamble 0)
_ai_api_call() { return 1 }
s=\$EPOCHREALTIME
_terminal_title_preexec 'make build'
say \"ELAPSED \$(printf '%.2f' \$((EPOCHREALTIME - s)))\"
sleep 1
_terminal_title_precmd
say \"TITLE=[\$_AI_TITLE_CURRENT]\"
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TITLE=[]"* ]]
}

@test "back-to-back commands do not pile up background generations" {
    run zsh -c "$(_preamble 3)
_terminal_title_preexec 'a'
_terminal_title_preexec 'b'
_terminal_title_preexec 'c'
say \"JOBS=\$(jobs -pr | grep -c . || true)\"
"
    [ "$status" -eq 0 ]
    local jobs="${output##*JOBS=}"
    [ "${jobs%%$'\n'*}" -le 1 ]
}

# The title call used to hand the backend a 3s budget, sized for the REST API.
# Under GEMINI_AUTH_MODE=cli the agy round trip is 5-6s warm, so the title was
# cut off every single time and the feature silently produced nothing.
@test "the title call gives the backend a budget it can actually meet" {
    run zsh -c "$(_preamble 0)
_ai_api_call() { say \"TIMEOUT=\$5\"; print -r -- 'x' }
_ai_get_terminal_title 'make build' 'shell' >/dev/null
"
    [ "$status" -eq 0 ]
    timeout_arg="${output##*TIMEOUT=}"
    timeout_arg="${timeout_arg%%$'\n'*}"
    [ -n "$timeout_arg" ]
    [ "$timeout_arg" -ge 10 ]
}
