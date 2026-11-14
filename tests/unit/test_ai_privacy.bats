#!/usr/bin/env bats

# What the automatic AI calls send, and how. The terminal-title generator and
# the command-not-found lookup run without being asked, on command lines that
# can hold credentials. A mocked curl (first on PATH: nothing reaches the
# network) records its argument list and its standard input separately:
#   - the request must not contain a token-shaped value from the command line,
#     whatever language the surrounding text is in;
#   - the argument list, which every local user can read in the process table,
#     must contain neither the API key nor the prompt.

setup() {
    NIVUUS_SHELL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export NIVUUS_SHELL_DIR
    unset AI_BACKEND GEMINI_MODEL OPENAI_MODEL ANTHROPIC_MODEL GEMINI_AUTH_MODE
    unset GOOGLE_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY

    MOCK_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$MOCK_BIN"
    cat > "$MOCK_BIN/curl" <<MOCK
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/curl-args"
cat >> "$BATS_TEST_TMPDIR/curl-stdin"
printf '%s' '{"choices":[{"message":{"content":"Mock title"}}],"content":[{"text":"Mock title"}],"candidates":[{"content":{"parts":[{"text":"Mock title"}]}}]}'
MOCK
    chmod +x "$MOCK_BIN/curl"

    # Token-shaped, under a header name no keyword list knows, next to a
    # comment in another language than English.
    SECRET='Zq7Lm3Nx9Pw2Rt5Vb8Kc4Hd6Fj1Gs0YaQe'
    API_KEY='key-under-test-0123456789'
    COMMAND_LINE="curl -H 'X-Jeton: $SECRET' https://intra.example # le jeton de prod"
}

_run_title() {
    local backend="$1" key_var="$2"
    run env PATH="$MOCK_BIN:$PATH" HOME="$BATS_TEST_TMPDIR" AI_BACKEND="$backend" \
        "$key_var=$API_KEY" TERM=xterm-256color ENABLE_AI_TERMINAL_TITLES=true \
        AI_TITLE_CACHE_DIR="$BATS_TEST_TMPDIR/titles-$backend" \
        zsh -c "
source '$NIVUUS_SHELL_DIR/config/00-core.zsh'
source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'
source '$NIVUUS_SHELL_DIR/config/09-ai-backend-gemini.zsh'
source '$NIVUUS_SHELL_DIR/config/09-ai-backend-openai.zsh'
source '$NIVUUS_SHELL_DIR/config/09-ai-backend-anthropic.zsh'
source '$NIVUUS_SHELL_DIR/config/20-terminal-title.zsh' >/dev/null
_AI_TITLE_SESSION_HISTORY=(${COMMAND_LINE@Q})
_ai_get_terminal_title ${COMMAND_LINE@Q} project
"
}

_assert_private() {
    [ -s "$BATS_TEST_TMPDIR/curl-stdin" ]
    # The prompt did go out, with the secret masked.
    grep -q "le jeton de prod" "$BATS_TEST_TMPDIR/curl-stdin"
    ! grep -qF "$SECRET" "$BATS_TEST_TMPDIR/curl-stdin"
    # Neither the key nor the prompt is in the argument list.
    ! grep -qF "$API_KEY" "$BATS_TEST_TMPDIR/curl-args"
    ! grep -qF "le jeton de prod" "$BATS_TEST_TMPDIR/curl-args"
    ! grep -qF "$SECRET" "$BATS_TEST_TMPDIR/curl-args"
}

@test "title generator, gemini: no secret in the request, no key or prompt in curl's arguments" {
    _run_title gemini GOOGLE_API_KEY
    [ "$status" -eq 0 ]
    [ "$output" = "Mock title" ]
    _assert_private
    grep -qF "$API_KEY" "$BATS_TEST_TMPDIR/curl-stdin"
}

@test "title generator, openai: no secret in the request, no key or prompt in curl's arguments" {
    _run_title openai OPENAI_API_KEY
    [ "$status" -eq 0 ]
    [ "$output" = "Mock title" ]
    _assert_private
    grep -qF "Authorization: Bearer $API_KEY" "$BATS_TEST_TMPDIR/curl-stdin"
}

@test "title generator, anthropic: no secret in the request, no key or prompt in curl's arguments" {
    _run_title anthropic ANTHROPIC_API_KEY
    [ "$status" -eq 0 ]
    [ "$output" = "Mock title" ]
    _assert_private
    grep -qF "x-api-key: $API_KEY" "$BATS_TEST_TMPDIR/curl-stdin"
}

@test "command-not-found lookup: no secret in the request, no key or prompt in curl's arguments" {
    run env PATH="$MOCK_BIN:$PATH" HOME="$BATS_TEST_TMPDIR" AI_BACKEND=openai \
        OPENAI_API_KEY="$API_KEY" AI_COMMAND_NOT_FOUND_CACHE_DIR="$BATS_TEST_TMPDIR/cnf" \
        zsh -c "
source '$NIVUUS_SHELL_DIR/config/00-core.zsh'
source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'
source '$NIVUUS_SHELL_DIR/config/09-ai-backend-openai.zsh'
source '$NIVUUS_SHELL_DIR/config/24-ai-command-not-found.zsh'
_ai_cnf_supported_managers() { print -r -- apt-get }
_ai_cnf_ai_lookup zzqtool ${COMMAND_LINE@Q} 'OS: Linux'
"
    _assert_private
}

@test "redaction keeps ordinary text in any script and masks only token-shaped values" {
    run zsh -c "
source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'
print -r -- 'cd ~/projets/été && grep 東京 notes.txt # مرحبا sha 1a2b' | _ai_redact
print -r -- 'export X=$SECRET' | _ai_redact
"
    [ "${lines[0]}" = 'cd ~/projets/été && grep 東京 notes.txt # مرحبا sha 1a2b' ]
    [[ "${lines[1]}" == 'export X='*REDACTED* ]]
    [[ "${lines[1]}" != *"$SECRET"* ]]
}
