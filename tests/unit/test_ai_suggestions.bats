#!/usr/bin/env bats

# Unit tests for AI suggestions module (config/19-ai-suggestions.zsh)

setup() {
    # Load dependencies in ZSH context
    export NIVUUS_AI_SUGGESTIONS_LOADED=""
}

@test "AI suggestions module loads without errors" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh' && source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh' && echo \$NIVUUS_AI_SUGGESTIONS_LOADED"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1"* ]]
}

@test "AI suggestions defines required widgets" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh' && source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh' && zle -l | grep -E '(_ai_show_inline|_ai_accept_inline|_ai_clear_inline)'"
    [ "$status" -eq 0 ]
}

@test "TRAPUSR1 signal handler is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'TRAPUSR1()' config/19-ai-suggestions.zsh"
    [ "$status" -eq 0 ]
}

@test "AI cache associative arrays are initialized" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh' && source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh' && typeset -p _AI_CACHE 2>&1"
    [ "$status" -eq 0 ]
}

@test "AI generation function exists" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh' && source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh' && typeset -f _ai_generate"
    [ "$status" -eq 0 ]
}

@test "Animation spinner tick function exists" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh' && source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh' && typeset -f _ai_spinner_tick"
    [ "$status" -eq 0 ]
}

@test "Loading animation uses Nord cyan color (110)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '110' config/19-ai-suggestions-render.zsh"
    [ "$status" -eq 0 ]
}

@test "Suggestion display uses Nord green color (143)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '143' config/19-ai-suggestions.zsh"
    [ "$status" -eq 0 ]
}

@test "Cancel generation function exists" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh' && source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh' && typeset -f _ai_cancel_generation"
    [ "$status" -eq 0 ]
}

@test "Keybindings are registered (Ctrl+2, Ctrl+Down, Shift+Tab)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh' && source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh' && bindkey | grep -E '(ai-show-inline|ai-accept-inline|ai-clear-inline)'"
    [ "$status" -eq 0 ]
}

@test "ghost text highlight covers POSTDISPLAY, not the start of the line" {
    # A `P` offset counts from the start of PREDISPLAY+BUFFER+POSTDISPLAY, so
    # the range has to start past the buffer. `P0 <len>` painted the command
    # the user typed instead of the suggestion after it.
    run zsh -c "
        source '$NIVUUS_SHELL_DIR/themes/nord.zsh'
        source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'
        source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh'
        PREDISPLAY=''
        BUFFER='git sw'
        region_highlight=()
        _ai_set_postdisplay 'itch main' 'fg=143'
        print -r -- \"\${region_highlight[1]}\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "P6 15 fg=143 memo=nivuus-ai" ]]
}

@test "clearing the ghost text leaves other plugins' highlights alone" {
    run zsh -c "
        source '$NIVUUS_SHELL_DIR/themes/nord.zsh'
        source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'
        source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh'
        PREDISPLAY=''
        BUFFER='git sw'
        region_highlight=('0 3 fg=110 memo=zsh-syntax-highlighting')
        _ai_set_postdisplay 'itch main' 'fg=143'
        _ai_clear_postdisplay
        print -r -- \"\${#region_highlight[@]}:\${region_highlight[1]}\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "1:0 3 fg=110 memo=zsh-syntax-highlighting" ]]
}
