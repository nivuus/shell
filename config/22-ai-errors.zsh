#!/usr/bin/env zsh
# =============================================================================
# AI Error Explanation System
# =============================================================================
# Analyzes command errors and provides AI-powered explanations
# Press Ctrl+E after an error to get intelligent help
# =============================================================================

# Skip if explicitly disabled or gemini-cli not available
[[ "${ENABLE_AI_ERROR_EXPLANATION:-true}" != "true" ]] && return

if ! command -v gemini &>/dev/null; then
    return
fi

# =============================================================================
# Configuration
# =============================================================================

: ${AI_ERROR_CACHE_DIR:="$HOME/.cache/nivuus-shell/ai-errors"}
: ${AI_ERROR_CACHE_TTL:=86400}  # 24 hours
: ${AI_ERROR_MODEL:="${GEMINI_MODEL:-gemini-1.5-flash}"}

# Create cache directory
mkdir -p "$AI_ERROR_CACHE_DIR"

# =============================================================================
# State Variables
# =============================================================================

typeset -g _AI_LAST_ERROR_CODE=0
typeset -g _AI_LAST_COMMAND=""
typeset -g _AI_LAST_ERROR_TIME=0
typeset -g _AI_ERROR_AVAILABLE=false
typeset -g _AI_CURRENT_DIR=""

# =============================================================================
# Cache Management
# =============================================================================

_ai_error_cache_key() {
    local cmd="$1"
    local exit_code="$2"
    local context="$3"

    # Create hash from command + exit code + context
    echo -n "${cmd}|${exit_code}|${context}" | md5sum | cut -d' ' -f1
}

_ai_error_cache_get() {
    local cache_key="$1"
    local cache_file="$AI_ERROR_CACHE_DIR/$cache_key"

    # Check if cache exists and is fresh
    if [[ -f "$cache_file" ]]; then
        local file_time=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
        local current_time=$(date +%s)

        if (( current_time - file_time < AI_ERROR_CACHE_TTL )); then
            cat "$cache_file"
            return 0
        fi
    fi

    return 1
}

_ai_error_cache_set() {
    local cache_key="$1"
    local content="$2"
    local cache_file="$AI_ERROR_CACHE_DIR/$cache_key"

    echo "$content" > "$cache_file"
}

# =============================================================================
# Context Detection
# =============================================================================

_ai_error_get_context() {
    local context=""

    # Detect project type
    if [[ -f "package.json" ]]; then
        context+="Node.js project"
    elif [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]]; then
        context+="Python project"
    elif [[ -f "Cargo.toml" ]]; then
        context+="Rust project"
    elif [[ -f "go.mod" ]]; then
        context+="Go project"
    fi

    # Git repository
    if git rev-parse --git-dir &>/dev/null; then
        [[ -n "$context" ]] && context+=", "
        context+="Git repository"
    fi

    # Docker
    if [[ -f "Dockerfile" ]] || [[ -f "docker-compose.yml" ]]; then
        [[ -n "$context" ]] && context+=", "
        context+="Docker project"
    fi

    echo "$context"
}

# =============================================================================
# Error Capture Hooks
# =============================================================================

_ai_error_preexec() {
    # Capture the command before execution
    _AI_LAST_COMMAND="$1"
    _AI_CURRENT_DIR="$PWD"
}

_ai_error_precmd() {
    # Capture the exit code after execution
    local exit_code=$?

    # Only track errors (non-zero exit codes)
    if (( exit_code != 0 )); then
        _AI_LAST_ERROR_CODE=$exit_code
        _AI_LAST_ERROR_TIME=$EPOCHSECONDS
        _AI_ERROR_AVAILABLE=true
    else
        _AI_ERROR_AVAILABLE=false
    fi
}

# =============================================================================
# AI Error Analysis
# =============================================================================

_ai_analyze_error() {
    local cmd="$1"
    local exit_code="$2"
    local context="$3"
    local current_dir="$4"

    # Build prompt for AI
    local prompt="You are a helpful command-line assistant. A user ran a command that failed.

Command: \`$cmd\`
Exit Code: $exit_code
Context: $context
Directory: $current_dir

Please provide:
1. A brief explanation of what likely went wrong (2-3 sentences)
2. The most common causes for this error (2-3 bullet points)
3. Suggested fixes (2-3 concrete commands or actions)

Keep your response concise, practical, and focused on actionable solutions.
Format your response in a clear, readable way suitable for terminal display."

    # Call gemini-cli
    gemini --model "$AI_ERROR_MODEL" ask "$prompt" 2>/dev/null
}

# =============================================================================
# Widget: Explain Last Error (Ctrl+E)
# =============================================================================

_ai_explain_error_widget() {
    # Check if error is available
    if [[ "$_AI_ERROR_AVAILABLE" != "true" ]]; then
        zle -M "No error to explain (last command succeeded)"
        return 0
    fi

    # Clear the current line and move to new line
    print ""
    print ""
    print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print -P "%F{167}⚠  AI Error Analysis%f"
    print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print ""
    print -P "%F{246}Command:%f $_AI_LAST_COMMAND"
    print -P "%F{246}Exit Code:%f $_AI_LAST_ERROR_CODE"
    print ""

    # Get context
    local context=$(_ai_error_get_context)

    # Generate cache key
    local cache_key=$(_ai_error_cache_key "$_AI_LAST_COMMAND" "$_AI_LAST_ERROR_CODE" "$context")

    # Check cache first
    local analysis=""
    if analysis=$(_ai_error_cache_get "$cache_key"); then
        print -P "%F{143}💾 From cache:%f"
        print ""
    else
        print -P "%F{110}🤖 Analyzing with AI...%f"
        print ""

        # Call AI
        analysis=$(_ai_analyze_error "$_AI_LAST_COMMAND" "$_AI_LAST_ERROR_CODE" "$context" "$_AI_CURRENT_DIR")

        # Cache the result
        if [[ -n "$analysis" ]]; then
            _ai_error_cache_set "$cache_key" "$analysis"
        fi
    fi

    # Display analysis
    if [[ -n "$analysis" ]]; then
        print "$analysis"
    else
        print -P "%F{167}Failed to analyze error. Is gemini-cli configured correctly?%f"
        print -P "%F{246}Run: gemini --help%f"
    fi

    print ""
    print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print ""

    # Redisplay prompt
    zle reset-prompt
}

# =============================================================================
# Manual Error Analysis Command
# =============================================================================

explain-error() {
    if [[ "$_AI_ERROR_AVAILABLE" != "true" ]]; then
        print -P "%F{167}⚠  No error to explain (last command succeeded)%f"
        return 1
    fi

    # Call the widget logic directly
    _ai_explain_error_widget
}

# Alias for convenience
alias ee='explain-error'

# =============================================================================
# Cache Management Commands
# =============================================================================

ai-error-clear-cache() {
    local count=$(ls -1 "$AI_ERROR_CACHE_DIR" 2>/dev/null | wc -l)
    rm -rf "$AI_ERROR_CACHE_DIR"/*
    mkdir -p "$AI_ERROR_CACHE_DIR"
    echo "✓ Cleared $count cached error explanations"
}

ai-error-stats() {
    local cache_count=$(ls -1 "$AI_ERROR_CACHE_DIR" 2>/dev/null | wc -l)
    local cache_size=$(du -sh "$AI_ERROR_CACHE_DIR" 2>/dev/null | cut -f1)

    echo "AI Error Explanation Statistics"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Cached explanations: $cache_count"
    echo "Cache size: $cache_size"
    echo "Cache TTL: ${AI_ERROR_CACHE_TTL}s ($(( AI_ERROR_CACHE_TTL / 3600 )) hours)"
    echo "Model: $AI_ERROR_MODEL"
    echo ""
    echo "Keybinding: Ctrl+E"
    echo "Command: explain-error (or 'ee')"
    echo ""

    if [[ "$_AI_ERROR_AVAILABLE" == "true" ]]; then
        echo "Last error: $_AI_LAST_COMMAND (exit code: $_AI_LAST_ERROR_CODE)"
        echo "Status: Ready for explanation"
    else
        echo "Status: No error to explain"
    fi
}

# =============================================================================
# Help
# =============================================================================

ai-error-help() {
    cat <<'EOF'
AI Error Explanation System

Automatically captures command errors and provides AI-powered explanations
and solutions.

USAGE:
  After a command fails, press Ctrl+E to get an AI analysis

  Or use commands:
    explain-error     Explain the last error
    ee                Short alias for explain-error

EXAMPLES:
  $ npm install
  Error: EACCES: permission denied

  [Press Ctrl+E]

  🤖 AI Analysis:
     This is a permission error. Don't use sudo with npm.

     Fixes:
     1. Fix npm permissions: npm config set prefix ~/.npm-global
     2. Or use nvm (already configured!)

CONFIGURATION:
  export ENABLE_AI_ERROR_EXPLANATION=false    # Disable feature
  export ENABLE_AI_ERROR_INDICATOR=false      # Hide ⚠ in RPROMPT
  export AI_ERROR_CACHE_TTL=86400             # Cache duration (seconds)
  export AI_ERROR_MODEL=gemini-1.5-flash      # Gemini model to use

CACHE MANAGEMENT:
  ai-error-clear-cache    Clear cached explanations
  ai-error-stats          Show statistics

NOTES:
  - Requires gemini-cli to be installed and configured
  - Errors are cached for 24 hours to avoid redundant API calls
  - Only non-zero exit codes are captured
  - The ⚠ indicator in RPROMPT shows when an error is available

EOF
}

# =============================================================================
# Setup
# =============================================================================

# Register hooks
autoload -U add-zsh-hook
add-zsh-hook preexec _ai_error_preexec
add-zsh-hook precmd _ai_error_precmd

# Register widget and keybinding
zle -N _ai_explain_error_widget
bindkey '^E' _ai_explain_error_widget
