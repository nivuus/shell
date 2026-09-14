#!/usr/bin/env zsh
# =============================================================================
# General Aliases
# =============================================================================
# Useful shortcuts and conveniences
# =============================================================================

# =============================================================================
# Navigation
# =============================================================================

alias -- -='cd -'                  # Go to previous directory
# Note: Cannot alias '~' as it's a reserved zsh token

# =============================================================================
# Safety
# =============================================================================

# Terminal only: -i blocks on a confirmation prompt nothing can answer in a
# script, cron job or agent shell, so the command fails or hangs silently.
# `[[ -o interactive ]]` does not express that — see nivuus_has_terminal.
if nivuus_has_terminal; then
    alias rm='rm -i'               # Confirm before removing
    alias cp='cp -i'               # Confirm before overwriting
    alias mv='mv -i'               # Confirm before overwriting
    alias ln='ln -i'               # Confirm before overwriting
fi

# =============================================================================
# Shortcuts
# =============================================================================

# Clear screen
alias c='clear'
alias cls='clear'

# Reload shell
alias reload='source ~/.zshrc'

# Edit config
alias zshconfig='$EDITOR ~/.zshrc'
alias zshlocal='$EDITOR ~/.zsh_local'

# History
alias h='history'
alias hg='history | grep'

# Jobs
alias j='jobs -l'

# =============================================================================
# System
# =============================================================================

# Sudo
alias please='sudo'
alias pls='sudo'

# Process management
alias psa='ps aux'
alias top='top -o cpu'

# Disk usage
alias df='df -h'
alias du='du -h'

# Free memory
if [[ "$OSTYPE" != "darwin"* ]]; then
    alias free='free -h'
fi

# =============================================================================
# Listing
# =============================================================================

# List listening ports.
#
# A function, not an alias: as a `||` chain in an alias, `listening | grep 443`
# piped only the last branch, and the trailing `2>/dev/null` meant that when
# none of the three tools was installed the command printed nothing at all and
# looked like "no ports are listening". The last fallback now reports why it
# failed.
listening() {
    lsof -iTCP -sTCP:LISTEN -n -P 2>/dev/null \
        || ss -tulpn 2>/dev/null \
        || netstat -tulpn
}

# =============================================================================
# Date/Time
# =============================================================================

alias now='date +"%Y-%m-%d %H:%M:%S"'
alias timestamp='date +%s'
alias isodate='date -u +"%Y-%m-%dT%H:%M:%SZ"'

# =============================================================================
# Text Processing
# =============================================================================

# Copy/paste clipboard (Wayland > X11 > macOS)
if command -v wl-copy &>/dev/null; then
    alias clip='wl-copy'
    alias paste='wl-paste'
elif command -v xclip &>/dev/null; then
    alias clip='xclip -selection clipboard'
    alias paste='xclip -selection clipboard -o'
elif command -v pbcopy &>/dev/null; then
    alias clip='pbcopy'
    alias paste='pbpaste'
fi

# =============================================================================
# Development
# =============================================================================

# Python
alias py='python3'
alias python='python3'
alias pip='pip3'

# Virtual environments (managed by 09-python.zsh)
# alias venv - managed by 09-python.zsh
alias activate='source venv/bin/activate'

# Docker (if installed)
if command -v docker &>/dev/null; then
    alias d='docker'
    alias dc='docker-compose'
    alias dps='docker ps'
    alias dpsa='docker ps -a'
    alias di='docker images'
    alias dex='docker exec -it'
    alias dlog='docker logs -f'
fi

# Kubernetes (if installed)
if command -v kubectl &>/dev/null; then
    alias k='kubectl'
    alias kgp='kubectl get pods'
    alias kgs='kubectl get services'
    alias kgd='kubectl get deployments'
    alias kdp='kubectl describe pod'
    alias kl='kubectl logs -f'
fi

# =============================================================================
# Miscellaneous
# =============================================================================

# Quick note
alias note='$EDITOR ~/notes.txt'

# Calculator
alias calc='bc -l'

# Weather shortcut
alias w='weather'

# IP shortcuts
alias ip='myip && localip'

# Update everything
alias update='update_system'

# =============================================================================
# Fun
# =============================================================================

# Matrix effect (if cmatrix is installed)
if command -v cmatrix &>/dev/null; then
    alias matrix='cmatrix -ba'
fi

# Fortune + cowsay (if installed)
if command -v fortune &>/dev/null && command -v cowsay &>/dev/null; then
    alias wisdom='fortune | cowsay'
fi
