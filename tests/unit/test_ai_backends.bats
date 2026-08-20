#!/usr/bin/env bats

# Unit tests for the AI backend dispatcher and per-provider backends
# (config/09-ai-core.zsh, config/09-ai-backend-*.zsh)

setup() {
    unset AI_BACKEND GEMINI_MODEL OPENAI_MODEL ANTHROPIC_MODEL
    unset GOOGLE_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_AUTH_MODE
}

# --- Dispatcher ---

@test "AI_BACKEND defaults to gemini when unset" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; echo \$AI_BACKEND"
    [ "$status" -eq 0 ]
    [ "$output" = "gemini" ]
}

@test "_ai_resolve_model returns the gemini default" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; _ai_resolve_model"
    [ "$status" -eq 0 ]
    [ "$output" = "gemini-3.5-flash-lite" ]
}

@test "_ai_resolve_model returns the openai default when AI_BACKEND=openai" {
    run zsh -c "export AI_BACKEND=openai; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; _ai_resolve_model"
    [ "$status" -eq 0 ]
    [ "$output" = "gpt-5.6-luna" ]
}

@test "_ai_resolve_model returns the anthropic default when AI_BACKEND=anthropic" {
    run zsh -c "export AI_BACKEND=anthropic; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; _ai_resolve_model"
    [ "$status" -eq 0 ]
    [ "$output" = "claude-haiku-4-5" ]
}

@test "_ai_resolve_model honors a per-backend model override" {
    run zsh -c "export AI_BACKEND=openai OPENAI_MODEL=gpt-5.6-terra; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; _ai_resolve_model"
    [ "$status" -eq 0 ]
    [ "$output" = "gpt-5.6-terra" ]
}

@test "_ai_api_call rejects an unknown AI_BACKEND with a clear error" {
    run zsh -c "export AI_BACKEND=bogus; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; _ai_api_call hello"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown backend 'bogus'"* ]]
}

# --- Gemini backend (api-key mode) ---

@test "gemini backend parses candidates text via curl+jq" {
    # The implementation runs curl under the external `timeout` binary, which
    # execs "curl" via a fresh PATH lookup -- a shell function named `curl`
    # in this process is invisible to that subprocess. So the mock must be a
    # real executable on PATH, not a shell function.
    local mock_bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$mock_bin"
    cat > "$mock_bin/curl" <<'MOCK'
#!/usr/bin/env bash
printf '%s' '{"candidates":[{"content":{"parts":[{"text":"mocked gemini response"}]}}]}'
MOCK
    chmod +x "$mock_bin/curl"

    run zsh -c '
export PATH="'"$mock_bin"':$PATH"
export GOOGLE_API_KEY=test-key
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-core.zsh"
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-backend-gemini.zsh"
_ai_backend_gemini_call "hello" "gemini-3.5-flash-lite" 100 0.3 5
'
    [ "$status" -eq 0 ]
    [ "$output" = "mocked gemini response" ]
}

@test "gemini backend fails when no API key is configured" {
    run zsh -c '
unset GOOGLE_API_KEY
export HOME="'"$BATS_TEST_TMPDIR"'"
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-core.zsh"
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-backend-gemini.zsh"
_ai_backend_gemini_call "hello"
'
    [ "$status" -eq 1 ]
}

# --- OpenAI backend ---

@test "openai backend parses choices content via curl+jq" {
    # The implementation runs curl under the external `timeout` binary, which
    # execs "curl" via a fresh PATH lookup -- a shell function named `curl`
    # in this process is invisible to that subprocess. So the mock must be a
    # real executable on PATH, not a shell function.
    local mock_bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$mock_bin"
    cat > "$mock_bin/curl" <<'MOCK'
#!/usr/bin/env bash
printf '%s' '{"choices":[{"message":{"content":"mocked openai response"}}]}'
MOCK
    chmod +x "$mock_bin/curl"

    run zsh -c '
export PATH="'"$mock_bin"':$PATH"
export OPENAI_API_KEY=test-key
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-core.zsh"
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-backend-openai.zsh"
_ai_backend_openai_call "hello" "gpt-5.6-luna" 100 0.3 5
'
    [ "$status" -eq 0 ]
    [ "$output" = "mocked openai response" ]
}

@test "openai backend fails when no API key is configured" {
    run zsh -c '
unset OPENAI_API_KEY
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-core.zsh"
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-backend-openai.zsh"
_ai_backend_openai_call "hello"
'
    [ "$status" -eq 1 ]
}

@test "openai backend fails clearly when jq is missing" {
    local no_jq_dir="$BATS_TEST_TMPDIR/no-jq-openai"
    mkdir -p "$no_jq_dir"
    local bin real
    for bin in curl timeout grep cut sed; do
        real=$(command -v "$bin") || continue
        ln -sf "$real" "$no_jq_dir/$bin"
    done
    run zsh -c '
export PATH="'"$no_jq_dir"'"
export OPENAI_API_KEY=test-key
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-core.zsh"
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-backend-openai.zsh"
_ai_backend_openai_call "hello"
'
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires jq"* ]]
}
