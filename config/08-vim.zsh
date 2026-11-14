#!/usr/bin/env zsh
# =============================================================================
# Vim Integration - Modern Shortcuts + Nord Theme
# =============================================================================
# Ctrl+C/V/X/A support with environment detection
# =============================================================================

# Check if vim is installed
if ! command -v vim &>/dev/null; then
    return
fi

# =============================================================================
# Environment Detection
# =============================================================================

detect_vim_env() {
    if [[ -n "$SSH_CLIENT" || -n "$SSH_TTY" ]]; then
        echo "ssh"
    elif [[ -n "$VSCODE_INJECTION" ]] || [[ "$TERM_PROGRAM" == "vscode" ]]; then
        echo "vscode"
    elif [[ -n "$CODESPACES" ]] || [[ -n "$GITPOD_WORKSPACE_ID" ]]; then
        echo "web"
    else
        echo "local"
    fi
}

# =============================================================================
# Vim Commands
# =============================================================================

# Main edit command with environment detection
vedit() {
    local env=$(detect_vim_env)
    local vimrc="$NIVUUS_SHELL_DIR/.vimrc.nord"

    case "$env" in
        ssh)
            # SSH: minimal config for speed
            vim -u "$vimrc" --noplugin "$@"
            ;;
        vscode)
            # VS Code: use editor
            code "$@" 2>/dev/null || vim -u "$vimrc" "$@"
            ;;
        web)
            # Web: basic vim
            vim -u "$vimrc" --noplugin "$@"
            ;;
        *)
            # Local: full-featured
            vim -u "$vimrc" "$@"
            ;;
    esac
}

# Explicit mode commands
alias vim.modern="vim -u $NIVUUS_SHELL_DIR/.vimrc.nord"
alias vim.ssh="vim -u $NIVUUS_SHELL_DIR/.vimrc.nord --noplugin"

# Show vim shortcuts
vim_help() {
    cat <<'EOF'
Nivuus Vim - Modern Shortcuts

Mode: INSERT mode
  Ctrl+C    - Copy selection (yank to system clipboard)
  Ctrl+X    - Cut selection
  Ctrl+V    - Paste from system clipboard
  Ctrl+A    - Select all

Mode: NORMAL mode
  Ctrl+C    - Copy line
  Ctrl+V    - Paste
  Ctrl+A    - Select all (visual mode)

Commands:
  vedit <file>    - Edit with auto-detection
  vim.modern      - Full-featured vim
  vim.ssh         - Optimized for SSH
  vim_help        - Show this help

Environment: $(detect_vim_env)
EOF
}

# =============================================================================
# Default Vim Alias
# =============================================================================

# Use Nord theme by default -- at a terminal only: `vim -u` replaces the
# user's vimrc, which a script or an agent shell calling `vim` did not ask for.
if nivuus_has_terminal; then
    if [[ $(detect_vim_env) == "ssh" ]]; then
        alias vim='vim -u $NIVUUS_SHELL_DIR/.vimrc.nord --noplugin'
    else
        alias vim='vim -u $NIVUUS_SHELL_DIR/.vimrc.nord'
    fi
fi

# Set EDITOR
export EDITOR="vim"
export VISUAL="vim"
