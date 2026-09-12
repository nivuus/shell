#!/usr/bin/env zsh
# =============================================================================
# AI Backend - Antigravity CLI (agy) persistent daemon
# =============================================================================
# A cold `agy -p "prompt"` spends 3-6s on process/session startup (auth,
# conversation creation, plugin + slash-command loading, workspace indexing)
# before the model turn even begins -- measured against ~2s for the turn
# itself. `agy --input-format stream-json` reads one NDJSON message per line
# from stdin and runs a turn for each, so keeping a single process alive
# amortizes that startup over every call: ~5.5s cold, ~1s warm.
#
# The daemon is shared by every shell of the user (one process per model),
# reached through a pair of FIFOs, and serialized with flock since agy handles
# one turn at a time. Any failure falls back to the one-shot `agy -p` path.
# =============================================================================

# Set to false to always use the one-shot `agy -p` path.
typeset -g AGY_DAEMON_ENABLED="${AGY_DAEMON_ENABLED:-true}"

# The agy model slug, and the single place its default is written down.
# Antigravity retires tiers as it ships new ones: a slug it no longer knows
# does not fail fast, it burns the full 4-6s startup before answering
# "invalid model selection", and every AI feature silently returns nothing.
# Keeping one definition means no copy can be left pointing at a dead model.
typeset -g GEMINI_CLI_MODEL="${GEMINI_CLI_MODEL:-gemini-3.6-flash-low}"

# Each turn re-sends the whole conversation, so input tokens grow ~6k per turn.
# Recycle the process regularly to keep prompts small (each of our prompts is
# self-contained -- the accumulated history is pure overhead).
typeset -g AGY_DAEMON_MAX_TURNS="${AGY_DAEMON_MAX_TURNS:-8}"

# Lifetime cap handed to agy itself, so a forgotten daemon eventually exits.
typeset -g AGY_DAEMON_TTL="${AGY_DAEMON_TTL:-8h}"

typeset -g AGY_DAEMON_RUNTIME_DIR="${AGY_DAEMON_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}/nivuus-agy-${UID}}"

# Set while a caller holds the flock, so _agy_daemon_start can close that fd
# inside the daemon: an inherited lock fd would keep the lock held for the
# daemon's whole life and stall every later call until its flock timeout.
typeset -g _AGY_DAEMON_LOCK_FD=""

_agy_daemon_has_flock() {
    command -v flock &>/dev/null
}

# One daemon per model: the model is fixed for the life of an agy process.
_agy_daemon_dir() {
    local model="${1//[^a-zA-Z0-9._-]/_}"
    print -r -- "$AGY_DAEMON_RUNTIME_DIR/$model"
}

_agy_daemon_alive() {
    local dir=$(_agy_daemon_dir "$1")
    local pid
    [[ -f "$dir/pid" ]] || return 1
    pid=$(<"$dir/pid") 2>/dev/null
    [[ -n "$pid" ]] || return 1
    kill -0 "$pid" 2>/dev/null
}

_agy_daemon_stop() {
    local model="$1"
    local dir=$(_agy_daemon_dir "$model")
    local pid
    if [[ -f "$dir/pid" ]]; then
        pid=$(<"$dir/pid") 2>/dev/null
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
    fi
    rm -f "$dir/pid" "$dir/turns" "$dir/req" "$dir/resp" 2>/dev/null
    return 0
}

# Spawn the long-lived agy process. Returns as soon as it is launched: the
# first caller simply blocks on the response FIFO while agy authenticates.
_agy_daemon_start() {
    local model="$1"
    local dir=$(_agy_daemon_dir "$model")

    command -v agy &>/dev/null || return 1

    mkdir -p "$dir" 2>/dev/null || return 1
    chmod 700 "$AGY_DAEMON_RUNTIME_DIR" 2>/dev/null

    rm -f "$dir/req" "$dir/resp" 2>/dev/null
    mkfifo -m 600 "$dir/req" 2>/dev/null || return 1
    mkfifo -m 600 "$dir/resp" 2>/dev/null || return 1
    : > "$dir/turns"

    # cwd = the daemon dir, not the user's project: agy indexes its working
    # directory into the prompt, which costs both tokens and startup time.
    (
        cd "$dir" || exit 1
        # Drop the caller's lock fd before becoming agy (see above).
        if [[ -n "$_AGY_DAEMON_LOCK_FD" ]]; then
            { exec {_AGY_DAEMON_LOCK_FD}>&- } 2>/dev/null
        fi
        # Hold both FIFOs read-write inside the daemon itself: stdin never
        # reaches EOF (so agy keeps serving turns) and writes to the response
        # FIFO never block on a missing reader.
        exec 0<>"$dir/req"
        exec 1<>"$dir/resp"
        exec 2>>"$dir/agy.log"
        # `exec` so this subshell *becomes* agy and $! is agy's own pid.
        exec agy --input-format stream-json --output-format stream-json \
            --model "$model" --print-timeout "$AGY_DAEMON_TTL" --print=""
    ) &!

    print -r -- "$!" > "$dir/pid"
    return 0
}

_agy_daemon_ensure() {
    local model="$1"
    _agy_daemon_alive "$model" && return 0
    _agy_daemon_start "$model"
}

# Send one prompt to the daemon and print the response text.
# Usage: _agy_daemon_call PROMPT MODEL [TIMEOUT_SECS]
_agy_daemon_call() {
    local prompt="$1"
    local model="$2"
    local timeout_secs="${3:-30}"

    [[ "$AGY_DAEMON_ENABLED" == "false" ]] && return 1
    _agy_daemon_has_flock || return 1
    command -v jq &>/dev/null || return 1

    local dir=$(_agy_daemon_dir "$model")
    mkdir -p "$dir" 2>/dev/null || return 1

    # NB: every fd juggle goes through a { ... } 2>/dev/null block. A bare
    # `exec {fd}>file 2>/dev/null` would redirect *the shell's own* stderr for
    # good, silently swallowing every later diagnostic in the caller.
    local lockfd
    { exec {lockfd}>"$dir/lock" } 2>/dev/null || return 1
    if ! flock -w "$timeout_secs" "$lockfd" 2>/dev/null; then
        { exec {lockfd}>&- } 2>/dev/null
        return 1
    fi
    _AGY_DAEMON_LOCK_FD="$lockfd"

    _agy_daemon_ensure "$model" || {
        _AGY_DAEMON_LOCK_FD=""
        { exec {lockfd}>&- } 2>/dev/null
        return 1
    }

    local reqfd respfd
    if ! { exec {reqfd}<>"$dir/req" } 2>/dev/null; then
        _AGY_DAEMON_LOCK_FD=""
        { exec {lockfd}>&- } 2>/dev/null
        return 1
    fi
    if ! { exec {respfd}<>"$dir/resp" } 2>/dev/null; then
        _AGY_DAEMON_LOCK_FD=""
        { exec {reqfd}>&- } 2>/dev/null
        { exec {lockfd}>&- } 2>/dev/null
        return 1
    fi

    # Drop anything a previously interrupted client left in the stream.
    local junk
    while read -r -t 0 -u "$respfd" junk 2>/dev/null; do :; done

    local escaped=$(_ai_json_escape "$prompt")
    print -r -u "$reqfd" -- "{\"event\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"$escaped\"}}"

    # NB: `status` is a read-only alias of `?` in zsh -- never use it as a name.
    local line result="" agy_status="" rc=1
    while read -r -t "$timeout_secs" -u "$respfd" line 2>/dev/null; do
        [[ "$line" == *'"event":"result"'* ]] || continue
        agy_status=$(print -r -- "$line" | jq -r '.result.status // empty' 2>/dev/null)
        result=$(print -r -- "$line" | jq -r '.result.response // empty' 2>/dev/null)
        break
    done

    if [[ "$agy_status" == "SUCCESS" && -n "$result" ]]; then
        rc=0
    else
        # A timeout or a malformed reply leaves the stream out of sync with the
        # next request -- recycle the process rather than desync every caller.
        _agy_daemon_stop "$model"
    fi

    { exec {reqfd}>&- } 2>/dev/null
    { exec {respfd}>&- } 2>/dev/null

    # Recycle proactively once the conversation has grown, so the cost lands
    # here in the background instead of on the next user-visible call.
    if (( rc == 0 )); then
        local turns=0
        [[ -f "$dir/turns" ]] && turns=$(<"$dir/turns")
        (( turns = turns + 1 ))
        print -r -- "$turns" > "$dir/turns"
        if (( turns >= AGY_DAEMON_MAX_TURNS )); then
            _agy_daemon_stop "$model"
            _agy_daemon_start "$model" 2>/dev/null
        fi
    fi

    _AGY_DAEMON_LOCK_FD=""
    { exec {lockfd}>&- } 2>/dev/null

    (( rc == 0 )) && print -r -- "$result"
    return $rc
}

# Start the daemon ahead of the first real call, so the 5s cold start is not
# paid by the user's first inline suggestion. Non-blocking.
_agy_daemon_prewarm() {
    [[ "$AGY_DAEMON_ENABLED" == "false" ]] && return 0
    [[ "$AI_BACKEND" == "gemini" || -z "$AI_BACKEND" ]] || return 0
    [[ "$GEMINI_AUTH_MODE" == "cli" ]] || return 0
    command -v agy &>/dev/null || return 0
    local model="$GEMINI_CLI_MODEL"
    _agy_daemon_alive "$model" && return 0
    { _agy_daemon_start "$model" &>/dev/null } &!
    return 0
}

# =============================================================================
# User command
# =============================================================================

ai-daemon() {
    local action="${1:-status}"
    local model="$GEMINI_CLI_MODEL"
    local dir=$(_agy_daemon_dir "$model")

    case "$action" in
        status)
            if _agy_daemon_alive "$model"; then
                local turns=0
                [[ -f "$dir/turns" ]] && turns=$(<"$dir/turns")
                echo "agy daemon: running (pid $(<"$dir/pid"), model $model, $turns/$AGY_DAEMON_MAX_TURNS turns)"
            else
                echo "agy daemon: stopped (model $model)"
            fi
            ;;
        start)
            _agy_daemon_ensure "$model" && echo "agy daemon: started (model $model)" || echo "agy daemon: failed to start"
            ;;
        stop)
            _agy_daemon_stop "$model"
            echo "agy daemon: stopped"
            ;;
        restart)
            _agy_daemon_stop "$model"
            _agy_daemon_ensure "$model" && echo "agy daemon: restarted" || echo "agy daemon: failed to start"
            ;;
        logs)
            [[ -f "$dir/agy.log" ]] && tail -50 "$dir/agy.log" || echo "no log yet"
            ;;
        *)
            echo "Usage: ai-daemon [status|start|stop|restart|logs]"
            return 1
            ;;
    esac
}
