#!/usr/bin/env zsh
# =============================================================================
# PTY harness for the inline AI suggestion widget
# =============================================================================
# POSTDISPLAY and region_highlight only exist inside a running ZLE, so the
# inline suggestion display cannot be tested by calling the functions directly:
# outside a widget they are ordinary shell variables and every assertion passes
# while nothing is drawn on screen. This harness drives a real interactive zsh
# through a pseudo-terminal and returns what the terminal actually received.
#
# Usage: zsh tests/helpers/ai_inline_pty.zsh <repo-dir> <scenario>
#   Scenarios:
#     display  - type a prefix, trigger a suggestion, dump the raw terminal output
#     accept   - same, then press Ctrl+Right and Enter; the accepted command runs
# =============================================================================

emulate -L zsh
zmodload zsh/zpty

typeset -g REPO="${1:?repo dir required}"
typeset -g SCENARIO="${2:?scenario required}"

typeset -g WORKDIR="${TMPDIR:-/tmp}/nivuus-ai-pty.$$"
mkdir -p "$WORKDIR"
trap 'rm -rf "$WORKDIR"' EXIT

# The suggestion the stubbed backend returns, and the prefix typed to get it.
typeset -g STUB_PREFIX="pri"
typeset -g STUB_SUGGESTION="print NIVUUS_ACCEPTED_OK"

# The debounce scenario exercises the auto-trigger path (the .zshrc default),
# which registers different widgets than the manual trigger.
typeset -g AUTO_DEBOUNCE=false
[[ "$SCENARIO" == debounce* ]] && AUTO_DEBOUNCE=true

cat > "$WORKDIR/.zshrc" <<EOF
PS1='%% '
# The "already loaded" guards are exported, so a nested shell would skip the
# modules under test.
unset NIVUUS_AUTOSUGGESTIONS_LOADED NIVUUS_AI_SUGGESTIONS_LOADED
export ENABLE_AI_SUGGESTIONS=true ENABLE_AUTOSUGGESTIONS=true
export ENABLE_AI_AUTO_DEBOUNCE=$AUTO_DEBOUNCE
export AI_DEBOUNCE_DELAY=1
export AI_SUGGESTION_MIN_CHARS=3
source "$REPO/config/18-autosuggestions.zsh"
source "$REPO/config/19-ai-suggestions.zsh"

# Stub the backend: no network, no API key, deterministic answer.
_ai_generate() { sleep 0.2; print -r -- "$STUB_SUGGESTION"; }

# Ctrl+Space is NUL and cannot be sent through the pty, so expose the same
# widget on Ctrl+G for the test.
bindkey '^G' ai-show-inline
EOF

_drain() {
    local chunk
    while zpty -r -t pty chunk 2>/dev/null; do :; done
}

_read_all() {
    local chunk out=""
    while zpty -r -t pty chunk 2>/dev/null; do out+="$chunk"; done
    print -r -- "$out"
}

# zpty forks the shell, so ZDOTDIR must be exported rather than passed as a
# command prefix, otherwise the nested shell reads the real ~/.zshrc.
export ZDOTDIR="$WORKDIR"
zpty -b pty zsh -i
sleep 1.5
_drain

zpty -w -n pty "$STUB_PREFIX"
sleep 0.4
_drain                       # discard the echo of the typed prefix

if [[ "$AUTO_DEBOUNCE" == true ]]; then
    sleep 2.5                # let the debounce timer fire on its own
else
    zpty -w -n pty $'\a'     # Ctrl+G -> ai-show-inline
    sleep 1.2
fi

case "$SCENARIO" in
    display|debounce)
        _read_all
        ;;
    accept)
        _drain
        zpty -w -n pty $'\e[1;5C'   # Ctrl+Right -> accept the suggestion
        sleep 0.5
        zpty -w -n pty $'\r'        # Enter -> run whatever is in the buffer
        sleep 0.8
        _read_all
        ;;
    *)
        print -u2 "unknown scenario: $SCENARIO"
        exit 2
        ;;
esac

zpty -d pty
