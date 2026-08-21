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
    # Compile .zshrc if not already compiled or if source is newer.
    # Ce fichier appartient à l'utilisateur dans TOUS les modes : il est
    # compilé même en mode paquet.
    if [[ -f "$HOME/.zshrc" ]] && [[ (! -f "$HOME/.zshrc.zwc" || "$HOME/.zshrc" -nt "$HOME/.zshrc.zwc") ]]; then
        zcompile "$HOME/.zshrc" &>/dev/null
    fi

    # Bytecode de l'arbre Nivuus : DEUX conditions, et c'est délibéré.
    #
    #  - inscriptibilité : protège l'utilisateur normal, pour qui l'écriture
    #    sous /usr/share échouerait de toute façon en silence (&>/dev/null) ;
    #  - origine : protège le shell ROOT sur machine paquetée -- le cas où
    #    l'écriture RÉUSSIRAIT et laisserait des orphelins qu'apt purge ne
    #    nettoie pas. Le projet promet « aucune trace » : c'en serait une.
    #
    # Autonome : ce module peut être sourcé sans config/20-autoupdate.zsh
    # (tests, chargement partiel), donc il relit le marqueur lui-même quand
    # _nivuus_origin n'existe pas. Coût quand le marqueur est absent : un
    # [[ -r ]], sans fork.
    _nivuus_cleanup_owns_tree() {
        [[ -w "$NIVUUS_SHELL_DIR" ]] || return 1
        [[ -w "$NIVUUS_SHELL_DIR/config" ]] || return 1
        local origin
        if (( $+functions[_nivuus_origin] )); then
            origin="$(_nivuus_origin)"
        elif [[ -r "$NIVUUS_SHELL_DIR/.nivuus-origin" ]]; then
            origin="${$(sed -n 's/^origin=//p' "$NIVUUS_SHELL_DIR/.nivuus-origin" 2>/dev/null | head -n1):-source}"
        else
            origin=source
        fi
        [[ "$origin" != "package" ]]
    }

    if [[ -d "$NIVUUS_SHELL_DIR/config" ]] && _nivuus_cleanup_owns_tree; then
        for config_file in "$NIVUUS_SHELL_DIR"/config/*.zsh; do
            if [[ (! -f "${config_file}.zwc" || "$config_file" -nt "${config_file}.zwc") ]]; then
                { zcompile "$config_file" &>/dev/null } &!
            fi
        done
    fi

    # Compile .zsh_local if exists (domaine de l'utilisateur, tous modes).
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
export NIVUUS_SHELL_LOADED=1

# Export version
export NIVUUS_SHELL_VERSION="1.0.0"

# =============================================================================
# AI Daemon Prewarm
# =============================================================================
# In GEMINI_AUTH_MODE=cli, the first agy call pays ~5s of process startup while
# every later one costs ~1s (see config/09-ai-agy-daemon.zsh). Spawn the shared
# daemon in the background now so the user's first inline suggestion is fast.
# No-op when the daemon is disabled, agy is missing, or cli mode is off.
if [[ -o interactive ]] && (( $+functions[_agy_daemon_prewarm] )); then
    _agy_daemon_prewarm
fi

# =============================================================================
# AI Suggestions Integration
# =============================================================================
# AI suggestions now integrated with zsh-autosuggestions
# See config/19-ai-suggestions.zsh for Gemini custom strategy
# Keybindings configured in config/18-autosuggestions.zsh
