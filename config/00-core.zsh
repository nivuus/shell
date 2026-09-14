#!/usr/bin/env zsh
# =============================================================================
# Core ZSH Settings
# =============================================================================
# Minimal, fast core configuration
# =============================================================================

# Load theme (NIVUUS_THEME / NIVUUS_THEME_FILE / NIVUUS_THEME_DIR are set in
# .zshrc and can be overridden in ~/.zsh_local before this file loads)
export NIVUUS_THEME="${NIVUUS_THEME:-nord}"
_nivuus_theme_file="${NIVUUS_THEME_FILE:-}"
if [[ -z "$_nivuus_theme_file" && -n "$NIVUUS_THEME_DIR" && -f "$NIVUUS_THEME_DIR/${NIVUUS_THEME}.zsh" ]]; then
    _nivuus_theme_file="$NIVUUS_THEME_DIR/${NIVUUS_THEME}.zsh"
fi
[[ -z "$_nivuus_theme_file" ]] && _nivuus_theme_file="$NIVUUS_SHELL_DIR/themes/${NIVUUS_THEME}.zsh"
if [[ ! -f "$_nivuus_theme_file" ]]; then
    echo "⚠️  Nivuus Shell: theme '${NIVUUS_THEME}' introuvable (${_nivuus_theme_file}), fallback sur nord" >&2
    _nivuus_theme_file="$NIVUUS_SHELL_DIR/themes/nord.zsh"
fi
source "$_nivuus_theme_file"
unset _nivuus_theme_file

# =============================================================================
# Terminal Detection
# =============================================================================

# Is there a human behind this shell, watching a terminal?
#
# `[[ -o interactive ]]` is NOT that test, and using it for display or prompt
# decisions is a bug: agent harnesses (Claude Code, and anything else that
# snapshots an environment) build their shell by running `zsh -i` with the
# three standard descriptors on pipes. The option is set, no terminal is
# attached, and every "interactive only" guard lets the feature through into a
# context that cannot render or answer it.
#
# Probe stderr rather than stdout: a human redirects `ls > out.txt` all the
# time without ceasing to be a human, but fd 2 stays on the terminal.
#
# Use `[[ -o interactive ]]` only for things that genuinely need the option
# itself, such as ZLE widgets.
nivuus_has_terminal() {
    [[ -t 2 ]]
}

# =============================================================================
# Basic Options
# =============================================================================

# Disable beep
setopt NO_BEEP

# Allow comments in interactive shell
setopt INTERACTIVE_COMMENTS

# Change directory without cd
setopt AUTO_CD

# Push directory to stack automatically
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT

# Better globbing
setopt EXTENDED_GLOB
setopt GLOB_DOTS

# Disable flow control (Ctrl+S/Ctrl+Q)
setopt NO_FLOW_CONTROL

# =============================================================================
# Directory Stack
# =============================================================================

DIRSTACKSIZE=10

# =============================================================================
# Color Support
# =============================================================================

# Enable colors
autoload -U colors && colors

# Colored output for ls
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    export CLICOLOR=1
    alias ls='ls -G'
else
    # Linux
    alias ls='ls --color=auto'
fi

# Colored grep
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# =============================================================================
# Disable Python/Conda Prompt Modifications
# =============================================================================

export VIRTUAL_ENV_DISABLE_PROMPT=1
export CONDA_CHANGEPS1=false
