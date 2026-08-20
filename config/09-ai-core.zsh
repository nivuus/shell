#!/usr/bin/env zsh
# =============================================================================
# AI Core - Shared Gemini API Helper
# =============================================================================
# All AI features call the Gemini REST API directly (no gemini-cli dependency).
# Shared by config/10-ai.zsh, config/19-ai-suggestions.zsh,
# config/20-terminal-title.zsh and config/22-ai-errors.zsh.
# =============================================================================

typeset -g GEMINI_MODEL="${GEMINI_MODEL:-}"
typeset -g AI_DEFAULT_MODEL="${GEMINI_MODEL:-gemini-3.1-flash-lite}"

# Resolve the Google API key: explicit env var first, then fall back to the
# apiKey stored by a previously installed gemini-cli, for a smooth migration.
_ai_get_api_key() {
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

# Call the Gemini generateContent API and print the response text.
# Usage: _ai_api_call "$prompt" "$model" [max_tokens] [temperature] [timeout_secs]
_ai_api_call() {
    local prompt="$1"
    local model="${2:-$AI_DEFAULT_MODEL}"
    local max_tokens="${3:-1024}"
    local temperature="${4:-0.3}"
    local timeout_secs="${5:-15}"

    local api_key
    api_key=$(_ai_get_api_key) || return 1

    local api_url="https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${api_key}"

    # Build JSON payload (escape backslashes, quotes, then control chars, in that order)
    local escaped_prompt="${prompt//\\/\\\\}"
    escaped_prompt="${escaped_prompt//\"/\\\"}"
    escaped_prompt="${escaped_prompt//$'\n'/\\n}"
    escaped_prompt="${escaped_prompt//$'\r'/}"
    escaped_prompt="${escaped_prompt//$'\t'/\\t}"
    local json_payload="{\"contents\":[{\"parts\":[{\"text\":\"$escaped_prompt\"}]}],\"generationConfig\":{\"temperature\":${temperature},\"maxOutputTokens\":${max_tokens}}}"

    local api_response=$(timeout "$timeout_secs" curl -s -X POST "$api_url" \
        -H 'Content-Type: application/json' \
        -d "$json_payload" 2>/dev/null)

    [[ -z "$api_response" ]] && return 1

    # jq handles embedded quotes/escapes correctly; grep-based extraction
    # breaks as soon as the text itself contains a `"`.
    # Use `print -r --` (not `echo`) to feed the response through unmodified:
    # zsh's builtin `echo` expands backslash escapes (e.g. \n) by default,
    # which corrupts JSON strings containing literal `\n` sequences.
    local result=""
    if command -v jq &>/dev/null; then
        result=$(print -r -- "$api_response" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)
    else
        result=$(print -r -- "$api_response" | grep -o '"text"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/\\n/\n/g; s/\\"/"/g')
    fi

    [[ -z "$result" ]] && return 1

    print -r -- "$result"
}
