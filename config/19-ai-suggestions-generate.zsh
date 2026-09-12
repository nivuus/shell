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

# Redact obvious secrets before any context leaves the machine for the AI API.
# Masks API keys, tokens, passwords and Authorization headers on a line.
_ai_redact() {
    sed -E \
        -e 's/((api[_-]?key|token|secret|password|passwd|pwd|access[_-]?key|client[_-]?secret|authorization)[[:space:]]*[:=][[:space:]]*)[^[:space:]"'"'"']+/\1***REDACTED***/gI' \
        -e 's/(Bearer[[:space:]]+)[A-Za-z0-9._-]+/\1***REDACTED***/g' \
        -e 's/(gh[pousr]_)[A-Za-z0-9]+/\1***REDACTED***/g' \
        -e 's/(AKIA)[0-9A-Z]{12,}/\1***REDACTED***/g' \
        -e 's/(sk-)[A-Za-z0-9]{16,}/\1***REDACTED***/g'
}

_ai_get_context() {
    local context=""

    # Working directory
    context+="Dir: $PWD\n"

    # ALL files in current directory (limited to 50 to avoid huge repos)
    local files=$(ls -1 2>/dev/null | head -50 | tr '\n' ', ' | sed 's/,$//')
    [[ -n "$files" ]] && context+="Files (all): $files\n"

    # Recent command history (last 20 commands)
    local hist=$(fc -ln -25 2>/dev/null | sed 's/^[[:space:]]*//' | grep -v "^$" | tail -20 | tr '\n' ';')
    [[ -n "$hist" ]] && context+="Recent commands: $hist\n"

    # Environment variables
    context+="User: $USER\n"
    context+="Shell: $SHELL\n"
    context+="Home: $HOME\n"

    # Full PATH (truncated if too long)
    local path_truncated=$(echo "$PATH" | cut -c1-200)
    [[ ${#PATH} -gt 200 ]] && path_truncated="$path_truncated..."
    context+="PATH: $path_truncated\n"

    # Project type detection with file contents
    if [[ -f "package.json" ]]; then
        context+="Project: Node.js\n"
        local pkg_scripts=$(grep -A20 '"scripts"' package.json 2>/dev/null | head -25)
        [[ -n "$pkg_scripts" ]] && context+="package.json scripts:\n$pkg_scripts\n"
    fi

    if [[ -f "go.mod" ]]; then
        context+="Project: Go\n"
        local go_content=$(head -15 go.mod 2>/dev/null)
        [[ -n "$go_content" ]] && context+="go.mod:\n$go_content\n"
    fi

    if [[ -f "Cargo.toml" ]]; then
        context+="Project: Rust\n"
        local cargo_content=$(head -20 Cargo.toml 2>/dev/null)
        [[ -n "$cargo_content" ]] && context+="Cargo.toml:\n$cargo_content\n"
    fi

    if [[ -f "requirements.txt" ]]; then
        context+="Project: Python\n"
        local req_content=$(head -15 requirements.txt 2>/dev/null)
        [[ -n "$req_content" ]] && context+="requirements.txt:\n$req_content\n"
    fi

    # README preview
    if [[ -f "README.md" ]]; then
        local readme_preview=$(head -20 README.md 2>/dev/null)
        [[ -n "$readme_preview" ]] && context+="README.md preview:\n$readme_preview\n"
    fi

    # Git detailed status with diff
    if git rev-parse --git-dir &>/dev/null 2>&1; then
        local branch=$(git symbolic-ref --short HEAD 2>/dev/null)
        [[ -n "$branch" ]] && context+="Git branch: $branch\n"

        # Full git status
        local git_status=$(git status --short 2>/dev/null | head -30)
        [[ -n "$git_status" ]] && context+="Git status:\n$git_status\n"

        # Git diff of modified files (limited to 100 lines)
        local git_diff=$(git diff 2>/dev/null | head -100)
        [[ -n "$git_diff" ]] && context+="Git diff (first 100 lines):\n$git_diff\n"
    fi

    # Strip secrets before this context is sent to the AI provider.
    # (No -r: keep the historical behaviour of expanding the embedded \n.)
    print -- "$context" | _ai_redact
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

    local context=$(_ai_get_context)
    local prompt="You are a shell command autocompletion engine. The user has typed exactly this partial command: \"$prefix\"
Your output MUST be the full command and MUST start with exactly \"$prefix\" (same characters, same case). Do not suggest an unrelated command, even if the context below seems more relevant. Output ONLY the completed command, no explanation, no markdown.

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
    if [[ -n "$result" && "$result" != "$prefix"* ]]; then
        result=""
    fi

    if [[ -n "$result" ]]; then
        _AI_CACHE[$cache_key]="$result"
        _AI_CACHE_TIME[$cache_key]="$EPOCHSECONDS"
    fi

    print -r -- "$result"
}


# =============================================================================
