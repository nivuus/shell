#!/usr/bin/env bats

# Integration tests for the inline AI suggestion ghost text.
#
# These drive a real interactive zsh through a pseudo-terminal, because
# POSTDISPLAY and region_highlight are ZLE parameters: outside a widget they
# are ordinary shell variables. A test that calls the widget functions
# directly passes even when nothing is ever drawn on screen.

setup() {
    REPO="$BATS_TEST_DIRNAME/../.."
    HARNESS="$REPO/tests/helpers/ai_inline_pty.zsh"
}

@test "inline suggestion is drawn as ghost text after the cursor" {
    run zsh "$HARNESS" "$REPO" display
    [ "$status" -eq 0 ]
    # Suggestion colour (Nord green 143) reaches the terminal
    [[ "$output" == *"38;5;143"* ]]
    # ...carrying the tail of the stubbed suggestion
    [[ "$output" == *"_ACCEPTED_OK"* ]]
}

@test "braille spinner is animated while generating" {
    run zsh "$HARNESS" "$REPO" display
    [ "$status" -eq 0 ]
    # Spinner colour (Nord cyan 110)
    [[ "$output" == *"38;5;110"* ]]
    # More than one distinct braille frame means the zle -F ticks are rendering
    frames=$(printf '%s' "$output" | grep -oP '[\x{2800}-\x{28FF}]' | sort -u | wc -l)
    [ "$frames" -ge 2 ]
}

@test "highlight covers the ghost text, not the typed buffer" {
    run zsh "$HARNESS" "$REPO" display
    [ "$status" -eq 0 ]
    # The typed prefix is "pri". A wrong region_highlight offset paints those
    # characters instead of the ghost text.
    [[ "$output" != *"38;5;110mp"* ]]
    [[ "$output" != *"38;5;110mr"* ]]
    [[ "$output" != *"38;5;143mp"* ]]
}

@test "auto-debounce draws the suggestion without any keypress" {
    # Regression: the debounce used to be scheduled with zsh/sched, and a
    # zle -F handler registered from a sched callback never fires, so the
    # spinner froze on its first frame and the suggestion never appeared.
    run zsh "$HARNESS" "$REPO" debounce
    [ "$status" -eq 0 ]
    [[ "$output" == *"38;5;143"* ]]
    [[ "$output" == *"_ACCEPTED_OK"* ]]
}

@test "auto-debounce animates the spinner" {
    run zsh "$HARNESS" "$REPO" debounce
    [ "$status" -eq 0 ]
    frames=$(printf '%s' "$output" | grep -oP '[\x{2800}-\x{28FF}]' | sort -u | wc -l)
    [ "$frames" -ge 2 ]
}

@test "Ctrl+Right accepts the AI suggestion into the buffer" {
    run zsh "$HARNESS" "$REPO" accept
    [ "$status" -eq 0 ]
    # The accepted command actually ran, so its output appears verbatim
    [[ "$output" == *"NIVUUS_ACCEPTED_OK"* ]]
}
