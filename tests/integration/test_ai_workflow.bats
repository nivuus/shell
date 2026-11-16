#!/usr/bin/env bats

# Integration tests for the AI modules: they load together, the commands
# answer, the suggestion cache and the error capture behave. Every test runs
# the modules in zsh; none reads their source text. The behaviour of each
# module in depth lives in its unit tests (test_ai_backends, test_ai_privacy,
# test_ai_redact, test_ai_suggestions, test_terminal_title,
# test_ai_command_not_found).

bats_require_minimum_version 1.5.0

load "${BATS_TEST_DIRNAME}/../helpers/pty"

setup() {
    # Test the tree this file belongs to, never whatever NIVUUS_SHELL_DIR the
    # environment happens to point at.
    NIVUUS_SHELL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export NIVUUS_SHELL_DIR
    AI_CORE="source '$NIVUUS_SHELL_DIR/config/00-core.zsh'
source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'
source '$NIVUUS_SHELL_DIR/config/09-ai-backend-gemini.zsh'
source '$NIVUUS_SHELL_DIR/config/09-ai-backend-openai.zsh'
source '$NIVUUS_SHELL_DIR/config/09-ai-backend-anthropic.zsh'"
}

# =============================================================================
# Commands
# =============================================================================

@test "AI module loads without errors" {
    run --separate-stderr zsh -c "$AI_CORE; source '$NIVUUS_SHELL_DIR/config/10-ai.zsh'"
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
}

@test "aihelp lists the AI commands" {
    run zsh -c "export AI_BACKEND=openai OPENAI_API_KEY=test-key; $AI_CORE; source '$NIVUUS_SHELL_DIR/config/10-ai.zsh'; aihelp"
    [ "$status" -eq 0 ]
    [[ "$output" == *"??"* ]]
    [[ "$output" == *"why"* ]]
    [[ "$output" == *"explain"* ]]
    [[ "$output" == *"ask"* ]]
}

@test "aihelp shows the active backend and model" {
    run zsh -c "export AI_BACKEND=openai OPENAI_API_KEY=test-key; $AI_CORE; source '$NIVUUS_SHELL_DIR/config/10-ai.zsh'; aihelp"
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

    run zsh -c "export PATH='$fake_bin_dir:\$PATH' GEMINI_AUTH_MODE=cli; $AI_CORE; source '$NIVUUS_SHELL_DIR/config/10-ai.zsh'; aihelp"
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

    run zsh -c "export PATH=\"$fake_bin_dir:\$PATH\" GEMINI_AUTH_MODE=cli AGY_DAEMON_ENABLED=false; unset GOOGLE_API_KEY; $AI_CORE; source '$NIVUUS_SHELL_DIR/config/10-ai.zsh'; ask 'test question'"
    [ "$status" -eq 0 ]
    [ "$output" = "mocked e2e response" ]
}

# =============================================================================
# Suggestions
# =============================================================================

@test "AI suggestions module loads" {
    run --separate-stderr zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh'; $AI_CORE; source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh'"
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
}

@test "AI suggestions can be disabled" {
    run zsh -c "export ENABLE_AI_SUGGESTIONS=false; $AI_CORE; source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh'; (( ! \$+functions[_ai_generate] ))"
    [ "$status" -eq 0 ]
}

# A second request for the same prefix in the same directory within five
# minutes is answered from the cache; an older entry is not.
@test "a suggestion is served from the cache for five minutes, then asked again" {
    run zsh -c "$AI_CORE
source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions-generate.zsh'
_ai_credentials_ok() { return 0 }
# _ai_generate calls the backend in a command substitution: count in a file.
_ai_api_call() { print >> '$BATS_TEST_TMPDIR/calls'; print -r -- 'git status --short' }
_ai_generate 'git st' >/dev/null
_ai_generate 'git st' >/dev/null
print -r -- \"after two: \$(wc -l < '$BATS_TEST_TMPDIR/calls')\"
(( _AI_CACHE_TIME[git st_\$PWD] -= 301 ))
_ai_generate 'git st'
print -r -- \"after expiry: \$(wc -l < '$BATS_TEST_TMPDIR/calls')\""
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "after two: 1" ]
    [ "${lines[1]}" = "git status --short" ]
    [ "${lines[2]}" = "after expiry: 2" ]
}

# Generation runs in a background job; the shell stores what it returns, so
# the next request for the same line is a hit.
@test "a suggestion generated in the background is cached by the shell" {
    run zsh -c "$AI_CORE
source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh'
_ai_cancel_animation() { : }; _ai_set_postdisplay() { : }
_ai_clear_postdisplay() { : }; _ai_restore_autosuggest() { : }
_AI_TEMP_FILE='$BATS_TEST_TMPDIR/result'
print -r -- 'git status --short' > \$_AI_TEMP_FILE
_AI_GENERATE_KEY=\"git st_\$PWD\"
_ai_handle_completion
print -r -- \"\${_AI_CACHE[git st_\$PWD]}|\${+_AI_CACHE_TIME[git st_\$PWD]}\""
    [ "$status" -eq 0 ]
    [ "$output" = "git status --short|1" ]
}

# =============================================================================
# Error capture
# =============================================================================

@test "AI error module loads" {
    run --separate-stderr zsh -c "export AI_BACKEND=openai OPENAI_API_KEY=test-key; $AI_CORE; source '$NIVUUS_SHELL_DIR/config/22-ai-errors.zsh'"
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
}

# The module loads only when a backend is usable: a fake key, nothing is sent.
@test "a failed command is recorded with its exit code, a success clears it" {
    run zsh -c "export AI_BACKEND=openai OPENAI_API_KEY=test-key; $AI_CORE
source '$NIVUUS_SHELL_DIR/config/22-ai-errors.zsh'
_ai_error_preexec 'make deploy'
(exit 3); _ai_error_precmd
print -r -- \"\$_AI_LAST_COMMAND|\$_AI_LAST_ERROR_CODE|\$_AI_ERROR_AVAILABLE\"
_ai_error_preexec 'true'
true; _ai_error_precmd
print -r -- \"\$_AI_ERROR_AVAILABLE\""
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "make deploy|3|true" ]
    [ "${lines[1]}" != "true" ]
}

# =============================================================================
# Full shell
# =============================================================================

@test "AI modules load in correct order" {
    run --separate-stderr zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh'; $AI_CORE; source '$NIVUUS_SHELL_DIR/config/10-ai.zsh'; source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh'; source '$NIVUUS_SHELL_DIR/config/22-ai-errors.zsh'"
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
}

@test "AI modules work together with prompt" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && $AI_CORE && source '$NIVUUS_SHELL_DIR/config/10-ai.zsh' && source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh' 2>/dev/null && echo 'integrated'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"integrated"* ]]
}

# What "every AI module is listed in .zshrc" was meant to protect: loading the
# real .zshrc, at a terminal and with a usable backend (a fake key, nothing is
# sent), gives the shell each module's entry point.
@test "the full shell defines the entry point of every AI module" {
    mkdir -p "$BATS_TEST_TMPDIR/home"
    pty_run "export HOME='$BATS_TEST_TMPDIR/home' TERM=xterm-256color AI_BACKEND=openai OPENAI_API_KEY=test-key ENABLE_AUTOUPDATE=false
source '$NIVUUS_SHELL_DIR/.zshrc'
for f in _ai_api_call _ai_redact_text aihelp _ai_generate _terminal_title_preexec _ai_analyze_error command_not_found_handler; do
    (( \$+functions[\$f] )) || print -r -- \"undefined function: \$f\"
done
print -r -- checked"
    [ "$status" -eq 0 ]
    [[ "$output" == *checked* ]]
    [[ "$output" != *"undefined function:"* ]]
}

# =============================================================================
# Performance
# =============================================================================

@test "AI modules load quickly" {
    start=$(date +%s%N)
    zsh -c "$AI_CORE; source '$NIVUUS_SHELL_DIR/config/10-ai.zsh' && source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh' 2>/dev/null" >/dev/null
    end=$(date +%s%N)
    elapsed_ms=$(( (end - start) / 1000000 ))

    [ "$elapsed_ms" -lt 100 ]
}

@test "AI error module loads quickly" {
    start=$(date +%s%N)
    zsh -c "source '$NIVUUS_SHELL_DIR/config/22-ai-errors.zsh' 2>/dev/null" >/dev/null
    end=$(date +%s%N)
    elapsed_ms=$(( (end - start) / 1000000 ))

    [ "$elapsed_ms" -lt 50 ]
}
