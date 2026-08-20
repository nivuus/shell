#!/usr/bin/env zsh
# =============================================================================
# AI Backend - Anthropic
# =============================================================================
# Talks to the Anthropic Messages REST API.
# =============================================================================

_ai_backend_anthropic_call() {
    local prompt="$1"
    local model="${2:-${ANTHROPIC_MODEL:-claude-haiku-4-5}}"
    local max_tokens="${3:-1024}"
    local temperature="${4:-0.3}"
    local timeout_secs="${5:-15}"

    if ! command -v jq &>/dev/null; then
        print -u2 -- "The anthropic backend requires jq to parse API responses."
        return 1
    fi

    local api_key="$ANTHROPIC_API_KEY"
    [[ -z "$api_key" ]] && return 1

    local escaped_prompt=$(_ai_json_escape "$prompt")
    local json_payload="{\"model\":\"${model}\",\"max_tokens\":${max_tokens},\"temperature\":${temperature},\"messages\":[{\"role\":\"user\",\"content\":\"$escaped_prompt\"}]}"

    local api_response=$(timeout "$timeout_secs" curl -s -X POST "https://api.anthropic.com/v1/messages" \
        -H "x-api-key: ${api_key}" \
        -H "anthropic-version: 2023-06-01" \
        -H 'Content-Type: application/json' \
        -d "$json_payload" 2>/dev/null)

    [[ -z "$api_response" ]] && return 1

    local result=$(print -r -- "$api_response" | jq -r '.content[0].text // empty' 2>/dev/null)

    [[ -z "$result" ]] && return 1

    print -r -- "$result"
}
