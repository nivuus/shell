#!/usr/bin/env zsh
# =============================================================================
# Nivuus Shell - Main Configuration
# =============================================================================
# Modern, fast, AI-powered ZSH shell with Nord theme
# Performance target: <300ms startup
# Last updated: January 2025
# =============================================================================

# Performance measurement
typeset -g NIVUUS_START_TIME=$EPOCHREALTIME

# =============================================================================
# Installation Directory
# =============================================================================

export NIVUUS_SHELL_DIR="${NIVUUS_SHELL_DIR:-$HOME/.nivuus-shell}"

# Development mode: use current directory if config exists
if [[ -f "${0:A:h}/config/00-core.zsh" ]]; then
    NIVUUS_SHELL_DIR="${0:A:h}"
fi

# =============================================================================
# Feature Toggles
# =============================================================================

export ENABLE_SYNTAX_HIGHLIGHTING="${ENABLE_SYNTAX_HIGHLIGHTING:-true}"
export ENABLE_PROJECT_DETECTION="${ENABLE_PROJECT_DETECTION:-true}"
export ENABLE_FIREBASE_PROMPT="${ENABLE_FIREBASE_PROMPT:-true}"
export ENABLE_AI_SUGGESTIONS="${ENABLE_AI_SUGGESTIONS:-true}"
export ENABLE_AI_TERMINAL_TITLES="${ENABLE_AI_TERMINAL_TITLES:-true}"
export GIT_PROMPT_CACHE_TTL="${GIT_PROMPT_CACHE_TTL:-2}"
export ENABLE_AI_AUTO_DEBOUNCE="${ENABLE_AI_AUTO_DEBOUNCE:-true}"
export AI_INLINE_MODE="${AI_INLINE_MODE:-true}"

# =============================================================================
# Theme & Prompt Configuration
# =============================================================================
# NIVUUS_THEME: name of a theme file in themes/ (or $NIVUUS_THEME_DIR) to load.
#   Built-in: nord (default), dracula.
# NIVUUS_THEME_DIR: extra directory to look up custom theme files in, e.g.
#   ~/.config/nivuus-shell/themes/<name>.zsh
# NIVUUS_THEME_FILE: explicit path to a theme file, takes priority over
#   NIVUUS_THEME/NIVUUS_THEME_DIR.
# NIVUUS_PROMPT_FORMAT / NIVUUS_RPROMPT_FORMAT: template strings for the left
#   and right prompt. Available tokens: {ssh} {root} {status} {path} {venv}
#   {cloud} {firebase} {git} {jobs}. See doc/PROMPT.md.
export NIVUUS_THEME="${NIVUUS_THEME:-nord}"
export NIVUUS_THEME_DIR="${NIVUUS_THEME_DIR:-$HOME/.config/nivuus-shell/themes}"
export NIVUUS_THEME_FILE="${NIVUUS_THEME_FILE:-}"
# NOTE: default templates use literal { } tokens, which zsh's ${VAR:-default}
# brace-matching mishandles when nested in double quotes — set them via a
# plain conditional assignment instead.
[[ -z "$NIVUUS_PROMPT_FORMAT" ]] && NIVUUS_PROMPT_FORMAT='{ssh}{root}{status} {path}{venv}{cloud}{firebase}{git} '
[[ -z "$NIVUUS_RPROMPT_FORMAT" ]] && NIVUUS_RPROMPT_FORMAT='{jobs}'
export NIVUUS_PROMPT_FORMAT NIVUUS_RPROMPT_FORMAT

# =============================================================================
# User Local Configuration (load BEFORE modules for environment variables)
# =============================================================================

[[ -f "$HOME/.zsh_local" ]] && source "$HOME/.zsh_local"

# =============================================================================
# Load Configuration Modules
# =============================================================================

typeset -a config_files
config_files=(
    00-core.zsh
    01-environment.zsh
    02-history.zsh
    03-completion.zsh
    04-keybindings.zsh
    05-prompt.zsh
    06-git.zsh
    07-navigation.zsh
    08-vim.zsh
    09-ai-core.zsh
    09-ai-backend-gemini.zsh
    09-ai-backend-openai.zsh
    09-ai-backend-anthropic.zsh
    09-nodejs.zsh
    09-python.zsh
    10-ai.zsh
    11-files.zsh
    12-network.zsh
    13-system.zsh
    14-functions.zsh
    15-aliases.zsh
    17-colorization.zsh
    18-autosuggestions.zsh
    19-ai-suggestions.zsh
    20-autoupdate.zsh
    20-terminal-title.zsh
    21-safety.zsh
    22-ai-errors.zsh
    23-terminal-sanity.zsh
    98-syntax.zsh
    99-cleanup.zsh
)

for config_file in $config_files; do
    config_path="$NIVUUS_SHELL_DIR/config/$config_file"
    [[ -f "$config_path" ]] && source "$config_path"
done

# =============================================================================
# Performance Report
# =============================================================================

if [[ -n "$EPOCHREALTIME" ]] && [[ -n "$NIVUUS_START_TIME" ]]; then
    typeset -g NIVUUS_END_TIME=$EPOCHREALTIME
    typeset -g NIVUUS_LOAD_TIME=$(( ($NIVUUS_END_TIME - $NIVUUS_START_TIME) * 1000 ))

    if (( ${NIVUUS_LOAD_TIME} > 500 )); then
        echo "⚠️  Nivuus Shell: slow startup ${NIVUUS_LOAD_TIME}ms (target: <300ms)"
    fi
fi
