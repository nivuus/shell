#!/usr/bin/env zsh
# =============================================================================
# AI-Powered Commands - Gemini API Integration
# =============================================================================
# Talks directly to the Gemini REST API (no gemini-cli dependency)
# =============================================================================

# =============================================================================
# AI Help (always available)
# =============================================================================

aihelp() {
    local key_status
    if _ai_get_api_key &>/dev/null; then
        key_status="✓ Configured"
    else
        key_status="✗ Not configured"
    fi

    # Use /bin/cat to bypass bat alias
    /bin/cat <<EOF
Nivuus AI Commands (powered by Gemini)

General:
  ??                     - Get command suggestions
  ?? "find large files"  - Ask for specific task

Git:
  ?git "undo commit"     - Git-specific help
  ?gh "create repo"      - GitHub CLI help

Explain:
  why "tar -xzf file"    - Quick explanation
  explain "complex cmd"  - Detailed breakdown
  ask "how to compress"  - General question

AI Suggestions (Interactive):
  Manual:  Ctrl+↓ or Ctrl+2 - Show AI menu
  Auto:    export ENABLE_AI_AUTO_DEBOUNCE=true
  Delay:   Menu appears after 2s of inactivity
  Help:    ai_suggestions_help

AI Terminal Titles:
  Creative terminal titles powered by Gemini
  Enable:  export ENABLE_AI_TERMINAL_TITLES=true
  Stats:   ai-title-stats
  Help:    ai-title-help

Configuration:
  Model: $(_ai_resolve_model)
  API key: $key_status

Setup:
  Get a key: https://aistudio.google.com/apikey
  export GOOGLE_API_KEY='your-api-key'
EOF
}

# =============================================================================
# Check if the Gemini API key is configured
# =============================================================================

if ! _ai_get_api_key &>/dev/null; then
    # Provide setup instructions on first use
    _nivuus_ai_not_installed() {
        echo "⚠️  GOOGLE_API_KEY not set"
        echo "Get a key: https://aistudio.google.com/apikey"
        echo "Then: export GOOGLE_API_KEY='your-api-key'"
        echo ""
        echo "Run 'aihelp' for more information"
        return 1
    }

    # Use functions instead of aliases to avoid glob expansion issues
    why() { _nivuus_ai_not_installed }
    explain() { _nivuus_ai_not_installed }
    ask() { _nivuus_ai_not_installed }

    # Special handling for ?? to avoid glob issues
    setopt LOCAL_OPTIONS
    setopt NO_NOMATCH
    alias '??'='noglob _nivuus_ai_not_installed'
    return
fi

# =============================================================================
# AI Command Functions
# =============================================================================

# General command suggestions
_nivuus_ai_suggest() {
    local query="$*"
    if [[ -z "$query" ]]; then
        _ai_api_call "Suggest useful zsh commands and shell tricks"
    else
        _ai_api_call "Suggest zsh commands for: $query"
    fi
}

# Git-specific help
_nivuus_git_help() {
    local query="$*"
    _ai_api_call "Git command help: $query. Provide the exact command to run."
}

# GitHub CLI help
_nivuus_gh_help() {
    local query="$*"
    _ai_api_call "GitHub CLI (gh) help: $query. Provide the exact command to run."
}

# Explain a command
why() {
    local cmd="$*"
    if [[ -z "$cmd" ]]; then
        echo "Usage: why <command>"
        echo "Example: why 'tar -xzf file.tar.gz'"
        return 1
    fi

    _ai_api_call "Explain this command concisely: $cmd"
}

# Detailed explanation
explain() {
    local cmd="$*"
    if [[ -z "$cmd" ]]; then
        echo "Usage: explain <command>"
        echo "Example: explain 'find . -name \"*.log\" -delete'"
        return 1
    fi

    _ai_api_call "Provide a detailed explanation of this command, including each option: $cmd"
}

# General question
ask() {
    local question="$*"
    if [[ -z "$question" ]]; then
        echo "Usage: ask <question>"
        echo "Example: ask 'how to compress a folder'"
        return 1
    fi

    _ai_api_call "$question"
}

# =============================================================================
# Aliases - Disable glob expansion
# =============================================================================
# These must be defined AFTER the functions to avoid compilation errors

alias '??'='noglob _nivuus_ai_suggest'
alias '?git'='noglob _nivuus_git_help'
alias '?gh'='noglob _nivuus_gh_help'
