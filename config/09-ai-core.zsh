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

# =============================================================================
# What leaves the machine
# =============================================================================

# Redact secrets from stdin before any of it is sent to an AI provider.
# Two kinds of rule:
#   - known shapes: a key=value / key: value whose key names a credential,
#     Authorization headers, and the fixed prefixes of common providers;
#   - any run of 32+ characters from [A-Za-z0-9_+-] holding both a digit and
#     a letter, which is what generated tokens look like. This one depends on
#     the value only, never on the words around it, so a secret is masked
#     whatever language the command line or its comments are written in.
# Text in any script (accented, CJK, RTL...) is left untouched: the shape rule
# only ever matches ASCII token characters.
_ai_redact() {
    setopt localoptions extendedglob
    local text MATCH MBEGIN MEND
    text=$(sed -E \
        -e 's/((api[_-]?key|token|secret|password|passwd|pwd|access[_-]?key|client[_-]?secret|authorization)[[:space:]]*[:=][[:space:]]*)[^[:space:]"'"'"']+/\1***REDACTED***/gI' \
        -e 's/(Bearer[[:space:]]+)[A-Za-z0-9._-]+/\1***REDACTED***/g' \
        -e 's/(gh[pousr]_)[A-Za-z0-9]+/\1***REDACTED***/g' \
        -e 's/(AKIA)[0-9A-Z]{12,}/\1***REDACTED***/g' \
        -e 's/(sk-)[A-Za-z0-9]{16,}/\1***REDACTED***/g')
    text=${text//(#m)[A-Za-z0-9_+-](#c32,)/${${${MATCH//[^0-9]/}:+${${MATCH//[^A-Za-z]/}:+***REDACTED***}}:-$MATCH}}
    print -r -- "$text"
}

# Quote $1 as a parameter of a curl configuration file (curl -K): inside
# double quotes, curl unescapes \\, \", \n, \r and \t.
_ai_curl_config_quote() {
    local v="${1//\\/\\\\}"
    v="${v//\"/\\\"}"
    v="${v//$'\n'/\\n}"
    v="${v//$'\r'/\\r}"
    v="${v//$'\t'/\\t}"
    print -r -- "\"$v\""
}

# POST JSON body $2 to URL $1 within $3 seconds, with extra headers $4...,
# and print the response. URL, headers and body reach curl as a
# configuration read from its standard input (-K -), never as arguments:
# the process table, readable by every local user, shows neither the API key
# nor the prompt.
_ai_http_post_json() {
    local url="$1" body="$2" timeout_secs="$3" header
    shift 3
    {
        print -r -- "url = $(_ai_curl_config_quote "$url")"
        for header in "$@" 'Content-Type: application/json'; do
            print -r -- "header = $(_ai_curl_config_quote "$header")"
        done
        print -r -- "data-binary = $(_ai_curl_config_quote "$body")"
    } | timeout "$timeout_secs" curl -s -X POST -K - 2>/dev/null
}

# Call the active backend and print the response text. Every backend call
# goes through here, so the prompt is redacted here and nowhere else can skip
# it.
# Usage: _ai_api_call PROMPT [MODEL] [MAX_TOKENS] [TEMPERATURE] [TIMEOUT_SECS]
_ai_api_call() {
    local prompt
    prompt=$(print -r -- "$1" | _ai_redact)
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

# =============================================================================
# Markdown Rendering Helper
# =============================================================================

# Detect the best available markdown renderer in order of preference:
# 1. $NIVUUS_MARKDOWN_RENDERER (explicit user override: glow/mdcat/rich/bat/batcat/cat)
# 2. glow (dedicated terminal markdown renderer)
# 3. mdcat (fast rust terminal markdown renderer)
# 4. python3 + rich (Python Rich markdown renderer)
# 5. bat / batcat (syntax-highlighted markdown)
# 6. cat (plain text fallback)
_nivuus_get_markdown_renderer() {
    if [[ -n "$NIVUUS_MARKDOWN_RENDERER" ]]; then
        print -r -- "$NIVUUS_MARKDOWN_RENDERER"
        return 0
    fi

    if [[ -n "$_NIVUUS_CACHED_MD_RENDERER" ]]; then
        print -r -- "$_NIVUUS_CACHED_MD_RENDERER"
        return 0
    fi

    local renderer="cat"
    if command -v glow &>/dev/null; then
        renderer="glow"
    elif command -v mdcat &>/dev/null; then
        renderer="mdcat"
    elif command -v python3 &>/dev/null && python3 -c 'import rich.markdown' &>/dev/null; then
        renderer="rich"
    elif command -v bat &>/dev/null; then
        renderer="bat"
    elif command -v batcat &>/dev/null; then
        renderer="batcat"
    fi

    typeset -g _NIVUUS_CACHED_MD_RENDERER="$renderer"
    print -r -- "$renderer"
}

# Render markdown formatted text or file in the terminal.
# Supports stdin, file argument, or string arguments.
_render_markdown() {
    # If rendering is disabled or terminal is dumb, output plain text.
    # When stdout is not a tty (pipe/redirect), default to plain text unless forced.
    if [[ "${ENABLE_MARKDOWN_RENDERING:-true}" == "false" || "$TERM" == "dumb" || ( ! -t 1 && "${FORCE_MARKDOWN_COLOR:-false}" != "true" ) ]]; then
        if [[ $# -gt 0 ]]; then
            if [[ -f "$1" && $# -eq 1 ]]; then
                /bin/cat "$1"
            else
                print -r -- "$*"
            fi
        else
            /bin/cat
        fi
        return $?
    fi

    local renderer=$(_nivuus_get_markdown_renderer)
    local bat_theme="${THEME_BAT_NAME:-Nord}"

    _pipe_to_renderer() {
        case "$renderer" in
            glow)
                glow -s auto --pager=false - 2>/dev/null || glow - 2>/dev/null || /bin/cat
                ;;
            mdcat)
                mdcat - 2>/dev/null || /bin/cat
                ;;
            rich)
                python3 -m rich.markdown -c -y - 2>/dev/null || /bin/cat
                ;;
            bat)
                bat -l markdown --style="${BAT_STYLE:-plain}" --theme="$bat_theme" --paging=never --color=always 2>/dev/null || /bin/cat
                ;;
            batcat)
                batcat -l markdown --style="${BAT_STYLE:-plain}" --theme="$bat_theme" --paging=never --color=always 2>/dev/null || /bin/cat
                ;;
            *)
                /bin/cat
                ;;
        esac
    }

    if [[ $# -gt 0 ]]; then
        if [[ -f "$1" && $# -eq 1 ]]; then
            case "$renderer" in
                glow)
                    glow -s auto --pager=false "$1" 2>/dev/null || glow "$1" 2>/dev/null || /bin/cat "$1"
                    ;;
                mdcat)
                    mdcat "$1" 2>/dev/null || /bin/cat "$1"
                    ;;
                rich)
                    python3 -m rich.markdown -c -y "$1" 2>/dev/null || /bin/cat "$1"
                    ;;
                bat)
                    bat -l markdown --style="${BAT_STYLE:-plain}" --theme="$bat_theme" --paging=never --color=always "$1" 2>/dev/null || /bin/cat "$1"
                    ;;
                batcat)
                    batcat -l markdown --style="${BAT_STYLE:-plain}" --theme="$bat_theme" --paging=never --color=always "$1" 2>/dev/null || /bin/cat "$1"
                    ;;
                *)
                    /bin/cat "$1"
                    ;;
            esac
        else
            print -r -- "$*" | _pipe_to_renderer
        fi
    else
        _pipe_to_renderer
    fi
}

# User helper to render markdown files or stdin in the terminal
mdview() {
    _render_markdown "$@"
}

# =============================================================================
# Charte Graphique Loader
# =============================================================================

# Charge lib/charte.sh a la demande, jamais au chargement du module : la
# cible de demarrage <300 ms de .zshrc ne doit rien payer pour une sortie
# qui n'apparait qu'en cas d'erreur. Partage entre config/22-ai-errors.zsh
# et config/24-ai-command-not-found.zsh.
_ai_charte_load() {
    local charte="${NIVUUS_SHELL_DIR:-$HOME/.nivuus-shell}/lib/charte.sh"
    [[ -f "$charte" ]] && source "$charte"
    return 0
}


