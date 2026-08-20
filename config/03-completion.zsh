#!/usr/bin/env zsh
# =============================================================================
# Completion System
# =============================================================================
# TRUE lazy loading - compinit loads on first TAB press
# =============================================================================

typeset -g ZCOMPDUMP="$HOME/.zcompdump"

# Lazy load compinit on first completion attempt
_nivuus_lazy_compinit() {
    # Load completion system
    autoload -Uz compinit

    # Only regenerate once per day
    if [[ -n "$ZCOMPDUMP"(#qN.mh+24) ]]; then
        compinit -d "$ZCOMPDUMP"
    else
        compinit -C -d "$ZCOMPDUMP"
    fi

    # Compile zcompdump if not already compiled (async)
    if [[ -s "$ZCOMPDUMP" && (! -s "${ZCOMPDUMP}.zwc" || "$ZCOMPDUMP" -nt "${ZCOMPDUMP}.zwc") ]]; then
        zcompile "$ZCOMPDUMP" &!
    fi

    # Apply completion styling
    _nivuus_setup_completion_styles

    # Rebind TAB to the real completion widget FIRST.
    # This prevents issues when this function is wrapped by syntax-highlighting,
    # and gives fzf-tab (below) the correct widget to capture as its fallback -
    # if fzf-tab loads while TAB is still bound to this lazy loader, it wraps
    # the wrong (about to be unfunctioned) widget and silently no-ops.
    bindkey '^I' expand-or-complete

    # Optional: fzf-tab (real multi-select on TAB inside the completion menu).
    # Only loaded if both fzf and the fzf-tab plugin are actually installed -
    # falls back silently to native zsh completion otherwise. Must run AFTER
    # the bindkey above: it takes over '^I' itself once loaded.
    _nivuus_load_fzf_tab

    # Remove this temporary function (safe now that TAB is rebound)
    unfunction _nivuus_lazy_compinit

    # Trigger whichever widget TAB now points to (fzf-tab-complete if loaded,
    # expand-or-complete otherwise) so the completion originally requested happens
    zle "${${$(bindkey '^I')##* }:-expand-or-complete}"
}

# Create widget for lazy loading
zle -N _nivuus_lazy_compinit

# Bind TAB to lazy loader (will be replaced after first use)
bindkey '^I' _nivuus_lazy_compinit

# =============================================================================
# Completion Options and Styling
# =============================================================================
# These are set immediately so they're ready when compinit loads

setopt ALWAYS_TO_END        # Move cursor to end after completion
setopt AUTO_MENU            # Show completion menu on tab
setopt COMPLETE_IN_WORD     # Complete from both ends of word
setopt NO_MENU_COMPLETE     # Don't autoselect first completion

# Function to apply completion styles (called after compinit loads)
_nivuus_setup_completion_styles() {
    # Case-insensitive completion
    zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

    # Use menu selection
    zstyle ':completion:*' menu select

    # Cache completions
    zstyle ':completion:*' use-cache on
    zstyle ':completion:*' cache-path "$HOME/.cache/zsh/completion"

    # Group matches
    zstyle ':completion:*' group-name ''
    zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
    zstyle ':completion:*:messages' format '%F{purple}-- %d --%f'
    zstyle ':completion:*:warnings' format '%F{red}-- no matches found --%f'

    # Colors in completion
    zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}

    # Process completion
    zstyle ':completion:*:*:*:*:processes' command "ps -u $USER -o pid,user,comm -w -w"
    zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'
}

# =============================================================================
# fzf-tab (optional) - real multi-select on TAB
# =============================================================================
# Native zsh menu-select can only complete one candidate at a time (TAB
# replaces the current word). fzf-tab replaces the completion menu with fzf,
# which supports toggling several candidates with TAB before accepting them
# all at once with Enter - e.g. `ls <TAB>` on several directories.
# Requires both `fzf` and the fzf-tab plugin to be installed; does nothing
# otherwise (native completion keeps working as before).
_nivuus_load_fzf_tab() {
    command -v fzf &>/dev/null || return

    typeset -a fzf_tab_paths
    fzf_tab_paths=(
        "$NIVUUS_SHELL_DIR/plugins/fzf-tab/fzf-tab.plugin.zsh"
        /usr/share/fzf-tab/fzf-tab.plugin.zsh
        /usr/local/share/fzf-tab/fzf-tab.plugin.zsh
        /opt/homebrew/share/fzf-tab/fzf-tab.plugin.zsh
        ~/.local/share/fzf-tab/fzf-tab.plugin.zsh
        ~/.zsh/fzf-tab/fzf-tab.plugin.zsh
    )

    local fzf_tab_path
    for fzf_tab_path in $fzf_tab_paths; do
        if [[ -f "$fzf_tab_path" ]]; then
            source "$fzf_tab_path"
            break
        fi
    done

    # Exit if not found/loaded
    (( $+functions[fzf-tab-complete] )) || return

    # fzf-tab draws its own popup; the native zstyle 'menu select' would
    # otherwise still try to render alongside it.
    zstyle ':completion:*' menu no

    # fzf-tab does NOT inherit FZF_DEFAULT_OPTS by default (unlike plain fzf) -
    # opt in explicitly so the popup picks up the Nord colors set in
    # config/17-colorization.zsh.
    zstyle ':fzf-tab:*' use-fzf-default-opts yes

    # Enable multi-select: TAB toggles a candidate, Enter accepts all
    # selected ones (e.g. multiple directories) onto the command line.
    zstyle ':fzf-tab:*' fzf-flags '--multi'

    # Preview directory contents while browsing candidates
    zstyle ':fzf-tab:complete:*:*' fzf-preview 'ls -1 --color=always $realpath 2>/dev/null'
}
