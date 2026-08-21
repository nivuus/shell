#!/usr/bin/env zsh
# =============================================================================
# File Management
# =============================================================================
# Native tools with optional modern alternatives
# =============================================================================

# =============================================================================
# File Listing
# =============================================================================

# Enhanced ls aliases
alias ll='ls -lAhF --color=auto 2>/dev/null || ls -lAhFG 2>/dev/null || ls -lAhF'
alias la='ls -A --color=auto 2>/dev/null || ls -AG 2>/dev/null || ls -A'
alias l='ls -CF --color=auto 2>/dev/null || ls -CFG 2>/dev/null || ls -CF'

# Tree view (use native tree if available, otherwise fallback)
if command -v tree &>/dev/null; then
    alias tree='tree -C'
else
    alias tree='find . -print | sed -e "s;[^/]*/;|____;g;s;____|; |;g"'
fi

# =============================================================================
# File Search
# =============================================================================

# Create fd alias for fdfind (Debian/Ubuntu compatibility)
if ! command -v fd &>/dev/null && command -v fdfind &>/dev/null; then
    alias fd='fdfind'
fi

# Fast file find (prefer fd if available, otherwise use find)
if command -v fd &>/dev/null || command -v fdfind &>/dev/null; then
    alias f='fd'
else
    alias f='find . -iname'
fi

# Content search (prefer ripgrep if available)
if command -v rg &>/dev/null; then
    alias search='rg'
else
    alias search='grep -r'
fi

# =============================================================================
# File Operations
# =============================================================================

# Create directory and cd into it
mkcd() {
    if [[ -z "$1" ]]; then
        echo "Usage: mkcd <directory>"
        return 1
    fi
    mkdir -p "$1" && cd "$1"
}

# Backup file with timestamp
backup() {
    if [[ -z "$1" ]]; then
        echo "Usage: backup <file>"
        return 1
    fi

    if [[ ! -e "$1" ]]; then
        echo "Error: File '$1' does not exist"
        return 1
    fi

    local backup_name="$1.backup.$(date +%Y%m%d-%H%M%S)"
    cp -r "$1" "$backup_name"
    echo "✓ Backed up to: $backup_name"
}

# Extract archives (supports multiple formats)
extract() {
    if [[ -z "$1" ]]; then
        echo "Usage: extract <archive>"
        echo "Supported: .tar, .tar.gz, .tgz, .tar.bz2, .tbz2, .zip, .rar, .7z, .gz, .bz2"
        return 1
    fi

    if [[ ! -f "$1" ]]; then
        echo "Error: File '$1' not found"
        return 1
    fi

    case "$1" in
        *.tar.bz2|*.tbz2) tar xjf "$1" ;;
        *.tar.gz|*.tgz)   tar xzf "$1" ;;
        *.tar.xz)         tar xJf "$1" ;;
        *.tar)            tar xf "$1" ;;
        *.gz)             gunzip "$1" ;;
        *.bz2)            bunzip2 "$1" ;;
        *.zip)            unzip "$1" ;;
        *.rar)            unrar x "$1" ;;
        *.7z)             7z x "$1" ;;
        *)
            echo "Error: Unknown archive format for '$1'"
            return 1
            ;;
    esac

    echo "✓ Extracted: $1"
}

# Show directory sizes
size() {
    local target="${1:-.}"
    du -sh "$target"/* 2>/dev/null | sort -h
}

# =============================================================================
# Safe Operations
# =============================================================================

# rm/cp/mv -i live in 15-aliases.zsh, guarded on an interactive shell.

# =============================================================================
# Modern Tool Suggestions
# =============================================================================

# Check for modern alternatives and suggest
_suggest_modern_tools() {
    local suggestions=()

    command -v eza &>/dev/null || suggestions+=("eza (modern ls): cargo install eza")

    # Check for bat or batcat (Debian/Ubuntu uses batcat)
    if ! command -v bat &>/dev/null && ! command -v batcat &>/dev/null; then
        suggestions+=("bat (better cat): cargo install bat")
    fi

    # Check for fd or fdfind (Debian/Ubuntu uses fdfind)
    if ! command -v fd &>/dev/null && ! command -v fdfind &>/dev/null; then
        suggestions+=("fd (fast find): cargo install fd-find")
    fi

    command -v rg &>/dev/null || suggestions+=("rg (ripgrep): cargo install ripgrep")
    command -v timg &>/dev/null || suggestions+=("timg (terminal images): sudo apt install timg")

    if [[ ${#suggestions[@]} -gt 0 ]]; then
        echo "💡 Optional modern tools:"
        for suggestion in "${suggestions[@]}"; do
            echo "   $suggestion"
        done
    fi
}

# Show suggestions on first shell load (once per day)
_show_tool_suggestions() {
    local suggestion_file="$HOME/.cache/nivuus-shell/last-tool-suggestion"
    local current_day=$(date +%Y%m%d)

    if [[ ! -f "$suggestion_file" ]] || [[ "$(cat "$suggestion_file" 2>/dev/null)" != "$current_day" ]]; then
        mkdir -p "$(dirname "$suggestion_file")"
        echo "$current_day" > "$suggestion_file"
        _suggest_modern_tools
    fi
}

# Run suggestions check (async, non-blocking).
# Interactif SEULEMENT : un `zsh -c "source .zshrc"` (script, test, CI) doit
# recevoir un flux de sortie vide. La suggestion est une courtoisie pour un
# humain devant un terminal, pas une donnée pour un programme.
if [[ -o interactive ]]; then
    (_show_tool_suggestions &)
fi
