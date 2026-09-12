#!/usr/bin/env zsh
# =============================================================================
# ZSH Autosuggestions - Nord Theme
# =============================================================================
# Inline command suggestions from history
# =============================================================================

# Only load once. The guard is deliberately not exported: an exported guard is
# inherited by every child shell, so `exec zsh` -- or any nested zsh -- would
# see it already set and silently skip this whole module.
[[ -n "${NIVUUS_AUTOSUGGESTIONS_LOADED}" ]] && return
typeset -g NIVUUS_AUTOSUGGESTIONS_LOADED=1

# Skip if explicitly disabled
[[ "${ENABLE_AUTOSUGGESTIONS:-true}" != "true" ]] && return

# =============================================================================
# Load zsh-autosuggestions
# =============================================================================

# Try common installation paths
typeset -a autosuggestions_paths
autosuggestions_paths=(
    /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    ~/.local/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
)

for autosuggestions_path in $autosuggestions_paths; do
    if [[ -f "$autosuggestions_path" ]]; then
        source "$autosuggestions_path"
        break
    fi
done

# Exit if not loaded
[[ -z "$ZSH_AUTOSUGGEST_STRATEGY" ]] && return

# =============================================================================
# Configuration
# =============================================================================

# Strategy: history first, then completion
# Note: AI suggestions are now handled via completion menu (config/19-ai-suggestions.zsh)
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# Use async mode for better performance
ZSH_AUTOSUGGEST_USE_ASYNC=true

# Buffer max size (characters)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20

# Manual rebind (faster startup)
ZSH_AUTOSUGGEST_MANUAL_REBIND=1

# Accept entire suggestion with Ctrl+Space or End key
bindkey '^ ' autosuggest-accept        # Ctrl+Space
bindkey '^[[F' autosuggest-accept      # End key
bindkey '\e[F' autosuggest-accept      # End key (alternative)

# Custom widget: accept one word from suggestion or move forward
_autosuggest_accept_word() {
    if [[ -n $POSTDISPLAY ]]; then
        # There's a suggestion - accept up to the next word boundary
        local suggestion="$POSTDISPLAY"
        local -i pos=1

        # Find the next word boundary (space or end)
        while [[ $pos -le ${#suggestion} ]] && [[ "${suggestion[$pos]}" != " " ]]; do
            (( pos++ ))
        done

        # Accept characters up to that position
        BUFFER="$BUFFER${suggestion[1,$pos]}"
        POSTDISPLAY="${suggestion[$((pos+1)),-1]}"
        CURSOR=${#BUFFER}
    else
        # No suggestion - just move forward one word
        zle forward-word
    fi
}

zle -N autosuggest-accept-word _autosuggest_accept_word

# Bind Ctrl+Right to accept one word from suggestion
bindkey '^[[1;5C' autosuggest-accept-word
bindkey '\e[1;5C' autosuggest-accept-word
bindkey '^[Oc' autosuggest-accept-word

# Clear suggestion with Ctrl+C (already default)
# bindkey '^C' autosuggest-clear

# Note: Up/Down arrows use default behavior (history navigation)
# AI suggestions are accessed via Tab key (see config/19-ai-suggestions.zsh)

# =============================================================================
# Nord Theme Colors
# =============================================================================

# Suggestion color (Nord3 - dim gray)
# Using ANSI 240 which maps to Nord3 (#4C566A)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=240'

# Alternative styles (uncomment to try):
# ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'              # Dimmer
# ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=240,italic'    # Italic dim
# ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=240,underline' # Underline dim

# =============================================================================
# Custom Widget for Better Integration
# =============================================================================

# Accept and execute suggestion immediately
_autosuggest_accept_and_execute() {
    if [[ -n $POSTDISPLAY ]]; then
        # Accept the suggestion
        BUFFER="$BUFFER$POSTDISPLAY"
        POSTDISPLAY=''
        # Add to history and execute
        print -s "$BUFFER"
        zle accept-line
    else
        # No suggestion, just execute
        zle accept-line
    fi
}

zle -N autosuggest-accept-and-execute _autosuggest_accept_and_execute

# Bind Ctrl+Enter to accept and execute (if terminal supports it)
bindkey '^J^M' autosuggest-accept-and-execute

# =============================================================================
# Performance Tuning
# =============================================================================

# Disable autosuggestions for large buffers (performance)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=50

# Ignore patterns (commands you don't want suggestions for)
ZSH_AUTOSUGGEST_COMPLETION_IGNORE='_*'

# History ignore patterns (don't suggest these from history)
ZSH_AUTOSUGGEST_HISTORY_IGNORE='?(#c50,)'  # Ignore very long commands (>50 chars)

# =============================================================================
# Help
# =============================================================================

autosuggestions_help() {
    /bin/cat <<'EOF'
ZSH Autosuggestions (Nord Theme)

As you type, suggestions appear in dim gray (Nord3)

Keybindings:
  →                  - Accept entire suggestion
  Ctrl+Space         - Accept entire suggestion
  End                - Accept entire suggestion
  Ctrl+→             - Accept next word
  Ctrl+C             - Clear suggestion

Configuration:
  Color:    fg=240 (Nord3 - dim gray)
  Strategy: history, then completion
  Async:    enabled for performance

Disable:
  export ENABLE_AUTOSUGGESTIONS=false

EOF
}
