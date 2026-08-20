#!/usr/bin/env zsh
# =============================================================================
# AI Core - Backend Dispatcher
# =============================================================================
# Routes AI calls to the active backend (gemini/openai/anthropic).
# Shared by config/10-ai.zsh, config/19-ai-suggestions.zsh,
# config/20-terminal-title.zsh and config/22-ai-errors.zsh.
# =============================================================================

typeset -g AI_BACKEND="${AI_BACKEND:-gemini}"

# Return the default model for the active backend, honoring per-backend
# overrides (GEMINI_MODEL / OPENAI_MODEL / ANTHROPIC_MODEL).
_ai_resolve_model() {
    case "$AI_BACKEND" in
        openai) print -r -- "${OPENAI_MODEL:-gpt-5.6-luna}" ;;
        anthropic) print -r -- "${ANTHROPIC_MODEL:-claude-haiku-4-5}" ;;
        *) print -r -- "${GEMINI_MODEL:-gemini-3.5-flash-lite}" ;;
    esac
}

# Escape a string for embedding in a JSON string value.
_ai_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/}"
    s="${s//$'\t'/\\t}"
    # Any remaining raw control characters (U+0000-U+001F) would produce
    # invalid JSON that jq rejects -- flatten them to a space.
    s="${s//[[:cntrl:]]/ }"
    print -r -- "$s"
}

# Return success if the active backend can actually make a call right now
# (an API key is configured, or -- for Gemini in cli mode -- agy is
# installed). Use this for gating features, instead of _ai_get_api_key
# directly, since _ai_get_api_key has no knowledge of GEMINI_AUTH_MODE.
_ai_credentials_ok() {
    if [[ "$AI_BACKEND" == "gemini" && "$GEMINI_AUTH_MODE" == "cli" ]]; then
        command -v agy &>/dev/null
        return $?
    fi
    _ai_get_api_key &>/dev/null
}

# Resolve the API key/credential for the active backend.
_ai_get_api_key() {
    case "$AI_BACKEND" in
        openai)
            [[ -n "$OPENAI_API_KEY" ]] || return 1
            print -r -- "$OPENAI_API_KEY"
            ;;
        anthropic)
            [[ -n "$ANTHROPIC_API_KEY" ]] || return 1
            print -r -- "$ANTHROPIC_API_KEY"
            ;;
        *)
            _ai_gemini_get_api_key
            ;;
    esac
}

# Call the active backend and print the response text.
# Usage: _ai_api_call PROMPT [MODEL] [MAX_TOKENS] [TEMPERATURE] [TIMEOUT_SECS]
_ai_api_call() {
    local prompt="$1"
    local model="${2:-$(_ai_resolve_model)}"
    local max_tokens="${3:-1024}"
    local temperature="${4:-0.3}"
    local timeout_secs="${5:-15}"

    case "$AI_BACKEND" in
        openai)
            _ai_backend_openai_call "$prompt" "$model" "$max_tokens" "$temperature" "$timeout_secs"
            ;;
        anthropic)
            _ai_backend_anthropic_call "$prompt" "$model" "$max_tokens" "$temperature" "$timeout_secs"
            ;;
        gemini)
            _ai_backend_gemini_call "$prompt" "$model" "$max_tokens" "$temperature" "$timeout_secs"
            ;;
        *)
            print -u2 -- "AI_BACKEND: unknown backend '$AI_BACKEND' (expected gemini, openai, or anthropic)"
            return 1
            ;;
    esac
}
