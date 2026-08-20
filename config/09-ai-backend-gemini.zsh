#!/usr/bin/env zsh
# =============================================================================
# AI Backend - Gemini
# =============================================================================
# Talks to the Gemini REST API directly. When GEMINI_AUTH_MODE=cli, shells
# out to Antigravity CLI (agy) instead, to spend a Google AI Pro/Ultra
# subscription's quota rather than a metered API key.
# =============================================================================

typeset -g GEMINI_AUTH_MODE="${GEMINI_AUTH_MODE:-api-key}"

# Resolve the Google API key: explicit env var first, then fall back to the
# apiKey stored by a previously installed gemini-cli, for a smooth migration.
_ai_gemini_get_api_key() {
    if [[ -n "$GOOGLE_API_KEY" ]]; then
        print -r -- "$GOOGLE_API_KEY"
        return 0
    fi

    local config_file="$HOME/.gemini-cli/config.json"
    if [[ -f "$config_file" ]]; then
        local key=$(grep -o '"apiKey"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | cut -d'"' -f4)
        if [[ -n "$key" ]]; then
            print -r -- "$key"
            return 0
        fi
    fi

    return 1
}

_ai_backend_gemini_call() {
    local prompt="$1"
    local model="${2:-${GEMINI_MODEL:-gemini-3.5-flash-lite}}"
    local max_tokens="${3:-1024}"
    local temperature="${4:-0.3}"
    local timeout_secs="${5:-15}"

    if [[ "$GEMINI_AUTH_MODE" == "cli" ]]; then
        # Antigravity CLI uses its own model slugs (e.g. "gemini-3.5-flash-medium"),
        # not the Generative Language API's model IDs (e.g. "gemini-3.5-flash-lite") —
        # the two are not interchangeable, so cli mode gets its own override var.
        #
        # "-medium"/"-high" tiers run agy as a full agentic session: it tries to
        # read files and shell out to explore context instead of just answering,
        # which takes 7-15s and often fails outright with a permission-check
        # error the moment it attempts a tool call. The "-low" tier answers
        # directly in a single turn, so it's the only tier fit for a synchronous
        # shell helper (inline suggestions, chat, titles, error explain).
        _ai_gemini_cli_call "$prompt" "${GEMINI_CLI_MODEL:-gemini-3.5-flash-low}" "$timeout_secs"
        return $?
    fi

    local api_key
    api_key=$(_ai_gemini_get_api_key) || return 1

    local api_url="https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${api_key}"
    local escaped_prompt=$(_ai_json_escape "$prompt")
    local json_payload="{\"contents\":[{\"parts\":[{\"text\":\"$escaped_prompt\"}]}],\"generationConfig\":{\"temperature\":${temperature},\"maxOutputTokens\":${max_tokens}}}"

    local api_response=$(timeout "$timeout_secs" curl -s -X POST "$api_url" \
        -H 'Content-Type: application/json' \
        -d "$json_payload" 2>/dev/null)

    [[ -z "$api_response" ]] && return 1

    # jq handles embedded quotes/escapes correctly; grep-based extraction
    # breaks as soon as the text itself contains a `"`.
    local result=""
    if command -v jq &>/dev/null; then
        result=$(print -r -- "$api_response" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)
    else
        result=$(print -r -- "$api_response" | grep -o '"text"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/\\n/\n/g; s/\\"/"/g')
    fi

    [[ -z "$result" ]] && return 1

    print -r -- "$result"
}

# Shell out to Antigravity CLI (agy) to spend a Google AI Pro/Ultra
# subscription's quota instead of a metered API key. agy owns its own
# OAuth session (one-time interactive `agy` login, cached credentials) —
# no OAuth code lives in this repo. gemini-cli was discontinued for
# subscription/free-tier accounts on 2026-06-18; agy is its replacement.
_ai_gemini_cli_call() {
    local prompt="$1"
    local model="$2"
    local timeout_secs="$3"

    if ! command -v agy &>/dev/null; then
        print -u2 -- "GEMINI_AUTH_MODE=cli but 'agy' (Antigravity CLI) is not installed. Install it, or set GEMINI_AUTH_MODE=api-key."
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        print -u2 -- "GEMINI_AUTH_MODE=cli requires jq to parse the agy JSON response."
        return 1
    fi

    # Fast path: a persistent agy process (see config/09-ai-agy-daemon.zsh)
    # skips the 3-6s of per-process startup a one-shot `agy -p` pays. Any
    # failure (daemon disabled, no flock, unwritable runtime dir, timeout)
    # falls through to the one-shot call below.
    if [[ "$AGY_DAEMON_ENABLED" != "false" ]] && (( $+functions[_agy_daemon_call] )); then
        local daemon_result
        if daemon_result=$(_agy_daemon_call "$prompt" "$model" "$timeout_secs"); then
            print -r -- "$daemon_result"
            return 0
        fi
    fi

    # agy indexes its working directory. Running it from the user's project
    # costs ~1s of wall clock per call (6.4s vs 5.4s median, measured) for
    # context none of our prompts use, so the one-shot call runs from an empty
    # scratch directory -- the same trick the daemon uses. Falls back to the
    # current directory if that scratch dir cannot be created.
    local workspace="${AGY_DAEMON_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}/nivuus-agy-${UID}}/workspace"
    mkdir -p "$workspace" 2>/dev/null || workspace="$PWD"

    local cli_response
    cli_response=$(cd "$workspace" && timeout "$timeout_secs" agy -p "$prompt" --model "$model" \
        --output-format json --print-timeout "${timeout_secs}s" 2>/dev/null)

    if [[ -z "$cli_response" ]]; then
        print -u2 -- "agy produced no output (timeout, network failure, or not logged in — run 'agy' interactively once to sign in)."
        return 1
    fi

    local agy_status
    agy_status=$(print -r -- "$cli_response" | jq -r '.status // empty' 2>/dev/null)

    if [[ "$agy_status" != "SUCCESS" ]]; then
        local agy_error
        agy_error=$(print -r -- "$cli_response" | jq -r '.error // empty' 2>/dev/null)
        print -u2 -- "agy call failed (status: ${agy_status:-unknown})${agy_error:+: $agy_error}"
        return 1
    fi

    local result
    result=$(print -r -- "$cli_response" | jq -r '.response // empty' 2>/dev/null)

    [[ -z "$result" ]] && return 1

    print -r -- "$result"
}
