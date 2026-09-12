#!/usr/bin/env zsh
# =============================================================================
# AI Command Suggestions - Spinner and Ghost Text
# =============================================================================
# Part of the AI suggestions module. Sourced by config/19-ai-suggestions.zsh,
# which is the entry point listed in .zshrc -- this file is not loaded on its
# own.
# =============================================================================

[[ -n "${NIVUUS_AI_SUGGESTIONS_RENDER_LOADED}" ]] && return
typeset -g NIVUUS_AI_SUGGESTIONS_RENDER_LOADED=1

# Animation state (braille spinner via zle -F)
typeset -g _AI_SPINNER_FRAME=0
typeset -ga _AI_SPINNER_CHARS=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
typeset -g _AI_ANIM_FD=""
typeset -g _AI_ANIM_PID=""

typeset -g _AI_SAVED_AUTOSUGGEST_STRATEGY=""

# Loading Animation (braille spinner in POSTDISPLAY via zle -F)
# =============================================================================

# Load zsh/system for sysparams and FD handlers
zmodload zsh/system 2>/dev/null

_ai_spinner_tick() {
    local dummy
    if [[ -z "$2" || "$2" == "hup" ]]; then
        read -u $1 dummy 2>/dev/null
        if [[ -n "$_AI_GENERATE_PID" ]]; then
            (( _AI_SPINNER_FRAME = (_AI_SPINNER_FRAME + 1) % ${#_AI_SPINNER_CHARS[@]} ))
            _ai_set_postdisplay " ${_AI_SPINNER_CHARS[$((_AI_SPINNER_FRAME + 1))]}" "fg=110"
        fi
    fi
}

# `zle -F -w` requires its handler to be a registered widget.
zle -N _ai_spinner_tick

_ai_start_spinner() {
    _ai_cancel_animation

    _AI_SPINNER_FRAME=0
    _ai_set_postdisplay " ${_AI_SPINNER_CHARS[1]}" "fg=110"

    builtin exec {_AI_ANIM_FD}< <(
        echo $sysparams[pid]
        while true; do
            sleep 0.1
            echo "1"
        done
    )
    read _AI_ANIM_PID <&$_AI_ANIM_FD
    # -w, so the tick runs in widget context. A plain fd handler gets a
    # detached view of the ZLE parameters: $BUFFER and $region_highlight read
    # back empty, the POSTDISPLAY it writes is never rendered (the spinner
    # looks frozen on its first frame) and the region_highlight it assigns
    # wipes the syntax highlighting off the command line.
    zle -F -w "$_AI_ANIM_FD" _ai_spinner_tick
}

_ai_cancel_animation() {
    # Close spinner FD handler and kill background process
    if [[ -n "$_AI_ANIM_FD" ]]; then
        zle -F "$_AI_ANIM_FD" 2>/dev/null
        builtin exec {_AI_ANIM_FD}<&- 2>/dev/null
        _AI_ANIM_FD=""
    fi
    if [[ -n "$_AI_ANIM_PID" ]]; then
        kill -TERM "$_AI_ANIM_PID" 2>/dev/null
        _AI_ANIM_PID=""
    fi
}

# =============================================================================
# Inline Suggestion Display (Async with POSTDISPLAY)
# =============================================================================

# Global variable for temp file (shared with async checker)
typeset -g _AI_TEMP_FILE=""
typeset -g _AI_SAVED_AUTOSUGGEST_STRATEGY=""

# Helper: restore zsh-autosuggestions strategy
_ai_restore_autosuggest() {
    unset _ZSH_AUTOSUGGEST_DISABLED
    if [[ -n "$_AI_SAVED_AUTOSUGGEST_STRATEGY" ]]; then
        # Restore as array
        ZSH_AUTOSUGGEST_STRATEGY=(${=_AI_SAVED_AUTOSUGGEST_STRATEGY})
        _AI_SAVED_AUTOSUGGEST_STRATEGY=""
    fi
}

# Tag on our own region_highlight entries, so they can be removed again
# without touching the ones zsh-syntax-highlighting (or any other plugin) owns.
typeset -g _AI_HIGHLIGHT_MEMO="nivuus-ai"

_ai_drop_highlight() {
    region_highlight=("${(@)region_highlight:#*memo=$_AI_HIGHLIGHT_MEMO*}")
}

# Helper: set POSTDISPLAY with a color using region_highlight
_ai_set_postdisplay() {
    local text="$1"
    local style="$2"  # e.g., "fg=143" or "fg=110"

    POSTDISPLAY="$text"
    _ai_drop_highlight

    if [[ -n "$text" && -n "$style" ]]; then
        # A `P` offset is relative to the whole displayed string --
        # PREDISPLAY, then BUFFER, then POSTDISPLAY -- and not to POSTDISPLAY
        # alone. `P0 ${#text}` therefore painted the first ${#text} characters
        # of the command the user typed instead of the ghost text after it:
        # with "git sw" completed to "git switch main", "git switc" came out
        # green and the actual suggestion stayed uncoloured.
        local -i start=$(( ${#PREDISPLAY} + ${#BUFFER} ))
        region_highlight+=("P${start} $(( start + ${#text} )) ${style} memo=$_AI_HIGHLIGHT_MEMO")
    fi

    zle && zle -R
}

# Helper: clear POSTDISPLAY and its highlights
_ai_clear_postdisplay() {
    POSTDISPLAY=""
    _ai_drop_highlight
    zle && zle -R
}
