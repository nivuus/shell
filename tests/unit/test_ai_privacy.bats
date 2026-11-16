#!/usr/bin/env bats

# What the automatic AI calls send, and how. The terminal-title generator and
# the command-not-found lookup run without being asked, on command lines that
# can hold credentials. A mocked curl (first on PATH: nothing reaches the
# network) records its argument list and its standard input separately:
#   - the request must not contain a secret from the command line, token-shaped
#     or not, whatever language its key and the surrounding text are in;
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

    # Token-shaped (built here, so no credential-like literal sits in the
    # repository), under a header name no keyword list knows, next to a
    # comment in another language than English.
    SECRET="$(printf 'tok%02d' {10..20})A"
    # Short, not token-shaped, behind a key in Spanish: only the shape of the
    # assignment gives it away.
    SHORT="girasol$(( 6 * 7 ))"
    API_KEY="fake$(printf '%02d' {1..9})"
    COMMAND_LINE="curl -H 'X-Jeton: $SECRET' -d contraseña=$SHORT https://intra.example # le jeton de prod"
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

# refute_in TEXT FILE: fails when FILE holds TEXT. Not `! grep`: bats does not
# fail a test on a negated command that is not its last one, so such a line
# can never fail.
refute_in() {
    if grep -qF -- "$1" "$2"; then
        printf 'unexpected %q in %s\n' "$1" "$2" >&2
        return 1
    fi
}

_assert_private() {
    [ -s "$BATS_TEST_TMPDIR/curl-stdin" ]
    # The prompt did go out, with the secret masked.
    grep -q "le jeton de prod" "$BATS_TEST_TMPDIR/curl-stdin"
    refute_in "$SECRET" "$BATS_TEST_TMPDIR/curl-stdin"
    refute_in "$SHORT" "$BATS_TEST_TMPDIR/curl-stdin"
    grep -qF "contraseña=" "$BATS_TEST_TMPDIR/curl-stdin"
    # Neither the key nor the prompt is in the argument list.
    refute_in "$API_KEY" "$BATS_TEST_TMPDIR/curl-args"
    refute_in "le jeton de prod" "$BATS_TEST_TMPDIR/curl-args"
    refute_in "$SECRET" "$BATS_TEST_TMPDIR/curl-args"
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

# The other automatic and explicit callers. _ai_api_call is replaced by a
# recorder: what each caller hands it is what would be sent.
_run_caller() {
    run env HOME="$BATS_TEST_TMPDIR" LANG=C.UTF-8 RECORD="$BATS_TEST_TMPDIR/prompt" \
        zsh -fc "
source '$NIVUUS_SHELL_DIR/config/00-core.zsh'
source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'
_ai_credentials_ok() { return 0 }
_ai_api_call() { print -r -- \"\$1\" >> \"\$RECORD\"; print -r -- \"\${MOCK_REPLY:-ok}\" }
$1"
}

_assert_prompt_private() {
    [ -s "$BATS_TEST_TMPDIR/prompt" ]
    refute_in "$SHORT" "$BATS_TEST_TMPDIR/prompt"
    grep -qF "contraseña=" "$BATS_TEST_TMPDIR/prompt"
}

@test "ask, why, explain, ?git and ?gh send the question redacted" {
    _run_caller "
source '$NIVUUS_SHELL_DIR/config/10-ai.zsh'
ask 'pourquoi contraseña=$SHORT échoue ?'
why 'mysql contraseña=$SHORT'
explain 'mysql contraseña=$SHORT'
_nivuus_git_help 'contraseña=$SHORT'
_nivuus_gh_help 'contraseña=$SHORT'
_nivuus_ai_suggest 'contraseña=$SHORT'"
    [ "$status" -eq 0 ]
    _assert_prompt_private
    [ "$(grep -c 'contraseña=' "$BATS_TEST_TMPDIR/prompt")" -eq 6 ]
}

@test "error analysis sends the failed command and its directory redacted" {
    _run_caller "
source '$NIVUUS_SHELL_DIR/config/22-ai-errors.zsh' >/dev/null
_ai_analyze_error 'psql contraseña=$SHORT' 2 'Git repository' '/srv/contraseña=$SHORT'"
    [ "$status" -eq 0 ]
    _assert_prompt_private
}

@test "inline suggestion: the context is redacted, the typed line comes back whole" {
    mkdir -p "$BATS_TEST_TMPDIR/proj"
    printf 'contraseña: %s\n' "$SHORT" > "$BATS_TEST_TMPDIR/proj/README.md"
    cd "$BATS_TEST_TMPDIR/proj"
    # The model completes the line it was shown, placeholder included.
    MOCK_REPLY='mysql contraseña=***REDACTED*** -e "select 1"' _run_caller "
source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions-generate.zsh'
_ai_generate 'mysql contraseña=$SHORT'"
    [ "$status" -eq 0 ]
    _assert_prompt_private
    # Labels are this code's and stay readable; values are redacted.
    grep -qF "README.md preview:" "$BATS_TEST_TMPDIR/prompt"
    grep -qF "Dir: $BATS_TEST_TMPDIR/proj" "$BATS_TEST_TMPDIR/prompt"
    [ "$output" = "mysql contraseña=$SHORT -e \"select 1\"" ]
}

@test "inline suggestion: a reply that does not extend the shown line is dropped" {
    MOCK_REPLY='rm -rf /' _run_caller "
source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions-generate.zsh'
_ai_generate 'mysql contraseña=$SHORT'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
