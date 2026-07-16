#!/usr/bin/env zsh
# =============================================================================
# AI-Powered Commands - Gemini CLI Integration
# =============================================================================
# Using gemini-cli for intelligent command assistance
# =============================================================================

# =============================================================================
# AI Help (always available)
# =============================================================================

aihelp() {
    local gemini_status
    if command -v gemini &>/dev/null; then
        gemini_status="✓ Installed"
    else
        gemini_status="✗ Not installed"
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
  Model: ${GEMINI_MODEL:-Global setting (from gemini /settings)}
  Status: $gemini_status

Setup:
  Install: npm install -g @google/gemini-cli
EOF
}

# =============================================================================
# Check if gemini is installed
# =============================================================================

if ! command -v gemini &>/dev/null; then
    # Provide installation instructions on first use
    _nivuus_ai_not_installed() {
        echo "⚠️  gemini not found"
        echo "Install: npm install -g @google/gemini-cli"
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
# Configuration
# =============================================================================

# export GEMINI_MODEL="${GEMINI_MODEL:-gemini-2.0-flash}"

# =============================================================================
# AI Command Functions
# =============================================================================

# Helper to get model flag
_ai_model_flag() {
    if [[ -n "$GEMINI_MODEL" ]]; then
        echo "--model $GEMINI_MODEL"
    fi
}

# General command suggestions
_nivuus_ai_suggest() {
    local query="$*"
    local model_flag=($(_ai_model_flag))
    if [[ -z "$query" ]]; then
        gemini "${model_flag[@]}" "Suggest useful zsh commands and shell tricks" 2>/dev/null
    else
        gemini "${model_flag[@]}" "Suggest zsh commands for: $query" 2>/dev/null
    fi
}

# Git-specific help
_nivuus_git_help() {
    local query="$*"
    local model_flag=($(_ai_model_flag))
    gemini "${model_flag[@]}" "Git command help: $query. Provide the exact command to run." 2>/dev/null
}

# GitHub CLI help
_nivuus_gh_help() {
    local query="$*"
    local model_flag=($(_ai_model_flag))
    gemini "${model_flag[@]}" "GitHub CLI (gh) help: $query. Provide the exact command to run." 2>/dev/null
}

# Explain a command
why() {
    local cmd="$*"
    local model_flag=($(_ai_model_flag))
    if [[ -z "$cmd" ]]; then
        echo "Usage: why <command>"
        echo "Example: why 'tar -xzf file.tar.gz'"
        return 1
    fi

    gemini "${model_flag[@]}" "Explain this command concisely: $cmd" 2>/dev/null
}

# Detailed explanation
explain() {
    local cmd="$*"
    local model_flag=($(_ai_model_flag))
    if [[ -z "$cmd" ]]; then
        echo "Usage: explain <command>"
        echo "Example: explain 'find . -name \"*.log\" -delete'"
        return 1
    fi

    gemini "${model_flag[@]}" "Provide a detailed explanation of this command, including each option: $cmd" 2>/dev/null
}

# General question
ask() {
    local question="$*"
    local model_flag=($(_ai_model_flag))
    if [[ -z "$question" ]]; then
        echo "Usage: ask <question>"
        echo "Example: ask 'how to compress a folder'"
        return 1
    fi

    gemini "${model_flag[@]}" "$question" 2>/dev/null
}

# =============================================================================
# Aliases - Disable glob expansion
# =============================================================================
# These must be defined AFTER the functions to avoid compilation errors

alias '??'='noglob _nivuus_ai_suggest'
alias '?git'='noglob _nivuus_git_help'
alias '?gh'='noglob _nivuus_gh_help'
