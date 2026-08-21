#!/usr/bin/env bats

# Integration tests for AI workflow (commands, suggestions, error handling,
# terminal titles).
#
# Architecture under test (config/):
#   09-ai-core.zsh              backend dispatcher: _ai_api_call/_ai_resolve_model
#   09-ai-backend-{gemini,openai,anthropic}.zsh   one _ai_backend_*_call each
#   09-ai-agy-daemon.zsh        Antigravity CLI daemon (GEMINI_AUTH_MODE=cli)
#   10-ai.zsh                   user commands: ??, why, explain, ask, aihelp
#   19-ai-suggestions.zsh       inline ghost-text suggestions (ZLE widgets)
#   20-terminal-title.zsh       terminal titles, optionally AI-generated
#   22-ai-errors.zsh            error capture + on-demand AI analysis
#   24-ai-command-not-found.zsh missing-package suggestions
#
# Tests assert on behaviour (source the module, call the function) wherever
# possible so they survive renames; no test ever performs a real network call.

setup() {
    REPO="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    export NIVUUS_SHELL_DIR="$REPO"

    # A developer running these tests from inside a Nivuus shell exports both
    # the "load once" guards and the feature toggles. Left in place they make
    # the modules under test return immediately, or make results depend on the
    # developer's own configuration.
    unset NIVUUS_AI_SUGGESTIONS_LOADED NIVUUS_TERMINAL_TITLE_LOADED
    unset NIVUUS_AUTOSUGGESTIONS_LOADED NIVUUS_COLORIZATION_LOADED
    unset ENABLE_AI_SUGGESTIONS ENABLE_AI_TERMINAL_TITLES ENABLE_AI_AUTO_DEBOUNCE
    unset ENABLE_AI_COMMAND_NOT_FOUND AI_INLINE_MODE
    unset AI_BACKEND GEMINI_AUTH_MODE GEMINI_MODEL GEMINI_CLI_MODEL
    unset OPENAI_MODEL ANTHROPIC_MODEL AI_SUGGESTION_MODEL AI_TITLE_MODEL

    # Dispatcher + every backend, i.e. what .zshrc loads before 10-ai.zsh.
    AI_CORE="source '$REPO/config/09-ai-core.zsh'; source '$REPO/config/09-ai-backend-gemini.zsh'; source '$REPO/config/09-ai-backend-openai.zsh'; source '$REPO/config/09-ai-backend-anthropic.zsh'"
    AI_STACK="$AI_CORE; source '$REPO/config/10-ai.zsh'"
}

# =============================================================================
# AI Module Integration Tests
# =============================================================================

@test "AI module loads without errors" {
    run zsh -c "$AI_CORE; source '$REPO/config/10-ai.zsh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "AI command functions are defined" {
    run bash -c "cd '$REPO' && grep -c -E '(why\\(\\)|explain\\(\\)|ask\\(\\)|aihelp\\(\\))' config/10-ai.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 3 ]
}

@test "AI commands are gated on the active backend's credentials" {
    # There is no gemini-cli dependency any more: 10-ai.zsh asks the dispatcher
    # (_ai_credentials_ok) whether the active backend can be called at all, and
    # degrades to setup instructions when it cannot.
    local fake_home="$BATS_TEST_TMPDIR/no-creds-home"
    mkdir -p "$fake_home"

    run zsh -c "export HOME='$fake_home' AI_BACKEND=gemini GEMINI_AUTH_MODE=api-key; unset GOOGLE_API_KEY; $AI_STACK; ask 'anything'"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GOOGLE_API_KEY"* ]]
    [[ "$output" == *"aihelp"* ]]
}

@test "AI help shows command information" {
    run zsh -c "$AI_STACK; aihelp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"??"* ]]
    [[ "$output" == *"why"* ]]
    [[ "$output" == *"explain"* ]]
    [[ "$output" == *"ask"* ]]
}

@test "aihelp shows the active backend and model" {
    run zsh -c "export AI_BACKEND=openai OPENAI_API_KEY=test-key; $AI_STACK; aihelp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Backend: openai"* ]]
    [[ "$output" == *"gpt-5.6-luna"* ]]
}

@test "aihelp shows agy status in gemini cli auth mode" {
    local fake_bin_dir="$BATS_TEST_TMPDIR/fake-agy-aihelp"
    mkdir -p "$fake_bin_dir"
    cat > "$fake_bin_dir/agy" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "--version" ]] && echo "agy 1.0.0"
EOF
    chmod +x "$fake_bin_dir/agy"

    run zsh -c "export PATH='$fake_bin_dir:\$PATH' GEMINI_AUTH_MODE=cli; $AI_STACK; aihelp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Antigravity CLI"* ]]
    [[ "$output" == *"✓"* ]]
}

@test "ask works end-to-end under GEMINI_AUTH_MODE=cli" {
    local fake_bin_dir="$BATS_TEST_TMPDIR/fake-agy-e2e"
    mkdir -p "$fake_bin_dir"
    cat > "$fake_bin_dir/agy" <<'EOF'
#!/usr/bin/env bash
echo '{"response":"mocked e2e response","status":"SUCCESS"}'
EOF
    chmod +x "$fake_bin_dir/agy"

    run zsh -c "export PATH=\"$fake_bin_dir:\$PATH\" GEMINI_AUTH_MODE=cli; unset GOOGLE_API_KEY; $AI_STACK; ask 'test question'"
    [ "$status" -eq 0 ]
    [ "$output" = "mocked e2e response" ]
}

# =============================================================================
# AI Suggestions Module Tests
# =============================================================================

@test "AI suggestions module loads" {
    run zsh -c "source '$REPO/themes/nord.zsh' && $AI_CORE && source '$REPO/config/19-ai-suggestions.zsh' 2>/dev/null && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "AI suggestions can be disabled" {
    run zsh -c "export ENABLE_AI_SUGGESTIONS=false; $AI_CORE; source '$REPO/config/19-ai-suggestions.zsh' 2>/dev/null; typeset -f _ai_show_inline >/dev/null && echo 'defined' || echo 'not defined'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not defined"* ]]
}

@test "AI suggestions hook into ZLE" {
    # Suggestions are driven by ZLE widgets + keybindings (there is no precmd
    # hook): the module must register them at load time.
    run zsh -c "source '$REPO/themes/nord.zsh'; $AI_CORE; source '$REPO/config/19-ai-suggestions.zsh'; zle -l"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ai-show-inline"* ]]
    [[ "$output" == *"ai-accept-inline"* ]]
    [[ "$output" == *"ai-clear-inline"* ]]

    run zsh -c "source '$REPO/themes/nord.zsh'; $AI_CORE; source '$REPO/config/19-ai-suggestions.zsh'; bindkey -L"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ai-show-inline"* ]]
}

@test "AI suggestions use SIGUSR1" {
    run bash -c "cd '$REPO' && grep 'SIGUSR1\|TRAPUSR1' config/19-ai-suggestions.zsh"
    [ "$status" -eq 0 ]
}

@test "AI suggestions run in background" {
    # _ai_show_inline must fork the generation and return immediately, leaving
    # the child's pid behind so it can be cancelled.
    run zsh -c "source '$REPO/themes/nord.zsh'; $AI_CORE; source '$REPO/config/19-ai-suggestions.zsh'
        _ai_generate() { sleep 5; print -r -- 'too late'; }
        BUFFER='git st'
        _ai_show_inline
        [[ -n \"\$_AI_GENERATE_PID\" ]] && echo 'backgrounded'
        kill \"\$_AI_GENERATE_PID\" 2>/dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" == *"backgrounded"* ]]
}

@test "AI suggestions have cache" {
    run bash -c "cd '$REPO' && grep '_AI_CACHE' config/19-ai-suggestions.zsh"
    [ "$status" -eq 0 ]
}

@test "AI suggestions cache prevents a second backend call" {
    # Behavioural check of the cache: same prefix, same directory, one call.
    # Regression guard for the missing `zmodload zsh/datetime` that made every
    # $EPOCHSECONDS stamp empty and the TTL check never match.
    run zsh -c "source '$REPO/themes/nord.zsh'; $AI_CORE; source '$REPO/config/19-ai-suggestions.zsh'
        _ai_credentials_ok() { return 0; }
        _ai_api_call() { print x >> '$BATS_TEST_TMPDIR/calls'; print -r -- 'git status --short'; }
        _ai_generate 'git st' > '$BATS_TEST_TMPDIR/out1'
        _ai_generate 'git st' > '$BATS_TEST_TMPDIR/out2'
        print -r -- \"calls=\$(wc -l < '$BATS_TEST_TMPDIR/calls')\"
        print -r -- \"cached=\$(cat '$BATS_TEST_TMPDIR/out2')\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"calls=1"* ]]
    [[ "$output" == *"cached=git status --short"* ]]
}

@test "AI suggestions cache has a 5 minute TTL" {
    # The stamp is compared against a 300s budget; keep both halves asserted so
    # dropping either the timestamp or the comparison fails the test.
    run bash -c "cd '$REPO' && grep -n 'EPOCHSECONDS - _AI_CACHE_TIME' config/19-ai-suggestions.zsh"
    [ "$status" -eq 0 ]
    run bash -c "cd '$REPO' && grep -n 'age < 300' config/19-ai-suggestions.zsh"
    [ "$status" -eq 0 ]
}

@test "AI suggestions report a missing backend credential instead of hanging" {
    local fake_home="$BATS_TEST_TMPDIR/sugg-no-creds"
    mkdir -p "$fake_home"

    run zsh -c "export HOME='$fake_home' AI_BACKEND=gemini GEMINI_AUTH_MODE=api-key; unset GOOGLE_API_KEY
        source '$REPO/themes/nord.zsh'; $AI_CORE; source '$REPO/config/19-ai-suggestions.zsh'
        _ai_generate 'git st' 2>&1"
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"GOOGLE_API_KEY"* ]]
}

# =============================================================================
# AI Inline Mode Tests
# =============================================================================

@test "AI inline mode feature toggle exists" {
    run bash -c "cd '$REPO' && grep 'AI_INLINE_MODE' config/19-ai-suggestions.zsh"
    [ "$status" -eq 0 ]
}

@test "AI inline mode respects toggle" {
    # AI_INLINE_MODE=false must suppress the ghost text (no generation started)
    # while AI_INLINE_MODE=true keeps it working.
    run zsh -c "source '$REPO/themes/nord.zsh'; $AI_CORE; source '$REPO/config/19-ai-suggestions.zsh'
        _ai_generate() { print -r -- 'git status'; }
        BUFFER='git st'
        AI_INLINE_MODE=false; _ai_show_inline
        print -r -- \"off=[\$_AI_GENERATE_PID]\"
        AI_INLINE_MODE=true; _ai_show_inline
        [[ -n \"\$_AI_GENERATE_PID\" ]] && print -r -- 'on=started'
        kill \"\$_AI_GENERATE_PID\" 2>/dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" == *"off=[]"* ]]
    [[ "$output" == *"on=started"* ]]
}

# =============================================================================
# AI Error Handling Module Tests
# =============================================================================

@test "AI error module loads" {
    run zsh -c "export AI_ERROR_CACHE_DIR='$BATS_TEST_TMPDIR/ai-errors'; $AI_CORE; source '$REPO/config/22-ai-errors.zsh' 2>/dev/null && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "AI error module has preexec hook" {
    run bash -c "cd '$REPO' && grep -E 'add-zsh-hook +preexec' config/22-ai-errors.zsh"
    [ "$status" -eq 0 ]
}

@test "AI error module stores exit codes" {
    run zsh -c "export AI_ERROR_CACHE_DIR='$BATS_TEST_TMPDIR/ai-errors'; $AI_CORE; source '$REPO/config/22-ai-errors.zsh'
        _ai_error_preexec 'false --nope'
        (exit 42); _ai_error_precmd
        print -r -- \"cmd=\$_AI_LAST_COMMAND code=\$_AI_LAST_ERROR_CODE avail=\$_AI_ERROR_AVAILABLE\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"cmd=false --nope"* ]]
    [[ "$output" == *"code=42"* ]]
    [[ "$output" == *"avail=true"* ]]
}

@test "AI error module suggests fixes" {
    run bash -c "cd '$REPO' && grep -E '(suggest|fix|error.*help)' config/22-ai-errors.zsh"
    [ "$status" -eq 0 ]
}

@test "AI error handling is non-blocking" {
    # The preexec/precmd hooks run on every prompt: they must only record
    # state, never call the AI backend or the network (analysis happens
    # on demand, from _ai_analyze_error).
    run zsh -c "export AI_ERROR_CACHE_DIR='$BATS_TEST_TMPDIR/ai-errors'; $AI_CORE; source '$REPO/config/22-ai-errors.zsh'; functions _ai_error_preexec _ai_error_precmd"
    [ "$status" -eq 0 ]
    [[ -n "$output" ]]
    [[ "$output" != *"_ai_api_call"* ]]
    [[ "$output" != *"curl"* ]]
    [[ "$output" != *"_ai_analyze_error"* ]]
}

# =============================================================================
# Terminal Titles Module Tests (config/20-terminal-title.zsh)
# =============================================================================

@test "AI terminal titles module loads" {
    run zsh -c "export TERM=xterm-256color ENABLE_AI_TERMINAL_TITLES=true AI_TITLE_CACHE_DIR='$BATS_TEST_TMPDIR/ai-titles'
        $AI_CORE; source '$REPO/config/20-terminal-title.zsh' 2>/dev/null
        typeset -f _set_terminal_title >/dev/null && typeset -f _ai_get_terminal_title >/dev/null && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "AI terminal titles can be disabled" {
    # Disabling only turns off the AI part: plain titles keep working.
    run zsh -c "export TERM=xterm-256color ENABLE_AI_TERMINAL_TITLES=false
        $AI_CORE; source '$REPO/config/20-terminal-title.zsh' 2>/dev/null
        typeset -f _set_terminal_title >/dev/null && echo 'titles kept'
        typeset -f _ai_get_terminal_title >/dev/null && echo 'ai kept' || echo 'ai disabled'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"titles kept"* ]]
    [[ "$output" == *"ai disabled"* ]]
}

@test "AI terminal titles use preexec" {
    run bash -c "cd '$REPO' && grep -E 'add-zsh-hook +preexec' config/20-terminal-title.zsh"
    [ "$status" -eq 0 ]
}

@test "AI terminal titles set terminal escape codes" {
    # OSC 0 ; <title> BEL
    run zsh -c "export TERM=xterm-256color ENABLE_AI_TERMINAL_TITLES=false
        $AI_CORE; source '$REPO/config/20-terminal-title.zsh' 2>/dev/null
        _set_terminal_title 'nivuus-test' | cat -v"
    [ "$status" -eq 0 ]
    [[ "$output" == *"^[]0;nivuus-test^G"* ]]
}

# =============================================================================
# AI Command Not Found Module Tests (config/24-ai-command-not-found.zsh)
# =============================================================================

@test "AI command-not-found module loads and registers its handler" {
    run zsh -c "export ENABLE_AI_COMMAND_NOT_FOUND=true; $AI_CORE; source '$REPO/config/24-ai-command-not-found.zsh' 2>/dev/null
        typeset -f command_not_found_handler >/dev/null && echo 'handler registered'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"handler registered"* ]]
}

# =============================================================================
# AI Backend Dispatcher Tests (config/09-ai-core.zsh)
# =============================================================================

@test "AI commands use gemini model variable" {
    # GEMINI_MODEL is resolved centrally by _ai_resolve_model() in
    # config/09-ai-core.zsh (config/10-ai.zsh only calls _ai_resolve_model).
    run zsh -c "export GEMINI_MODEL=my-custom-model; $AI_CORE; _ai_resolve_model"
    [ "$status" -eq 0 ]
    [ "$output" = "my-custom-model" ]
}

@test "AI commands default to a gemini model" {
    # Pinning the exact version here only creates churn; what matters is that
    # the gemini backend is the default and resolves to a gemini model.
    run zsh -c "unset AI_BACKEND GEMINI_MODEL; $AI_CORE; _ai_resolve_model"
    [ "$status" -eq 0 ]
    [[ "$output" == gemini-* ]]
}

@test "AI commands support temperature setting" {
    # _ai_api_call takes the temperature as 4th argument and forwards it to the
    # active backend, with a conservative default.
    run zsh -c "$AI_CORE
        _ai_backend_gemini_call() { print -r -- \"temp=\$4\"; }
        _ai_api_call 'prompt'
        _ai_api_call 'prompt' 'model' 128 0.9"
    [ "$status" -eq 0 ]
    [[ "$output" == *"temp=0.3"* ]]
    [[ "$output" == *"temp=0.9"* ]]
}

@test "AI backend dispatch honors AI_BACKEND" {
    run zsh -c "export AI_BACKEND=anthropic; $AI_CORE
        _ai_backend_anthropic_call() { print -r -- 'anthropic called'; }
        _ai_api_call 'prompt'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"anthropic called"* ]]

    run zsh -c "export AI_BACKEND=nonsense; $AI_CORE; _ai_api_call 'prompt' 2>&1"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown backend"* ]]
}

# =============================================================================
# Full AI Workflow Integration
# =============================================================================

@test "AI modules load in correct order" {
    run zsh -c "export AI_ERROR_CACHE_DIR='$BATS_TEST_TMPDIR/ai-errors'
        source '$REPO/themes/nord.zsh' && $AI_STACK && source '$REPO/config/19-ai-suggestions.zsh' 2>/dev/null && source '$REPO/config/22-ai-errors.zsh' 2>/dev/null && echo 'all loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"all loaded"* ]]
}

@test "AI modules work together with prompt" {
    run zsh -c "source '$REPO/themes/nord.zsh' && source '$REPO/config/05-prompt.zsh' && $AI_STACK && source '$REPO/config/19-ai-suggestions.zsh' 2>/dev/null && echo 'integrated'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"integrated"* ]]
}

@test "Full shell loads all AI modules" {
    run zsh -c "export TERM=xterm-256color; source '$REPO/.zshrc' 2>/dev/null
        for f in aihelp _ai_api_call _ai_resolve_model _ai_generate _ai_show_inline _set_terminal_title _ai_error_precmd command_not_found_handler; do
            typeset -f \$f >/dev/null || print -r -- \"MISSING \$f\"
        done
        print -r -- 'checked'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"MISSING"* ]]
    [[ "$output" == *"checked"* ]]
}

# =============================================================================
# AI Feature Toggles
# =============================================================================

@test "ENABLE_AI_SUGGESTIONS toggle exists in .zshrc" {
    run bash -c "cd '$REPO' && grep 'ENABLE_AI_SUGGESTIONS' .zshrc"
    [ "$status" -eq 0 ]
}

@test "ENABLE_AI_TERMINAL_TITLES toggle exists in .zshrc" {
    run bash -c "cd '$REPO' && grep 'ENABLE_AI_TERMINAL_TITLES' .zshrc"
    [ "$status" -eq 0 ]
}

@test "AI_INLINE_MODE toggle exists in .zshrc" {
    run bash -c "cd '$REPO' && grep 'AI_INLINE_MODE' .zshrc"
    [ "$status" -eq 0 ]
}

@test "ENABLE_AI_AUTO_DEBOUNCE toggle exists in .zshrc" {
    run bash -c "cd '$REPO' && grep 'ENABLE_AI_AUTO_DEBOUNCE' .zshrc"
    [ "$status" -eq 0 ]
}

@test "every AI toggle declared in .zshrc is actually read by a module" {
    # Guards against toggles that survive a refactor as documentation only
    # (AI_INLINE_MODE was dead for several releases).
    run bash -c "cd '$REPO' && for t in \$(grep -oE '^export (ENABLE_AI_[A-Z_]+|AI_INLINE_MODE)' .zshrc | awk '{print \$2}'); do
            grep -rqF \"\$t\" config/ || echo \"UNUSED \$t\"
        done"
    [ "$status" -eq 0 ]
    [[ "$output" != *"UNUSED"* ]]
}

# =============================================================================
# AI Performance Tests
# =============================================================================

@test "AI modules load quickly" {
    start=$(date +%s%N)
    zsh -c "$AI_STACK; source '$REPO/config/19-ai-suggestions.zsh' 2>/dev/null" >/dev/null
    end=$(date +%s%N)
    elapsed_ms=$(( (end - start) / 1000000 ))

    [ "$elapsed_ms" -lt 200 ]
}

@test "AI error module loads quickly" {
    start=$(date +%s%N)
    zsh -c "export AI_ERROR_CACHE_DIR='$BATS_TEST_TMPDIR/ai-errors'; $AI_CORE; source '$REPO/config/22-ai-errors.zsh' 2>/dev/null" >/dev/null
    end=$(date +%s%N)
    elapsed_ms=$(( (end - start) / 1000000 ))

    [ "$elapsed_ms" -lt 100 ]
}

# =============================================================================
# AI Safety Tests
# =============================================================================

@test "AI suggestions don't block prompt" {
    run bash -c "cd '$REPO' && grep -E '\\} *&!' config/19-ai-suggestions.zsh"
    [ "$status" -eq 0 ]
}

@test "AI suggestions context includes directory, files and user" {
    local work="$BATS_TEST_TMPDIR/ctx"
    mkdir -p "$work"
    touch "$work/hello.txt"

    run zsh -c "cd '$work'; source '$REPO/themes/nord.zsh'; $AI_CORE; source '$REPO/config/19-ai-suggestions.zsh'; _ai_get_context"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dir: "*"/ctx"* ]]
    [[ "$output" == *"hello.txt"* ]]
    [[ "$output" == *"User: "* ]]
}

@test "AI suggestions redact secrets before sending context" {
    run zsh -c "source '$REPO/themes/nord.zsh'; $AI_CORE; source '$REPO/config/19-ai-suggestions.zsh'
        print -r -- 'export GITHUB_TOKEN=ghp_supersecretvalue123' | _ai_redact"
    [ "$status" -eq 0 ]
    [[ "$output" != *"ghp_supersecretvalue123"* ]]
}

# =============================================================================
# AI Color Integration
# =============================================================================

@test "AI suggestions are rendered with an explicit color" {
    # Ghost text and spinner are drawn through POSTDISPLAY highlight specs
    # (fg=NNN), the prompt-style %F{} form is not usable there.
    run bash -c "cd '$REPO' && grep -E \"fg=[0-9]+|%F\\{\" config/19-ai-suggestions.zsh"
    [ "$status" -eq 0 ]
}

@test "AI error messages use prompt colors" {
    run bash -c "cd '$REPO' && grep -E '(NORD_|%F\\{)' config/22-ai-errors.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Module Coverage Tests
# =============================================================================

@test "AI module files exist" {
    for module in \
        09-ai-core.zsh \
        09-ai-agy-daemon.zsh \
        09-ai-backend-gemini.zsh \
        09-ai-backend-openai.zsh \
        09-ai-backend-anthropic.zsh \
        10-ai.zsh \
        19-ai-suggestions.zsh \
        20-terminal-title.zsh \
        22-ai-errors.zsh \
        24-ai-command-not-found.zsh
    do
        [ -f "$REPO/config/$module" ] || { echo "missing config/$module"; return 1; }
    done
}

@test "the backend dispatcher entry points are defined by some module" {
    # Assert on the contract rather than on a file name, so a future move of
    # the dispatcher doesn't turn this suite red for the wrong reason.
    for fn in _ai_api_call _ai_resolve_model _ai_credentials_ok; do
        run bash -c "cd '$REPO' && grep -rlE '^${fn}\\(\\)' config/"
        [ "$status" -eq 0 ]
        [ -n "$output" ]
    done
}

@test "All AI modules are in .zshrc config_files" {
    local block
    block=$(sed -n '/config_files=(/,/^)/p' "$REPO/.zshrc")
    [ -n "$block" ]

    # Every AI module shipped in config/ must be wired into the load list --
    # this is what actually rots when modules are split or renamed.
    local f name
    for f in "$REPO"/config/*ai*.zsh; do
        name="$(basename "$f")"
        [[ "$block" == *"$name"* ]] || { echo "config/$name is never sourced by .zshrc"; return 1; }
    done

    # The dispatcher and every backend must come before the consumers.
    local core_line ai_line
    core_line=$(grep -n '09-ai-core.zsh' "$REPO/.zshrc" | head -1 | cut -d: -f1)
    ai_line=$(grep -n '^ *10-ai.zsh' "$REPO/.zshrc" | head -1 | cut -d: -f1)
    [ -n "$core_line" ]
    [ -n "$ai_line" ]
    [ "$core_line" -lt "$ai_line" ]
}
