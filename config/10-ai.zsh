#!/usr/bin/env zsh
# =============================================================================
# AI-Powered Commands - Multi-Backend Integration
# =============================================================================
# Talks to the active AI backend (Gemini/OpenAI/Anthropic) via
# config/09-ai-core.zsh - no gemini-cli dependency for API-key mode.
# =============================================================================

# =============================================================================
# AI Help (always available)
# =============================================================================

aihelp() {
    local status_line

    if _ai_credentials_ok; then
        if [[ "$AI_BACKEND" == "gemini" && "$GEMINI_AUTH_MODE" == "cli" ]]; then
            status_line="✓ Antigravity CLI (agy) found"
        else
            status_line="✓ Configured"
        fi
    else
        if [[ "$AI_BACKEND" == "gemini" && "$GEMINI_AUTH_MODE" == "cli" ]]; then
            status_line="✗ Antigravity CLI (agy) not found"
        else
            status_line="✗ Not configured"
        fi
    fi

    # Use /bin/cat to bypass bat alias
    /bin/cat <<EOF
Nivuus AI Commands

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
  Creative terminal titles powered by AI
  Enable:  export ENABLE_AI_TERMINAL_TITLES=true
  Stats:   ai-title-stats
  Help:    ai-title-help

Configuration:
  Backend: $AI_BACKEND
  Model: $(_ai_resolve_model)
  Status: $status_line

Setup:
  Gemini:    export GOOGLE_API_KEY='...' (get one: https://aistudio.google.com/apikey)
             or export GEMINI_AUTH_MODE=cli (uses Antigravity CLI + your AI Pro/Ultra subscription)
  OpenAI:    export AI_BACKEND=openai OPENAI_API_KEY='...'
  Anthropic: export AI_BACKEND=anthropic ANTHROPIC_API_KEY='...'
EOF
}

# =============================================================================
# Check if the Gemini API key is configured
# =============================================================================

if ! _ai_credentials_ok; then
    # Provide setup instructions on first use
    _nivuus_ai_not_installed() {
        case "$AI_BACKEND" in
            openai)
                echo "⚠️  OPENAI_API_KEY not set"
                echo "Then: export OPENAI_API_KEY='your-api-key'"
                ;;
            anthropic)
                echo "⚠️  ANTHROPIC_API_KEY not set"
                echo "Then: export ANTHROPIC_API_KEY='your-api-key'"
                ;;
            gemini)
                if [[ "$GEMINI_AUTH_MODE" == "cli" ]]; then
                    echo "⚠️  Antigravity CLI (agy) not found"
                    echo "Install it, or set GEMINI_AUTH_MODE=api-key"
                else
                    echo "⚠️  GOOGLE_API_KEY not set"
                    echo "Get a key: https://aistudio.google.com/apikey"
                    echo "Then: export GOOGLE_API_KEY='your-api-key'"
                fi
                ;;
        esac
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
