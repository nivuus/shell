#!/usr/bin/env zsh
# =============================================================================
# Cleanup & Finalization
# =============================================================================
# Final setup and optimizations
# =============================================================================

# =============================================================================
# Rehash Command Hash Table
# =============================================================================

# Rebuild command hash table for faster command lookup
rehash

# =============================================================================
# Compile ZSH Files for Faster Loading
# =============================================================================

# Skip compilation in dev mode for faster iteration
if [[ "${NIVUUS_NO_COMPILE:-0}" != "1" ]]; then
    # Compile .zshrc if not already compiled or if source is newer
    if [[ -f "$HOME/.zshrc" ]] && [[ (! -f "$HOME/.zshrc.zwc" || "$HOME/.zshrc" -nt "$HOME/.zshrc.zwc") ]]; then
        zcompile "$HOME/.zshrc" &>/dev/null
    fi

    # Compile config files for faster loading
    if [[ -d "$NIVUUS_SHELL_DIR/config" ]]; then
        for config_file in "$NIVUUS_SHELL_DIR"/config/*.zsh; do
            if [[ (! -f "${config_file}.zwc" || "$config_file" -nt "${config_file}.zwc") ]]; then
                { zcompile "$config_file" &>/dev/null } &!
            fi
        done
    fi

    # Compile .zsh_local if exists
    if [[ -f "$HOME/.zsh_local" ]] && [[ (! -f "$HOME/.zsh_local.zwc" || "$HOME/.zsh_local" -nt "$HOME/.zsh_local.zwc") ]]; then
        zcompile "$HOME/.zsh_local" &>/dev/null
    fi
fi

# =============================================================================
# Environment Cleanup
# =============================================================================

# Remove duplicate PATH entries
typeset -U path
export PATH

# Remove duplicate FPATH entries
typeset -U fpath
export FPATH

# =============================================================================
# Welcome Message (Optional)
# =============================================================================

# Show welcome message on first shell of the session (terminal)
_show_welcome_message() {
    # Check if this is a new terminal session (not a subshell)
    if [[ -z "$NIVUUS_SESSION_SHOWN" ]] && [[ "$SHLVL" -eq 1 ]]; then
        export NIVUUS_SESSION_SHOWN=1

        # Only show if load time is available and good
        if [[ -n "$NIVUUS_LOAD_TIME" ]] && (( NIVUUS_LOAD_TIME < 500 )); then
            echo "✓ Nivuus Shell loaded in ${NIVUUS_LOAD_TIME}ms"
        fi

        # Show helpful tip occasionally (1 in 5 chance)
        if (( RANDOM % 5 == 0 )); then
            local tips=(
                "Tip: Use '??' to get AI-powered command suggestions"
                "Tip: Type 'aihelp' to see all AI commands"
                "Tip: Use '↑' with a prefix to search history"
                "Tip: Run 'healthcheck' to verify your setup"
                "Tip: Edit with 'vedit <file>' for modern vim shortcuts (Ctrl+C/V)"
                "Tip: Type 'vim_help' to see modern vim shortcuts"
            )
            echo "${tips[RANDOM % ${#tips[@]} + 1]}"
        fi
    fi
}

# Show welcome message (async, non-blocking)
(_show_welcome_message &)

# =============================================================================
# Performance Monitoring
# =============================================================================

# Warn if load time is slow
if [[ -n "$NIVUUS_LOAD_TIME" ]] && (( NIVUUS_LOAD_TIME > 500 )); then
    echo "⚠️  Shell loaded slowly (${NIVUUS_LOAD_TIME}ms). Consider:"
    echo "   - export ENABLE_SYNTAX_HIGHLIGHTING=false"
    echo "   - export ENABLE_PROJECT_DETECTION=false"
    echo "   - export ENABLE_FIREBASE_PROMPT=false"
fi

# =============================================================================
# Error Handling
# =============================================================================

# Disable core dumps (security)
ulimit -c 0

# =============================================================================
# Final Exports
# =============================================================================

# Mark shell as fully loaded
typeset -g NIVUUS_SHELL_LOADED=1

# Export version
export NIVUUS_SHELL_VERSION="1.0.0"

# =============================================================================
# AI Daemon Prewarm
# =============================================================================
# In GEMINI_AUTH_MODE=cli, the first agy call pays ~5s of process startup while
# every later one costs ~1s (see config/09-ai-agy-daemon.zsh). Spawn the shared
# daemon in the background now so the user's first inline suggestion is fast.
# No-op when the daemon is disabled, agy is missing, or cli mode is off.
# Terminal only: nothing but a human types the inline suggestion this warms up,
# so an agent or CI shell would pay for a daemon it never queries.
if nivuus_has_terminal && (( $+functions[_agy_daemon_prewarm] )); then
    _agy_daemon_prewarm
fi

# =============================================================================
# AI Suggestions Integration
# =============================================================================
# AI suggestions now integrated with zsh-autosuggestions
# See config/19-ai-suggestions.zsh for Gemini custom strategy
# Keybindings configured in config/18-autosuggestions.zsh
