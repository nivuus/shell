#!/usr/bin/env zsh
# =============================================================================
# AI Backend - OpenAI
# =============================================================================
# Talks to the OpenAI Chat Completions REST API.
# =============================================================================

_ai_backend_openai_call() {
    local prompt="$1"
    local model="${2:-${OPENAI_MODEL:-gpt-5.6-luna}}"
    local max_tokens="${3:-1024}"
    local temperature="${4:-0.3}"
    local timeout_secs="${5:-15}"

    if ! command -v jq &>/dev/null; then
        print -u2 -- "The openai backend requires jq to parse API responses."
        return 1
    fi

    local api_key="$OPENAI_API_KEY"
    [[ -z "$api_key" ]] && return 1

    local escaped_prompt=$(_ai_json_escape "$prompt")
    local json_payload="{\"model\":\"${model}\",\"messages\":[{\"role\":\"user\",\"content\":\"$escaped_prompt\"}],\"max_tokens\":${max_tokens},\"temperature\":${temperature}}"

    local api_response=$(timeout "$timeout_secs" curl -s -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Authorization: Bearer ${api_key}" \
        -H 'Content-Type: application/json' \
        -d "$json_payload" 2>/dev/null)

    [[ -z "$api_response" ]] && return 1

    local result=$(print -r -- "$api_response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)

    [[ -z "$result" ]] && return 1

    print -r -- "$result"
}
