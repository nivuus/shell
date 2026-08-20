#!/usr/bin/env zsh
# =============================================================================
# Syntax Highlighting
# =============================================================================
# Command-line syntax highlighting, colored from $THEME_COLORS (set by the
# loaded themes/*.zsh)
# =============================================================================

# Only load if enabled
[[ "${ENABLE_SYNTAX_HIGHLIGHTING:-false}" != "true" ]] && return

# =============================================================================
# Load zsh-syntax-highlighting
# =============================================================================

# Try common installation paths
typeset -a highlighting_paths
highlighting_paths=(
    /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    ~/.local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
)

for highlighting_path in $highlighting_paths; do
    if [[ -f "$highlighting_path" ]]; then
        source "$highlighting_path"
        break
    fi
done

# Exit if not loaded
[[ -z "$ZSH_HIGHLIGHT_HIGHLIGHTERS" ]] && return

# =============================================================================
# Themed Colors for Syntax Highlighting
# =============================================================================
# Reads semantic colors from $THEME_COLORS (set by the loaded themes/*.zsh),
# with Nord's own codes as a fallback if a color key is missing.
# =============================================================================

# Main highlighter
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern)

# Default text
ZSH_HIGHLIGHT_STYLES[default]="fg=${THEME_COLORS[fg_main]:-253}"

# Unknown commands
ZSH_HIGHLIGHT_STYLES[unknown-token]="fg=${THEME_COLORS[red]:-167},bold"

# Commands
ZSH_HIGHLIGHT_STYLES[command]="fg=${THEME_COLORS[cyan]:-110}"
ZSH_HIGHLIGHT_STYLES[builtin]="fg=${THEME_COLORS[cyan]:-110}"
ZSH_HIGHLIGHT_STYLES[function]="fg=${THEME_COLORS[cyan]:-110}"
ZSH_HIGHLIGHT_STYLES[alias]="fg=${THEME_COLORS[cyan]:-110}"

# Keywords and reserved words
ZSH_HIGHLIGHT_STYLES[reserved-word]="fg=${THEME_COLORS[blue]:-67}"
ZSH_HIGHLIGHT_STYLES[precommand]="fg=${THEME_COLORS[blue]:-67}"

# Paths
ZSH_HIGHLIGHT_STYLES[path]="fg=${THEME_COLORS[green]:-143}"
ZSH_HIGHLIGHT_STYLES[path_prefix]="fg=${THEME_COLORS[green]:-143}"
ZSH_HIGHLIGHT_STYLES[path_approx]="fg=${THEME_COLORS[green]:-143},underline"

# Strings
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]="fg=${THEME_COLORS[green]:-143}"
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]="fg=${THEME_COLORS[green]:-143}"
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]="fg=${THEME_COLORS[green]:-143}"

# Variables
ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]="fg=${THEME_COLORS[magenta]:-139}"
ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]="fg=${THEME_COLORS[magenta]:-139}"
ZSH_HIGHLIGHT_STYLES[back-quoted-argument]="fg=${THEME_COLORS[magenta]:-139}"
ZSH_HIGHLIGHT_STYLES[assign]="fg=${THEME_COLORS[magenta]:-139}"

# Globbing/wildcards
ZSH_HIGHLIGHT_STYLES[globbing]="fg=${THEME_COLORS[yellow]:-221}"

# Redirection
ZSH_HIGHLIGHT_STYLES[redirection]="fg=${THEME_COLORS[blue]:-67}"

# Command separator
ZSH_HIGHLIGHT_STYLES[commandseparator]="fg=${THEME_COLORS[comment]:-240}"

# Comments
ZSH_HIGHLIGHT_STYLES[comment]="fg=${THEME_COLORS[comment]:-240}"

# Arguments
ZSH_HIGHLIGHT_STYLES[arg0]="fg=${THEME_COLORS[cyan]:-110}"

# Brackets matching
ZSH_HIGHLIGHT_STYLES[bracket-level-1]="fg=${THEME_COLORS[cyan]:-110}"
ZSH_HIGHLIGHT_STYLES[bracket-level-2]="fg=${THEME_COLORS[blue]:-67}"
ZSH_HIGHLIGHT_STYLES[bracket-level-3]="fg=${THEME_COLORS[cyan_light]:-109}"
ZSH_HIGHLIGHT_STYLES[bracket-level-4]="fg=${THEME_COLORS[blue_light]:-68}"
ZSH_HIGHLIGHT_STYLES[bracket-error]="fg=${THEME_COLORS[red]:-167},bold"

# Cursor
ZSH_HIGHLIGHT_STYLES[cursor]='standout'

# =============================================================================
# Pattern Highlighting (Security)
# =============================================================================

# Highlight dangerous commands
ZSH_HIGHLIGHT_PATTERNS+=('rm -rf*' "fg=${THEME_COLORS[red]:-167},bold")

# Highlight only the word "sudo" (orange)
ZSH_HIGHLIGHT_STYLES[precommand]="fg=${THEME_COLORS[orange]:-208}"  # sudo, nohup, etc.

# =============================================================================
# Performance Optimization
# =============================================================================

# Disable highlighting for very long buffers (performance)
ZSH_HIGHLIGHT_MAXLENGTH=512
