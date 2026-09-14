#!/usr/bin/env zsh
# =============================================================================
# Smart Navigation
# =============================================================================
# History prefix filtering + directory shortcuts
# =============================================================================

# =============================================================================
# History Prefix Search
# =============================================================================

# Load history search widgets
autoload -U up-line-or-beginning-search
autoload -U down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search

# Bind arrow keys to prefix search
bindkey '^[[A' up-line-or-beginning-search      # Up arrow
bindkey '^[[B' down-line-or-beginning-search    # Down arrow
bindkey '^P' up-line-or-beginning-search        # Ctrl+P
bindkey '^N' down-line-or-beginning-search      # Ctrl+N

# =============================================================================
# Directory Shortcuts
# =============================================================================

# Go up directories
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

# Directory stack navigation
alias d='dirs -v'

# Quick jump to directories in stack
for i in {1..5}; do
    alias "$i"="cd -${i}"
done

# =============================================================================
# Enhanced cd
# =============================================================================

# Auto-ls after cd.
#
# chpwd hooks fire in non-interactive shells too, so a script or an agent that
# changes directory would get an unasked-for listing on stdout. Show it only
# when someone is there to read it.
#
# `command ls` is deliberate: zsh expands aliases when it parses a function
# body, so a bare `ls` here used to be frozen into whatever eza alias happened
# to be defined first — which also made the two fallbacks below unreachable,
# since all three branches ended up calling the same binary.
chpwd() {
    emulate -L zsh
    nivuus_has_terminal || return
    command ls --color=auto 2>/dev/null || command ls -G 2>/dev/null || command ls
}
