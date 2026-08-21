#!/usr/bin/env zsh
# =============================================================================
# AI Command Suggestions - Compact Interactive Menu
# =============================================================================

# Only load once
[[ -n "${NIVUUS_AI_SUGGESTIONS_LOADED}" ]] && return
export NIVUUS_AI_SUGGESTIONS_LOADED=1

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

# Cache
# $EPOCHSECONDS needs zsh/datetime; without it every cache entry is stamped
# with an empty time and the 5min TTL check below never sees a hit, so every
# keystroke re-calls the backend.
zmodload zsh/datetime 2>/dev/null
typeset -gA _AI_CACHE
typeset -gA _AI_CACHE_TIME

# Animation state (braille spinner via zle -F)
typeset -g _AI_SPINNER_FRAME=0
typeset -ga _AI_SPINNER_CHARS=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
typeset -g _AI_ANIM_FD=""
typeset -g _AI_ANIM_PID=""

# Pending ghost-text render, consumed by the _ai_apply_postdisplay widget
typeset -g _AI_RENDER_TEXT=""
typeset -g _AI_RENDER_STYLE=""
typeset -g _AI_LAST_HIGHLIGHT=""

# Debounce timer state via zle -F
typeset -g _AI_DEBOUNCE_FD=""
typeset -g _AI_DEBOUNCE_PID=""

# Typewriter animation state via zle -F
typeset -g _AI_TYPEWRITER_FD=""
typeset -g _AI_TYPEWRITER_PID=""
typeset -g _AI_TYPEWRITER_TEXT=""
typeset -g _AI_TYPEWRITER_POS=0

# Current generation process PID
typeset -g _AI_GENERATE_PID=""

# =============================================================================
# Context Collection
# =============================================================================

# Redact obvious secrets before any context leaves the machine for the AI API.
# Masks API keys, tokens, passwords and Authorization headers on a line.
_ai_redact() {
    sed -E \
        -e 's/((api[_-]?key|token|secret|password|passwd|pwd|access[_-]?key|client[_-]?secret|authorization)[[:space:]]*[:=][[:space:]]*)[^[:space:]"'"'"']+/\1***REDACTED***/gI' \
        -e 's/(Bearer[[:space:]]+)[A-Za-z0-9._-]+/\1***REDACTED***/g' \
        -e 's/(gh[pousr]_)[A-Za-z0-9]+/\1***REDACTED***/g' \
        -e 's/(AKIA)[0-9A-Z]{12,}/\1***REDACTED***/g' \
        -e 's/(sk-)[A-Za-z0-9]{16,}/\1***REDACTED***/g'
}

_ai_get_context() {
    local context=""

    # Working directory
    context+="Dir: $PWD\n"

    # ALL files in current directory (limited to 50 to avoid huge repos)
    local files=$(ls -1 2>/dev/null | head -50 | tr '\n' ', ' | sed 's/,$//')
    [[ -n "$files" ]] && context+="Files (all): $files\n"

    # Recent command history (last 20 commands)
    local hist=$(fc -ln -25 2>/dev/null | sed 's/^[[:space:]]*//' | grep -v "^$" | tail -20 | tr '\n' ';')
    [[ -n "$hist" ]] && context+="Recent commands: $hist\n"

    # Environment variables
    context+="User: $USER\n"
    context+="Shell: $SHELL\n"
    context+="Home: $HOME\n"

    # Full PATH (truncated if too long)
    local path_truncated=$(echo "$PATH" | cut -c1-200)
    [[ ${#PATH} -gt 200 ]] && path_truncated="$path_truncated..."
    context+="PATH: $path_truncated\n"

    # Project type detection with file contents
    if [[ -f "package.json" ]]; then
        context+="Project: Node.js\n"
        local pkg_scripts=$(grep -A20 '"scripts"' package.json 2>/dev/null | head -25)
        [[ -n "$pkg_scripts" ]] && context+="package.json scripts:\n$pkg_scripts\n"
    fi

    if [[ -f "go.mod" ]]; then
        context+="Project: Go\n"
        local go_content=$(head -15 go.mod 2>/dev/null)
        [[ -n "$go_content" ]] && context+="go.mod:\n$go_content\n"
    fi

    if [[ -f "Cargo.toml" ]]; then
        context+="Project: Rust\n"
        local cargo_content=$(head -20 Cargo.toml 2>/dev/null)
        [[ -n "$cargo_content" ]] && context+="Cargo.toml:\n$cargo_content\n"
    fi

    if [[ -f "requirements.txt" ]]; then
        context+="Project: Python\n"
        local req_content=$(head -15 requirements.txt 2>/dev/null)
        [[ -n "$req_content" ]] && context+="requirements.txt:\n$req_content\n"
    fi

    # README preview
    if [[ -f "README.md" ]]; then
        local readme_preview=$(head -20 README.md 2>/dev/null)
        [[ -n "$readme_preview" ]] && context+="README.md preview:\n$readme_preview\n"
    fi

    # Git detailed status with diff
    if git rev-parse --git-dir &>/dev/null 2>&1; then
        local branch=$(git symbolic-ref --short HEAD 2>/dev/null)
        [[ -n "$branch" ]] && context+="Git branch: $branch\n"

        # Full git status
        local git_status=$(git status --short 2>/dev/null | head -30)
        [[ -n "$git_status" ]] && context+="Git status:\n$git_status\n"

        # Git diff of modified files (limited to 100 lines)
        local git_diff=$(git diff 2>/dev/null | head -100)
        [[ -n "$git_diff" ]] && context+="Git diff (first 100 lines):\n$git_diff\n"
    fi

    # Strip secrets before this context is sent to the AI provider.
    # (No -r: keep the historical behaviour of expanding the embedded \n.)
    print -- "$context" | _ai_redact
}

# =============================================================================
# Generate AI Suggestions
# =============================================================================

_ai_generate() {
    local prefix="$1"
    local cache_key="${prefix}_${PWD}"

    # Check credentials for the active backend
    if ! _ai_credentials_ok; then
        case "$AI_BACKEND" in
            openai) echo "ERROR: OPENAI_API_KEY not set. Run 'aihelp' for setup instructions." >&2 ;;
            anthropic) echo "ERROR: ANTHROPIC_API_KEY not set. Run 'aihelp' for setup instructions." >&2 ;;
            gemini)
                if [[ "$GEMINI_AUTH_MODE" == "cli" ]]; then
                    echo "ERROR: Antigravity CLI (agy) not found. Install it, or set GEMINI_AUTH_MODE=api-key. Run 'aihelp' for setup instructions." >&2
                else
                    echo "ERROR: GOOGLE_API_KEY not set. Run 'aihelp' for setup instructions." >&2
                fi
                ;;
        esac
        return 1
    fi

    # Check cache (5min TTL)
    if [[ -n "${_AI_CACHE_TIME[$cache_key]}" ]]; then
        local age=$(( EPOCHSECONDS - _AI_CACHE_TIME[$cache_key] ))
        if (( age < 300 )); then
            echo "${_AI_CACHE[$cache_key]}"
            return
        fi
    fi

    # Inline mode always generates 1 suggestion for speed
    local num_suggestions=1

    local context=$(_ai_get_context)
    local prompt="You are a shell command autocompletion engine. The user has typed exactly this partial command: \"$prefix\"
Your output MUST be the full command and MUST start with exactly \"$prefix\" (same characters, same case). Do not suggest an unrelated command, even if the context below seems more relevant. Output ONLY the completed command, no explanation, no markdown.

Context (background reference only, does not override the partial command above):
$context"

    # Call the active backend. 15s (not 5s) because GEMINI_AUTH_MODE=cli routes
    # through the agy CLI, which has ~3s of fixed process-startup overhead on
    # top of the actual generation time -- a 5s budget made every inline
    # suggestion time out/get canceled once cli mode became the default.
    local result=$(_ai_api_call "$prompt" "$AI_SUGGESTION_MODEL" 60 0.3 15)

    # Keep first non-empty line, strip wrapping backticks/quotes
    result=$(print -r -- "$result" | grep -v '^[[:space:]]*$' | head -1 | \
        sed 's/^`\(.*\)`$/\1/' | \
        sed 's/^"\(.*\)"$/\1/')

    # Reject completions that don't actually extend what the user typed
    # (the model sometimes ignores the partial and free-associates from context)
    if [[ -n "$result" && "$result" != "$prefix"* ]]; then
        result=""
    fi

    if [[ -n "$result" ]]; then
        _AI_CACHE[$cache_key]="$result"
        _AI_CACHE_TIME[$cache_key]="$EPOCHSECONDS"
    fi

    print -r -- "$result"
}


# =============================================================================
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
    zle -F "$_AI_ANIM_FD" _ai_spinner_tick
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

    # Close typewriter FD handler and kill background process
    if [[ -n "$_AI_TYPEWRITER_FD" ]]; then
        zle -F "$_AI_TYPEWRITER_FD" 2>/dev/null
        builtin exec {_AI_TYPEWRITER_FD}<&- 2>/dev/null
        _AI_TYPEWRITER_FD=""
    fi
    if [[ -n "$_AI_TYPEWRITER_PID" ]]; then
        kill -TERM "$_AI_TYPEWRITER_PID" 2>/dev/null
        _AI_TYPEWRITER_PID=""
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

# Widget that actually writes the ghost text. POSTDISPLAY and region_highlight
# are ZLE parameters: they only exist inside a widget. Assigning them from a
# `zle -F` fd handler silently creates ordinary shell variables and displays
# nothing, so every render goes through this widget (same approach as
# zsh-autosuggestions' async response handler).
_ai_apply_postdisplay() {
    POSTDISPLAY="$_AI_RENDER_TEXT"

    # Drop our previous entry, keeping the ones owned by other plugins.
    # Matching on the exact entry (rather than a memo= tag) keeps this working
    # on zsh < 5.9, and is what zsh-autosuggestions does for the same reason.
    if [[ -n "$_AI_LAST_HIGHLIGHT" ]]; then
        region_highlight=("${(@)region_highlight:#$_AI_LAST_HIGHLIGHT}")
        _AI_LAST_HIGHLIGHT=""
    fi

    # Highlight the POSTDISPLAY range. Offsets are relative to $BUFFER and
    # extend past its end into the ghost text.
    if [[ -n "$POSTDISPLAY" && -n "$_AI_RENDER_STYLE" ]]; then
        _AI_LAST_HIGHLIGHT="${#BUFFER} $(( ${#BUFFER} + ${#POSTDISPLAY} )) ${_AI_RENDER_STYLE}"
        region_highlight+=("$_AI_LAST_HIGHLIGHT")
    fi

    zle -R
}
zle -N _ai_apply_postdisplay

# Helper: set the ghost text with a color. Safe from widgets and fd handlers.
_ai_set_postdisplay() {
    _AI_RENDER_TEXT="$1"
    _AI_RENDER_STYLE="$2"  # e.g., "fg=143" or "fg=110"
    zle && zle _ai_apply_postdisplay
}

# Helper: clear the ghost text and its highlight
_ai_clear_postdisplay() {
    _ai_set_postdisplay "" ""
}

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

# Typewriter animation callback
_ai_typewriter_tick() {
    local dummy
    if [[ -z "$2" || "$2" == "hup" ]]; then
        read -u $1 dummy 2>/dev/null
        (( _AI_TYPEWRITER_POS++ ))
        local visible="${_AI_TYPEWRITER_TEXT[1,$_AI_TYPEWRITER_POS]}"
        _ai_set_postdisplay "${visible}" "fg=143"

        if (( _AI_TYPEWRITER_POS >= ${#_AI_TYPEWRITER_TEXT} || _AI_TYPEWRITER_POS >= 8 )); then
            # Show full remaining text instantly and close typewriter
            _ai_set_postdisplay "${_AI_TYPEWRITER_TEXT}" "fg=143"
            if [[ -n "$_AI_TYPEWRITER_FD" ]]; then
                zle -F "$_AI_TYPEWRITER_FD" 2>/dev/null
                builtin exec {_AI_TYPEWRITER_FD}<&- 2>/dev/null
                _AI_TYPEWRITER_FD=""
            fi
            if [[ -n "$_AI_TYPEWRITER_PID" ]]; then
                kill -TERM "$_AI_TYPEWRITER_PID" 2>/dev/null
                _AI_TYPEWRITER_PID=""
            fi
        fi
    fi
}

_ai_start_typewriter() {
    local text="$1"
    _ai_cancel_animation
    _AI_TYPEWRITER_TEXT="$text"
    _AI_TYPEWRITER_POS=0

    builtin exec {_AI_TYPEWRITER_FD}< <(
        echo $sysparams[pid]
        local count=${#text}
        (( count > 8 )) && count=8
        for (( i=1; i<=count; i++ )); do
            sleep 0.025
            echo "1"
        done
    )
    read _AI_TYPEWRITER_PID <&$_AI_TYPEWRITER_FD
    zle -F "$_AI_TYPEWRITER_FD" _ai_typewriter_tick
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

        # Start typewriter animation for smooth appearance
        if (( ${#suffix} > 0 )); then
            _ai_start_typewriter "$suffix"
        else
            _ai_set_postdisplay "${suffix}" "fg=143"
        fi
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
# Debounce System (fd timer driven by zle -F)
# =============================================================================
# The delay is NOT scheduled with zsh/sched: a `zle -F` handler registered from
# inside a sched callback never fires, because ZLE is already blocked in its
# select() over the previous set of descriptors and does not pick up the new one
# until the next keypress. Triggering the suggestion from a sched callback
# therefore killed the spinner and the typewriter. An fd timer registered from
# the self-insert widget keeps the whole chain (timer -> suggestion -> spinner
# -> typewriter) inside contexts where zle -F is honoured.

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

# Fires once the debounce delay has elapsed
_ai_debounce_trigger() {
    local dummy fd="$1"
    [[ -n "$2" && "$2" != "hup" ]] && return

    read -u $fd dummy 2>/dev/null

    # Release the timer before running the widget so that _ai_show_inline's own
    # _ai_cancel_debounce call has nothing left to tear down
    zle -F "$fd" 2>/dev/null
    builtin exec {fd}<&- 2>/dev/null
    _AI_DEBOUNCE_FD=""
    _AI_DEBOUNCE_PID=""

    zle && zle ai-show-inline
}

_ai_start_debounce() {
    # Skip if auto-debounce is disabled
    [[ "${ENABLE_AI_AUTO_DEBOUNCE}" != "true" ]] && return

    # Skip if buffer is too short
    [[ ${#BUFFER} -lt $AI_SUGGESTION_MIN_CHARS ]] && return

    # Cancel any existing debounce timer
    _ai_cancel_debounce

    builtin exec {_AI_DEBOUNCE_FD}< <(
        echo $sysparams[pid]
        sleep "$AI_DEBOUNCE_DELAY"
        echo go
    )
    read _AI_DEBOUNCE_PID <&$_AI_DEBOUNCE_FD
    zle -F "$_AI_DEBOUNCE_FD" _ai_debounce_trigger
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
# Help
# =============================================================================

ai_suggestions_help() {
    cat <<'EOF'
AI Command Suggestions - Inline Mode

How it works:
  1. Type partial command (3+ chars): git s
  2. Either wait 2 seconds (auto-debounce) or press Ctrl+2/Ctrl+Space
  3. Spinner appears inline after cursor while generating
  4. Suggestion appears as green ghost text after cursor
  5. Press Ctrl+→ to accept suggestion (same key as word-accept from history)
  6. Press Enter to cancel generation and execute your typed command
  7. Navigate history (↑/↓/Ctrl+R) to cancel generation
  8. Continue typing to clear and reset timer

Features:
  • Nord color scheme (cyan spinner, green suggestions)
  • NO latency - Enter key responds instantly during generation
  • Async generation - never blocks your typing
  • ULTRA-RICH context for maximum relevance
  • Automatic cleanup on typing/accepting/canceling
  • Typewriter animation on suggestion appearance (when supported)

Context provided to AI (ultra-enriched):
  • ALL files in directory (up to 50)
  • Recent command history (last 20 commands)
  • Git status + FULL diff (100 lines)
  • Project files content (package.json scripts, go.mod, Cargo.toml, requirements.txt)
  • README.md preview (20 lines)
  • Full environment (USER, SHELL, HOME, PATH)
  • Project type detection (Node.js, Go, Rust, Python)

Configuration:
  AI_SUGGESTION_MIN_CHARS=3       # Minimum chars to trigger
  AI_DEBOUNCE_DELAY=2             # Debounce delay in seconds
  ENABLE_AI_AUTO_DEBOUNCE=false   # Auto-trigger after typing pause
  AI_SUGGESTION_MODEL=gemini-3.1-flash-lite  # Model for suggestions (default)

Available models:
  gemini-3.1-flash-lite  # Fastest, no "thinking" overhead, best for inline completion (default)
  gemini-2.5-flash       # More capable, still fast
  gemini-2.5-pro         # Most capable, slower
  Note: "thinking" models (gemini-3.7-flash, gemini-flash-latest) spend the
  output token budget on internal reasoning and return empty completions here.

Keybindings:
  Ctrl+→     - Accept inline AI suggestion (or next word from history)
  Shift+Tab  - Clear inline AI suggestion
  Ctrl+2     - Trigger AI suggestion manually
  Ctrl+Space - Trigger AI suggestion manually

During generation:
  Enter      - Cancel generation and execute your command (NO LATENCY)
  Ctrl+C     - Cancel generation and return to prompt
  Ctrl+L     - Cancel generation and clear screen
  ↑/↓        - Cancel generation and navigate history
  Ctrl+R     - Cancel generation and search history
  Type       - Clear suggestion and reset debounce timer

Colors (Nord palette):
  Cyan (110)       - Spinner / generating indicator
  Green (143)      - Suggested command (ghost text)

EOF
}
