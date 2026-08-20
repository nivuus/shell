#!/usr/bin/env bats

# Unit tests for the persistent Antigravity CLI daemon
# (config/09-ai-agy-daemon.zsh)
#
# A cold `agy -p` costs 3-6s of process/session startup on top of the model
# turn. The daemon keeps one `agy --input-format stream-json` process alive and
# feeds it one NDJSON message per turn, which removes that startup from every
# call but the first.

setup() {
    unset AI_BACKEND GEMINI_AUTH_MODE GEMINI_CLI_MODEL
    export AGY_DAEMON_RUNTIME_DIR="$BATS_TEST_TMPDIR/rt"
    export AGY_FAKE_LOG="$BATS_TEST_TMPDIR/agy-starts.log"
    export FAKE_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$FAKE_BIN"

    # Fake agy speaking both protocols: stream-json (daemon) and one-shot.
    cat > "$FAKE_BIN/agy" <<'INNEREOF'
#!/usr/bin/env bash
mode="oneshot"
prompt=""
for a in "$@"; do
    case "$a" in
        --input-format=stream-json) mode="daemon" ;;
        stream-json) [[ "$prev" == "--input-format" ]] && mode="daemon" ;;
        --print=*) prompt="${a#--print=}" ;;
    esac
    prev="$a"
done

if [[ "$mode" == "daemon" ]]; then
    # One start = one line in the log, so tests can count process reuse.
    echo "start $$" >> "$AGY_FAKE_LOG"
    while IFS= read -r line; do
        text=$(printf '%s' "$line" | sed -n 's/.*"content":"\(.*\)"}}$/\1/p')
        printf '{"event":"init","init":{"model":"fake"}}\n'
        printf '{"event":"result","result":{"status":"SUCCESS","response":"daemon:%s","usage":{"input_tokens":100,"cache_read_tokens":0}}}\n' "$text"
    done
    exit 0
fi

echo "oneshot $$ cwd=$PWD" >> "$AGY_FAKE_LOG"
printf '{"status":"SUCCESS","response":"oneshot:%s"}\n' "$prompt"
INNEREOF
    chmod +x "$FAKE_BIN/agy"
}

teardown() {
    # Kill any daemon a test left behind.
    local pidfile
    for pidfile in "$AGY_DAEMON_RUNTIME_DIR"/*/pid; do
        [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null
    done
    return 0
}

# Boilerplate: source the modules with the fake agy on PATH.
_preamble() {
    echo '
export PATH="'"$FAKE_BIN"':$PATH"
export AGY_DAEMON_RUNTIME_DIR="'"$AGY_DAEMON_RUNTIME_DIR"'"
export AGY_FAKE_LOG="'"$AGY_FAKE_LOG"'"
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-core.zsh"
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-agy-daemon.zsh"
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-backend-gemini.zsh"
'
}

@test "daemon call returns the agy response text" {
    run zsh -c "$(_preamble)
_agy_daemon_call 'hello world' 'fake-model' 10
"
    [ "$status" -eq 0 ]
    [ "$output" = "daemon:hello world" ]
}

@test "daemon reuses a single agy process across calls" {
    run zsh -c "$(_preamble)
_agy_daemon_call 'one' 'fake-model' 10
_agy_daemon_call 'two' 'fake-model' 10
_agy_daemon_call 'three' 'fake-model' 10
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"daemon:one"* ]]
    [[ "$output" == *"daemon:three"* ]]
    # Exactly one agy start for three calls.
    [ "$(grep -c '^start ' "$AGY_FAKE_LOG")" -eq 1 ]
}

@test "daemon escapes prompts containing quotes and newlines" {
    run zsh -c "$(_preamble)
_agy_daemon_call 'say \"hi\"' 'fake-model' 10
"
    [ "$status" -eq 0 ]
    [[ "$output" == *'hi'* ]]
}

@test "daemon restarts once AGY_DAEMON_MAX_TURNS is reached" {
    run zsh -c "$(_preamble)
export AGY_DAEMON_MAX_TURNS=2
_agy_daemon_call 'a' 'fake-model' 10
_agy_daemon_call 'b' 'fake-model' 10
_agy_daemon_call 'c' 'fake-model' 10
"
    [ "$status" -eq 0 ]
    [ "$(grep -c '^start ' "$AGY_FAKE_LOG")" -ge 2 ]
}

@test "gemini cli mode routes through the daemon by default" {
    run zsh -c "$(_preamble)
export GEMINI_AUTH_MODE=cli
_ai_backend_gemini_call 'ping' 'ignored-api-model' 100 0.3 10
"
    [ "$status" -eq 0 ]
    [[ "$output" == daemon:* ]]
}

@test "gemini cli mode falls back to one-shot when the daemon is disabled" {
    run zsh -c "$(_preamble)
export GEMINI_AUTH_MODE=cli AGY_DAEMON_ENABLED=false
_ai_backend_gemini_call 'ping' 'ignored-api-model' 100 0.3 10
"
    [ "$status" -eq 0 ]
    [[ "$output" == oneshot:* ]]
}

@test "gemini cli mode falls back to one-shot when the daemon cannot start" {
    run zsh -c "$(_preamble)
export GEMINI_AUTH_MODE=cli
# An unwritable runtime dir makes daemon startup fail.
export AGY_DAEMON_RUNTIME_DIR=/proc/nivuus-cannot-create
_ai_backend_gemini_call 'ping' 'ignored-api-model' 100 0.3 10
"
    [ "$status" -eq 0 ]
    [[ "$output" == oneshot:* ]]
}

@test "one-shot fallback runs agy from a neutral directory, not the caller's cwd" {
    # agy indexes its working directory: launching from a git repo costs ~1s of
    # wall clock per call (measured), for context none of our prompts use.
    local caller_dir="$BATS_TEST_TMPDIR/project"
    mkdir -p "$caller_dir"

    run zsh -c "$(_preamble)
export GEMINI_AUTH_MODE=cli AGY_DAEMON_ENABLED=false
cd '$caller_dir'
_ai_backend_gemini_call 'ping' 'ignored-api-model' 100 0.3 10
"
    [ "$status" -eq 0 ]
    [[ "$output" == oneshot:* ]]
    [[ "$(cat "$AGY_FAKE_LOG")" != *"cwd=$caller_dir"* ]]
    [[ "$(cat "$AGY_FAKE_LOG")" == *"cwd=$AGY_DAEMON_RUNTIME_DIR"* ]]
}

@test "one-shot fallback still answers when the neutral directory cannot be created" {
    run zsh -c "$(_preamble)
export GEMINI_AUTH_MODE=cli AGY_DAEMON_ENABLED=false
export AGY_DAEMON_RUNTIME_DIR=/proc/nivuus-cannot-create
_ai_backend_gemini_call 'ping' 'ignored-api-model' 100 0.3 10
"
    [ "$status" -eq 0 ]
    [[ "$output" == oneshot:* ]]
}

@test "daemon call fails when agy is not installed" {
    run zsh -c '
export PATH="/nonexistent-bin-only"
export AGY_DAEMON_RUNTIME_DIR="'"$AGY_DAEMON_RUNTIME_DIR"'"
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-core.zsh"
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-agy-daemon.zsh"
_agy_daemon_call "hello" "fake-model" 5
'
    [ "$status" -ne 0 ]
}

@test "ai-daemon status reports stopped before any call" {
    run zsh -c "$(_preamble)
ai-daemon status
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"stopped"* ]] || [[ "$output" == *"not running"* ]]
}

@test "ai-daemon stop kills a running daemon" {
    run zsh -c "$(_preamble)
# ai-daemon acts on the cli-mode model, so point it at the fake one.
export GEMINI_CLI_MODEL=fake-model
_agy_daemon_call 'hello' 'fake-model' 10 >/dev/null
ai-daemon stop
_agy_daemon_alive 'fake-model' && echo STILL_ALIVE || echo STOPPED
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"STOPPED"* ]]
}

@test "daemon is disabled cleanly when flock is unavailable" {
    local nolock="$BATS_TEST_TMPDIR/nolock"
    mkdir -p "$nolock"
    run zsh -c "$(_preamble)
export GEMINI_AUTH_MODE=cli
_agy_daemon_has_flock() { return 1; }
_ai_backend_gemini_call 'ping' 'ignored-api-model' 100 0.3 10
"
    [ "$status" -eq 0 ]
    [[ "$output" == oneshot:* ]]
}
