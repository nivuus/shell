#!/usr/bin/env zsh
# =============================================================================
# Terminal Sanity Reset
# =============================================================================
# If an SSH connection drops while a program had left the terminal in mouse-
# tracking or bracketed-paste mode (vim, htop, less, ranger, ...), the local
# terminal keeps sending mouse/paste escape sequences on scroll/click after
# reconnecting. The shell doesn't understand them and echoes the raw bytes,
# which looks like garbled characters. Reset those modes on every prompt so
# a stuck mode never survives past the next command.
# =============================================================================

# Skip if explicitly disabled
[[ "${ENABLE_TERMINAL_SANITY_RESET:-true}" != "true" ]] && return

_nivuus_terminal_sanity_reset() {
    # Disable mouse tracking (normal, button-event, any-event, SGR extended)
    # and bracketed paste mode. Harmless no-ops if the terminal never turned
    # them on.
    print -n '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?2004l'
}

autoload -U add-zsh-hook
add-zsh-hook precmd _nivuus_terminal_sanity_reset
