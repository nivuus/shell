#!/usr/bin/env zsh
# =============================================================================
# AI Command Suggestions - Compact Interactive Menu
# =============================================================================

# Only load once. The guard is deliberately not exported: an exported guard is
# inherited by every child shell, so `exec zsh` -- or any nested zsh -- would
# see it already set and silently skip this whole module.
[[ -n "${NIVUUS_AI_SUGGESTIONS_LOADED}" ]] && return
typeset -g NIVUUS_AI_SUGGESTIONS_LOADED=1

# Skip if explicitly disabled
[[ "${ENABLE_AI_SUGGESTIONS:-true}" != "true" ]] && return

# Don't check for gemini at load time (NVM loads lazily)
# We'll check at execution time instead

# =============================================================================
# Configuration
# =============================================================================

typeset -g AI_SUGGESTION_MIN_CHARS="${AI_SUGGESTION_MIN_CHARS:-3}"
typeset -g AI_DEBOUNCE_DELAY="${AI_DEBOUNCE_DELAY:-2}"  # Debounce delay in seconds
typeset -g ENABLE_AI_AUTO_DEBOUNCE="${ENABLE_AI_AUTO_DEBOUNCE:-false}"  # Auto-trigger after typing
typeset -g AI_SUGGESTION_MODEL="${AI_SUGGESTION_MODEL:-$(_ai_resolve_model)}"  # Model for suggestions

# Current generation process PID
typeset -g _AI_GENERATE_PID=""

# Debounce timer state (see the debounce section further down)
typeset -g _AI_DEBOUNCE_FD=""
typeset -g _AI_DEBOUNCE_PID=""

# The module is split across files to keep each one readable; they are sourced
# here rather than listed in .zshrc, so the module keeps a single entry point.
typeset -g _AI_SUGGESTIONS_DIR="${${(%):-%x}:A:h}"
source "$_AI_SUGGESTIONS_DIR/19-ai-suggestions-generate.zsh"
source "$_AI_SUGGESTIONS_DIR/19-ai-suggestions-render.zsh"

# =============================================================================
# Inline Suggestion Display (Async with POSTDISPLAY)
# =============================================================================

# Global variable for temp file (shared with async checker)
typeset -g _AI_TEMP_FILE=""

_ai_show_inline() {
    local prefix="$BUFFER"

    # Cancel any pending debounce timer, animation, and generation
    _ai_cancel_debounce
    _ai_cancel_animation
    _ai_cancel_generation

    # Min chars check
    if [[ ${#prefix} -lt $AI_SUGGESTION_MIN_CHARS ]]; then
        return
    fi

    # --- Anti-collision: cancel pending zsh-autosuggestions async request & disable it ---
    if [[ -n "$_ZSH_AUTOSUGGEST_ASYNC_FD" ]] && { true <&$_ZSH_AUTOSUGGEST_ASYNC_FD } 2>/dev/null; then
        builtin exec {_ZSH_AUTOSUGGEST_ASYNC_FD}<&-
        zle -F "$_ZSH_AUTOSUGGEST_ASYNC_FD" 2>/dev/null
        if [[ -n "$_ZSH_AUTOSUGGEST_CHILD_PID" ]]; then
            kill -TERM "$_ZSH_AUTOSUGGEST_CHILD_PID" 2>/dev/null
            _ZSH_AUTOSUGGEST_CHILD_PID=""
        fi
        _ZSH_AUTOSUGGEST_ASYNC_FD=""
    fi
    typeset -g _ZSH_AUTOSUGGEST_DISABLED=1
    _AI_SAVED_AUTOSUGGEST_STRATEGY="${ZSH_AUTOSUGGEST_STRATEGY[*]}"
    ZSH_AUTOSUGGEST_STRATEGY=()

    # Clear any existing autosuggestion ghost text
    _ai_clear_postdisplay

    # Start spinner animation (realtime 100ms via zle -F)
    _ai_start_spinner

    # Generate in background with SIGUSR1 notification
    _AI_TEMP_FILE=$(mktemp)

    # Generate in background and signal when done
    {
        # Discard stderr: backend error diagnostics (e.g. agy failures) must
        # never be captured as suggestion text and shown as ghost text.
        _ai_generate "$prefix" 2>/dev/null | head -1 > "$_AI_TEMP_FILE"
        # Send SIGUSR1 to parent shell to trigger update
        kill -USR1 $$ 2>/dev/null
    } &!
    _AI_GENERATE_PID=$!
}

# Called by TRAPUSR1 when generation completes
_ai_handle_completion() {
    # Cancel spinner animation first
    _ai_cancel_animation

    # Get result
    local suggestion=""
    if [[ -f "$_AI_TEMP_FILE" ]]; then
        suggestion=$(cat "$_AI_TEMP_FILE" 2>/dev/null)
        rm -f "$_AI_TEMP_FILE"
    fi
    _AI_TEMP_FILE=""
    _AI_GENERATE_PID=""

    # Check for errors
    if [[ "$suggestion" == ERROR:* ]] || [[ -z "$suggestion" ]]; then
        suggestion=""
    fi

    # Store suggestion (full command returned by AI)
    _AI_CURRENT_SUGGESTION="$suggestion"

    if [[ -n "$suggestion" ]]; then
        # Extract the suffix (part after what user already typed)
        local suffix="${suggestion#$BUFFER}"
        if [[ "$suffix" == "$suggestion" ]]; then
            # Suggestion doesn't start with BUFFER — show full suggestion
            suffix=" → $suggestion"
        fi

        # Draw the suggestion right here, synchronously. It used to be typed
        # out character by character from a `zle -F` handler, but that handler
        # is not serviced when SIGUSR1 lands in the middle of ZLE's own event
        # processing -- which is exactly what a cache hit does, since it
        # answers in a couple of milliseconds. The suggestion then never
        # appeared at all. Eight characters of animation are not worth a
        # feature that silently renders nothing.
        _ai_set_postdisplay "$suffix" "fg=143"
    else
        # No suggestion — restore autosuggestions
        _ai_clear_postdisplay
        _ai_restore_autosuggest
    fi
}

# Register ZLE widget for completion handler
zle -N _ai_handle_completion

# Trap SIGUSR1 to handle completion
TRAPUSR1() {
    # Call the completion handler widget if we're in ZLE
    zle && zle _ai_handle_completion
}

_ai_accept_inline() {
    # Accept the AI suggestion if present
    if [[ -n "$_AI_CURRENT_SUGGESTION" ]]; then
        BUFFER="$_AI_CURRENT_SUGGESTION"
        CURSOR=${#BUFFER}
        _AI_CURRENT_SUGGESTION=""
        _ai_clear_postdisplay
        _ai_restore_autosuggest
    fi
}

_ai_clear_inline() {
    _AI_CURRENT_SUGGESTION=""
    _ai_clear_postdisplay
    _ai_restore_autosuggest
}

# Cancel any ongoing generation
_ai_cancel_generation() {
    # Only act if AI suggestion system is actually active
    # (avoids clearing zsh-autosuggestions POSTDISPLAY on every keypress)
    if [[ -z "$_AI_GENERATE_PID" && -z "$_AI_CURRENT_SUGGESTION" && -z "$_AI_SAVED_AUTOSUGGEST_STRATEGY" ]]; then
        return
    fi

    # Kill the generation process if it's running
    if [[ -n "$_AI_GENERATE_PID" ]]; then
        kill $_AI_GENERATE_PID 2>/dev/null
        wait $_AI_GENERATE_PID 2>/dev/null
        _AI_GENERATE_PID=""
    fi

    # Cleanup temp files
    if [[ -n "$_AI_TEMP_FILE" ]]; then
        rm -f "$_AI_TEMP_FILE"
        _AI_TEMP_FILE=""
    fi

    # Clear suggestion and POSTDISPLAY
    _AI_CURRENT_SUGGESTION=""
    _ai_clear_postdisplay
    _ai_restore_autosuggest

    # Cancel any scheduled animations
    _ai_cancel_animation
}


# =============================================================================
# Debounce System (one-shot timer on a zle -F file descriptor)
# =============================================================================
# The timer used to be a `sched` event calling `zle ai-show-inline`, which
# looks equivalent but silently kills the spinner: a `zle -F` handler
# registered while the widget runs inside a sched callback is never serviced
# again for that line, so the spinner drew a single frame and then froze for
# the whole generation. A handler registered from a keypress widget (or from
# another `zle -F` handler) does fire, so the delay is timed by a `sleep` in a
# coprocess whose output wakes a handler instead.
#
# `-w` on the registration matters: it runs the handler in full widget
# context. A plain fd handler sees an empty $BUFFER, and _ai_show_inline would
# read an empty prefix and bail out.

_ai_cancel_debounce() {
    if [[ -n "$_AI_DEBOUNCE_FD" ]]; then
        zle -F "$_AI_DEBOUNCE_FD" 2>/dev/null
        builtin exec {_AI_DEBOUNCE_FD}<&- 2>/dev/null
        _AI_DEBOUNCE_FD=""
    fi
    if [[ -n "$_AI_DEBOUNCE_PID" ]]; then
        kill -TERM "$_AI_DEBOUNCE_PID" 2>/dev/null
        _AI_DEBOUNCE_PID=""
    fi
}

# Fires once, when the sleep in the timer coprocess ends (or when it is killed
# and the fd hangs up -- in which case the debounce was cancelled and there is
# nothing to do).
_ai_debounce_trigger() {
    local fd="$1" event="$2"

    zle -F "$fd" 2>/dev/null
    builtin exec {fd}<&- 2>/dev/null
    [[ "$fd" == "$_AI_DEBOUNCE_FD" ]] && _AI_DEBOUNCE_FD=""
    _AI_DEBOUNCE_PID=""

    # A hangup means the timer was killed on cancel: nothing to do.
    [[ -z "$event" ]] || return 0
    _ai_show_inline
}

# `zle -F -w` requires its handler to be a registered widget.
zle -N _ai_debounce_trigger

_ai_start_debounce() {
    # Skip if auto-debounce is disabled
    [[ "${ENABLE_AI_AUTO_DEBOUNCE}" != "true" ]] && return

    # Skip if buffer is too short
    [[ ${#BUFFER} -lt $AI_SUGGESTION_MIN_CHARS ]] && return

    # Cancel any existing debounce timer
    _ai_cancel_debounce

    # The coprocess announces its pid on the first line so the timer can be
    # killed on cancel; that line is consumed here, before the handler is
    # registered, so the handler only ever runs for the end-of-delay line.
    builtin exec {_AI_DEBOUNCE_FD}< <(
        echo $sysparams[pid]
        sleep "$AI_DEBOUNCE_DELAY"
        echo "go"
    )
    read _AI_DEBOUNCE_PID <&$_AI_DEBOUNCE_FD
    zle -F -w "$_AI_DEBOUNCE_FD" _ai_debounce_trigger
}

# Hook into self-insert to trigger debounce on typing
_ai_debounce_self_insert() {
    # Clear any existing inline suggestion and restore autosuggestions
    _AI_CURRENT_SUGGESTION=""
    _ai_clear_postdisplay
    _ai_restore_autosuggest

    zle .self-insert
    _ai_start_debounce
}

# Cancel debounce on accept-line (Enter)
_ai_debounce_accept_line() {
    # Cancel any pending debounce timer
    _ai_cancel_debounce

    # Cancel any ongoing AI generation
    _ai_cancel_generation

    # Execute the command in the buffer
    zle .accept-line
}

# Cancel debounce on send-break (Ctrl+C)
_ai_debounce_send_break() {
    _ai_cancel_debounce
    _ai_cancel_generation
    zle .send-break
}

# Cancel debounce on clear-screen (Ctrl+L)
_ai_debounce_clear_screen() {
    _ai_cancel_debounce
    _ai_cancel_generation
    zle .clear-screen
}

# =============================================================================
# Widget and Keybinding
# =============================================================================

# --- Unified Ctrl+Right: accept AI suggestion or autosuggestion word ---
_ai_accept_or_word() {
    if [[ -n "$_AI_CURRENT_SUGGESTION" ]]; then
        # AI suggestion active → accept it entirely
        _ai_accept_inline
    else
        # No AI suggestion → delegate to history autosuggestion word-accept
        _autosuggest_accept_word
    fi
}

# --- Cancel AI generation on history navigation ---

# Wrap up-line-or-beginning-search (autoloaded function, not builtin)
_ai_cancel_and_up_search() {
    _ai_cancel_generation
    up-line-or-beginning-search "$@"
}

# Wrap down-line-or-beginning-search (autoloaded function, not builtin)
_ai_cancel_and_down_search() {
    _ai_cancel_generation
    down-line-or-beginning-search "$@"
}

# Wrap history-incremental-search-backward (builtin widget)
_ai_cancel_and_search_backward() {
    _ai_cancel_generation
    zle .history-incremental-search-backward
}

# Wrap history-incremental-search-forward (builtin widget)
_ai_cancel_and_search_forward() {
    _ai_cancel_generation
    zle .history-incremental-search-forward
}

# zsh-autosuggestions wraps every widget it does not recognise as one that may
# modify the buffer: it snapshots POSTDISPLAY, runs the widget, and -- when the
# buffer came back unchanged, which is exactly our case -- puts its own
# snapshot back, wiping the spinner the widget just drew. Widget names starting
# with "_" are already on its ignore list; the public ai-* ones have to be
# declared. It binds its wrappers on the first precmd, so config load time is
# early enough, and the array exists by then (config/18-autosuggestions.zsh).
typeset -ga ZSH_AUTOSUGGEST_IGNORE_WIDGETS
ZSH_AUTOSUGGEST_IGNORE_WIDGETS+=('ai-*')

# Register widgets
zle -N ai-show-inline _ai_show_inline
zle -N ai-accept-inline _ai_accept_inline
zle -N ai-clear-inline _ai_clear_inline
zle -N ai-accept-or-word _ai_accept_or_word

# Register debounce widgets (only if auto-debounce is enabled)
if [[ "${ENABLE_AI_AUTO_DEBOUNCE}" == "true" ]]; then
    zle -N self-insert _ai_debounce_self_insert
    zle -N accept-line _ai_debounce_accept_line
    zle -N send-break _ai_debounce_send_break
    zle -N clear-screen _ai_debounce_clear_screen
else
    # Even without auto-debounce, we need to cancel manual generations
    _ai_accept_line_no_debounce() {
        _ai_cancel_generation
        zle .accept-line
    }

    _ai_send_break_no_debounce() {
        _ai_cancel_generation
        zle .send-break
    }

    _ai_clear_screen_no_debounce() {
        _ai_cancel_generation
        zle .clear-screen
    }

    zle -N accept-line _ai_accept_line_no_debounce
    zle -N send-break _ai_send_break_no_debounce
    zle -N clear-screen _ai_clear_screen_no_debounce
fi

# --- History navigation wrappers (always active) ---
# Re-register widget names to point to our wrapper functions that call the
# original autoloaded functions by name (they remain callable as functions).
zle -N up-line-or-beginning-search _ai_cancel_and_up_search
zle -N down-line-or-beginning-search _ai_cancel_and_down_search

# history-incremental-search-backward/forward are builtins — wrap with .prefix
zle -N history-incremental-search-backward _ai_cancel_and_search_backward
zle -N history-incremental-search-forward _ai_cancel_and_search_forward

# Keybindings for inline mode
bindkey '^[[1;5C' ai-accept-or-word   # Ctrl+Right - Accept AI suggestion or next word
bindkey '\e[1;5C' ai-accept-or-word   # Ctrl+Right (alt)
bindkey '^[Oc' ai-accept-or-word      # Ctrl+Right (rxvt)
bindkey '^[[Z' ai-clear-inline        # Shift+Tab - Clear suggestion
bindkey '^2' ai-show-inline           # Ctrl+2 - Manual trigger
bindkey '^ ' ai-show-inline           # Ctrl+Space - Manual trigger
bindkey '^@' ai-show-inline           # Ctrl+Space (alt) - Manual trigger
# Note: Ctrl+Down (^[[1;5B) binding removed — Ctrl+Right is the unified key

# =============================================================================

source "$_AI_SUGGESTIONS_DIR/19-ai-suggestions-help.zsh"
