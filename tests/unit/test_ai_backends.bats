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

@test "_ai_json_escape flattens raw control characters into valid JSON" {
    run zsh -c "
source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'
s=\$'a\x01b'
esc=\$(_ai_json_escape \"\$s\")
printf '{\"x\":\"%s\"}' \"\$esc\"
"
    [ "$status" -eq 0 ]
    echo "$output" | jq . >/dev/null
}

@test "_ai_credentials_ok is true for gemini cli mode when agy is installed" {
    local fake_bin_dir="$BATS_TEST_TMPDIR/fake-agy-creds-ok"
    mkdir -p "$fake_bin_dir"
    cat > "$fake_bin_dir/agy" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$fake_bin_dir/agy"

    run zsh -c "export PATH='$fake_bin_dir:\$PATH' GEMINI_AUTH_MODE=cli; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; _ai_credentials_ok && echo ok"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "_ai_credentials_ok is false for gemini cli mode when agy is missing" {
    run zsh -c "export PATH='/nonexistent-bin-only' GEMINI_AUTH_MODE=cli; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; _ai_credentials_ok"
    [ "$status" -eq 1 ]
}

@test "_ai_credentials_ok falls back to _ai_get_api_key for gemini api-key mode" {
    run zsh -c "export GOOGLE_API_KEY=test-key; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-backend-gemini.zsh'; _ai_credentials_ok"
    [ "$status" -eq 0 ]
}

# --- Gemini backend (api-key mode) ---

@test "gemini backend parses candidates text via curl+jq" {
    # The implementation runs curl under the external `timeout` binary, which
    # execs "curl" via a fresh PATH lookup -- a shell function named `curl`
    # in this process is invisible to that subprocess. So the mock must be a
    # real executable on PATH, not a shell function.
    local mock_bin="$BATS_TEST_TMPDIR/bin"
    local arg_log="$BATS_TEST_TMPDIR/curl-args-gemini.log"
    mkdir -p "$mock_bin"
    cat > "$mock_bin/curl" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$arg_log"
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

    # Assert URL/payload construction
    grep -q "generateContent" "$arg_log"
    grep -q "key=test-key" "$arg_log"
    local payload
    payload=$(grep -o "\-d {.*}" "$arg_log" | sed 's/^-d //')
    echo "$payload" | jq . >/dev/null
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
    local arg_log="$BATS_TEST_TMPDIR/curl-args-openai.log"
    mkdir -p "$mock_bin"
    cat > "$mock_bin/curl" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$arg_log"
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

    # Assert URL/headers/payload construction
    grep -q "https://api.openai.com/v1/chat/completions" "$arg_log"
    grep -q "Authorization: Bearer test-key" "$arg_log"
    local payload
    payload=$(grep -o "\-d {.*}" "$arg_log" | sed 's/^-d //')
    echo "$payload" | jq . >/dev/null
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

# --- Anthropic backend ---

@test "anthropic backend parses content text via curl+jq" {
    # The implementation runs curl under the external `timeout` binary, which
    # execs "curl" via a fresh PATH lookup -- a shell function named `curl`
    # in this process is invisible to that subprocess. So the mock must be a
    # real executable on PATH, not a shell function.
    local mock_bin="$BATS_TEST_TMPDIR/bin"
    local arg_log="$BATS_TEST_TMPDIR/curl-args-anthropic.log"
    mkdir -p "$mock_bin"
    cat > "$mock_bin/curl" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$arg_log"
printf '%s' '{"content":[{"type":"text","text":"mocked anthropic response"}]}'
MOCK
    chmod +x "$mock_bin/curl"

    run zsh -c '
export PATH="'"$mock_bin"':$PATH"
export ANTHROPIC_API_KEY=test-key
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-core.zsh"
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-backend-anthropic.zsh"
_ai_backend_anthropic_call "hello" "claude-haiku-4-5" 100 0.3 5
'
    [ "$status" -eq 0 ]
    [ "$output" = "mocked anthropic response" ]

    # Assert URL/headers/payload construction
    grep -q "https://api.anthropic.com/v1/messages" "$arg_log"
    grep -q "x-api-key: test-key" "$arg_log"
    grep -q "anthropic-version: 2023-06-01" "$arg_log"
    local payload
    payload=$(grep -o "\-d {.*}" "$arg_log" | sed 's/^-d //')
    echo "$payload" | jq . >/dev/null
}

@test "anthropic backend fails when no API key is configured" {
    run zsh -c '
unset ANTHROPIC_API_KEY
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-core.zsh"
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-backend-anthropic.zsh"
_ai_backend_anthropic_call "hello"
'
    [ "$status" -eq 1 ]
}

@test "anthropic backend fails clearly when jq is missing" {
    local no_jq_dir="$BATS_TEST_TMPDIR/no-jq-anthropic"
    mkdir -p "$no_jq_dir"
    local bin real
    for bin in curl timeout grep cut sed; do
        real=$(command -v "$bin") || continue
        ln -sf "$real" "$no_jq_dir/$bin"
    done
    run zsh -c '
export PATH="'"$no_jq_dir"'"
export ANTHROPIC_API_KEY=test-key
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-core.zsh"
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-backend-anthropic.zsh"
_ai_backend_anthropic_call "hello"
'
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires jq"* ]]
}

# --- Gemini backend (cli / Antigravity mode) ---

@test "gemini cli mode shells out to agy and parses .response" {
    local fake_bin_dir="$BATS_TEST_TMPDIR/fake-agy"
    mkdir -p "$fake_bin_dir"
    cat > "$fake_bin_dir/agy" <<'INNEREOF'
#!/usr/bin/env bash
echo '{"response":"mocked agy response","status":"SUCCESS"}'
INNEREOF
    chmod +x "$fake_bin_dir/agy"

    run zsh -c '
export PATH="'"$fake_bin_dir"':$PATH"
export GEMINI_AUTH_MODE=cli
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-core.zsh"
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-backend-gemini.zsh"
_ai_backend_gemini_call "hello" "gemini-3.5-flash-lite" 100 0.3 5
'
    [ "$status" -eq 0 ]
    [ "$output" = "mocked agy response" ]
}

@test "gemini cli mode fails clearly when agy is not installed" {
    run zsh -c '
export PATH="/nonexistent-bin-only"
export GEMINI_AUTH_MODE=cli
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-core.zsh"
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-backend-gemini.zsh"
_ai_backend_gemini_call "hello" "gemini-3.5-flash-lite"
'
    [ "$status" -eq 1 ]
    [[ "$output" == *"agy"*"not installed"* ]] || [[ "$output" == *"Antigravity CLI"* ]]
}

@test "gemini cli mode is not used by default (api-key stays default)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-backend-gemini.zsh'; echo \$GEMINI_AUTH_MODE"
    [ "$status" -eq 0 ]
    [ "$output" = "api-key" ]
}
