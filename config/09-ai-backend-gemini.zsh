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
        _ai_gemini_cli_call "$prompt" "$model" "$timeout_secs"
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
