#!/usr/bin/env zsh
# =============================================================================
# AI Command Suggestions - Context and Generation
# =============================================================================
# Part of the AI suggestions module. Sourced by config/19-ai-suggestions.zsh,
# which is the entry point listed in .zshrc -- this file is not loaded on its
# own.
# =============================================================================

[[ -n "${NIVUUS_AI_SUGGESTIONS_GENERATE_LOADED}" ]] && return
typeset -g NIVUUS_AI_SUGGESTIONS_GENERATE_LOADED=1

# Cache of generated suggestions, keyed by prefix and directory.
typeset -gA _AI_CACHE
typeset -gA _AI_CACHE_TIME

# =============================================================================
# Context Collection
# =============================================================================

# Append "LABEL: VALUE" to the caller's $context, VALUE redacted. The
# labels are this code's; only the values come from the machine and the
# person, so only they go through _ai_redact_text (redacting the whole
# context would also hit `Git branch: main`, an assignment by its shape).
_ai_context_add() {
    local label=$1 value=$2 sep=${3:- }
    [[ -n "$value" ]] || return 0
    local REPLY
    _ai_redact_text "$value"
    context+="${label}:${sep}${REPLY}"$'\n'
}

_ai_get_context() {
    local context=""

    _ai_context_add "Dir" "$PWD"

    # ALL files in current directory (limited to 50 to avoid huge repos)
    _ai_context_add "Files (all)" "$(ls -1 2>/dev/null | head -50 | tr '\n' ',' | sed 's/,$//')"

    # Recent command history (last 20 commands)
    _ai_context_add "Recent commands" "$(fc -ln -25 2>/dev/null | sed 's/^[[:space:]]*//' | grep -v "^$" | tail -20 | tr '\n' ';')"

    # Environment variables
    _ai_context_add "User" "$USER"
    _ai_context_add "Shell" "$SHELL"
    _ai_context_add "Home" "$HOME"

    # Full PATH (truncated if too long)
    local REPLY
    _ai_truncate 200 "$PATH"
    [[ ${#PATH} -gt 200 ]] && REPLY+="..."
    _ai_context_add "PATH" "$REPLY"

    # Project type detection with file contents
    if [[ -f "package.json" ]]; then
        context+="Project: Node.js"$'\n'
        _ai_context_add "package.json scripts" "$(grep -A20 '"scripts"' package.json 2>/dev/null | head -25)" $'\n'
    fi

    if [[ -f "go.mod" ]]; then
        context+="Project: Go"$'\n'
        _ai_context_add "go.mod" "$(head -15 go.mod 2>/dev/null)" $'\n'
    fi

    if [[ -f "Cargo.toml" ]]; then
        context+="Project: Rust"$'\n'
        _ai_context_add "Cargo.toml" "$(head -20 Cargo.toml 2>/dev/null)" $'\n'
    fi

    if [[ -f "requirements.txt" ]]; then
        context+="Project: Python"$'\n'
        _ai_context_add "requirements.txt" "$(head -15 requirements.txt 2>/dev/null)" $'\n'
    fi

    # README preview
    if [[ -f "README.md" ]]; then
        _ai_context_add "README.md preview" "$(head -20 README.md 2>/dev/null)" $'\n'
    fi

    # Git detailed status with diff
    if git rev-parse --git-dir &>/dev/null 2>&1; then
        _ai_context_add "Git branch" "$(git symbolic-ref --short HEAD 2>/dev/null)"
        _ai_context_add "Git status" "$(git status --short 2>/dev/null | head -30)" $'\n'
        _ai_context_add "Git diff (first 100 lines)" "$(git diff 2>/dev/null | head -100)" $'\n'
    fi

    print -r -- "$context"
}

# =============================================================================
# Generate AI Suggestions
# =============================================================================

_ai_generate() {
    local prefix="$1"
    local cache_key="${prefix}_${PWD}"

    # Check credentials for the active backend
    if ! _ai_credentials_ok; then
        case "$AI_BACKEND" in
            openai) echo "ERROR: OPENAI_API_KEY not set. Run 'aihelp' for setup instructions." >&2 ;;
            anthropic) echo "ERROR: ANTHROPIC_API_KEY not set. Run 'aihelp' for setup instructions." >&2 ;;
            gemini)
                if [[ "$GEMINI_AUTH_MODE" == "cli" ]]; then
                    echo "ERROR: Antigravity CLI (agy) not found. Install it, or set GEMINI_AUTH_MODE=api-key. Run 'aihelp' for setup instructions." >&2
                else
                    echo "ERROR: GOOGLE_API_KEY not set. Run 'aihelp' for setup instructions." >&2
                fi
                ;;
        esac
        return 1
    fi

    # Check cache (5min TTL)
    if [[ -n "${_AI_CACHE_TIME[$cache_key]}" ]]; then
        local age=$(( EPOCHSECONDS - _AI_CACHE_TIME[$cache_key] ))
        if (( age < 300 )); then
            echo "${_AI_CACHE[$cache_key]}"
            return
        fi
    fi

    # Inline mode always generates 1 suggestion for speed
    local num_suggestions=1

    # The model sees the partial command redacted; what it returns starts
    # with that redacted text, which is put back to what was typed below. The
    # secret never leaves, and the suggestion still extends the real line.
    local REPLY
    _ai_redact_text "$prefix"
    local sent_prefix=$REPLY

    local context=$(_ai_get_context)
    local prompt="You are a shell command autocompletion engine. The user has typed exactly this partial command: \"$sent_prefix\"
Your output MUST be the full command and MUST start with exactly \"$sent_prefix\" (same characters, same case). Do not suggest an unrelated command, even if the context below seems more relevant. Output ONLY the completed command, no explanation, no markdown.

Context (background reference only, does not override the partial command above):
$context"

    # Call the active backend. 15s (not 5s) because GEMINI_AUTH_MODE=cli routes
    # through the agy CLI, which has ~3s of fixed process-startup overhead on
    # top of the actual generation time -- a 5s budget made every inline
    # suggestion time out/get canceled once cli mode became the default.
    local result=$(_ai_api_call "$prompt" "$AI_SUGGESTION_MODEL" 60 0.3 15)

    # Keep first non-empty line, strip wrapping backticks/quotes
    result=$(print -r -- "$result" | grep -v '^[[:space:]]*$' | head -1 | \
        sed 's/^`\(.*\)`$/\1/' | \
        sed 's/^"\(.*\)"$/\1/')

    # Reject completions that don't actually extend what the user typed
    # (the model sometimes ignores the partial and free-associates from context)
    if [[ -n "$result" && "$result" == "$sent_prefix"* ]]; then
        result=$prefix${result#"$sent_prefix"}
    else
        result=""
    fi

    if [[ -n "$result" ]]; then
        _AI_CACHE[$cache_key]="$result"
        _AI_CACHE_TIME[$cache_key]="$EPOCHSECONDS"
    fi

    print -r -- "$result"
}


# =============================================================================
