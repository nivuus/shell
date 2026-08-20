#!/usr/bin/env bats

# Integration tests for AI workflow (suggestions, commands, error handling)

# =============================================================================
# AI Module Integration Tests
# =============================================================================

@test "AI module loads without errors" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/10-ai.zsh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "AI command functions are defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c -E '(why\\(\\)|explain\\(\\)|ask\\(\\)|aihelp\\(\\))' config/10-ai.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 3 ]
}

@test "AI module checks for gemini command" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'command -v gemini' config/10-ai.zsh"
    [ "$status" -eq 0 ]
}

@test "AI help shows command information" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 'aihelp()' config/10-ai.zsh | grep -E '(\\?\\?|why|explain)'"
    [ "$status" -eq 0 ]
}

@test "aihelp shows the active backend and model" {
    run zsh -c "export AI_BACKEND=openai OPENAI_API_KEY=test-key; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-backend-gemini.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-backend-openai.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-backend-anthropic.zsh'; source '$NIVUUS_SHELL_DIR/config/10-ai.zsh'; aihelp"
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

    run zsh -c "export PATH='$fake_bin_dir:\$PATH' GEMINI_AUTH_MODE=cli; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-backend-gemini.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-backend-openai.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-backend-anthropic.zsh'; source '$NIVUUS_SHELL_DIR/config/10-ai.zsh'; aihelp"
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

    run zsh -c "export PATH=\"$fake_bin_dir:\$PATH\" GEMINI_AUTH_MODE=cli; unset GOOGLE_API_KEY; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-backend-gemini.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-backend-openai.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-backend-anthropic.zsh'; source '$NIVUUS_SHELL_DIR/config/10-ai.zsh'; ask 'test question'"
    [ "$status" -eq 0 ]
    [ "$output" = "mocked e2e response" ]
}

# =============================================================================
# AI Suggestions Module Tests
# =============================================================================

@test "AI suggestions module loads" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh' 2>/dev/null && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "AI suggestions can be disabled" {
    run zsh -c "export ENABLE_AI_SUGGESTIONS=false && source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh' 2>/dev/null && echo 'loaded'"
    [ "$status" -eq 0 ]
}

@test "AI suggestions hook is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'precmd' config/19-ai-suggestions.zsh"
    [ "$status" -eq 0 ]
}

@test "AI suggestions use SIGUSR1" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'SIGUSR1' config/19-ai-suggestions.zsh"
    [ "$status" -eq 0 ]
}

@test "AI suggestions run in background" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '&)' config/19-ai-suggestions.zsh"
    [ "$status" -eq 0 ]
}

@test "AI suggestions have cache" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '_AI_CACHE' config/19-ai-suggestions.zsh"
    [ "$status" -eq 0 ]
}

@test "AI suggestions cache has TTL" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -E '(cache_ttl|CACHE_TTL|TTL.*300)' config/19-ai-suggestions.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# AI Inline Mode Tests
# =============================================================================

@test "AI inline mode feature toggle exists" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'AI_INLINE_MODE' config/19-ai-suggestions.zsh"
    [ "$status" -eq 0 ]
}

@test "AI inline mode respects toggle" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 5 'AI_INLINE_MODE' config/19-ai-suggestions.zsh | grep 'if'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# AI Error Handling Module Tests
# =============================================================================

@test "AI error module loads" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/22-ai-errors.zsh' 2>/dev/null && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "AI error module has preexec hook" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'preexec' config/22-ai-errors.zsh"
    [ "$status" -eq 0 ]
}

@test "AI error module stores exit codes" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -E '(_LAST_EXIT|_LAST_COMMAND|exit.*code)' config/22-ai-errors.zsh"
    [ "$status" -eq 0 ]
}

@test "AI error module suggests fixes" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -E '(suggest|fix|error.*help)' config/22-ai-errors.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# AI Terminal Titles Module Tests
# =============================================================================

@test "AI terminal titles module loads" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/23-ai-terminal-titles.zsh' 2>/dev/null && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "AI terminal titles can be disabled" {
    run zsh -c "export ENABLE_AI_TERMINAL_TITLES=false && source '$NIVUUS_SHELL_DIR/config/23-ai-terminal-titles.zsh' 2>/dev/null && echo 'loaded'"
    [ "$status" -eq 0 ]
}

@test "AI terminal titles use preexec" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'preexec' config/23-ai-terminal-titles.zsh"
    [ "$status" -eq 0 ]
}

@test "AI terminal titles set terminal escape codes" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -E '(\\\\033|ESC|title)' config/23-ai-terminal-titles.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# AI Command Tests
# =============================================================================

@test "AI commands use gemini model variable" {
    # GEMINI_MODEL is now resolved centrally by _ai_resolve_model() in
    # config/09-ai-core.zsh (config/10-ai.zsh only calls _ai_resolve_model).
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'GEMINI_MODEL' config/09-ai-core.zsh"
    [ "$status" -eq 0 ]
}

@test "AI commands default to gemini-2.0-flash" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'gemini-2.0-flash' config/10-ai.zsh"
    [ "$status" -eq 0 ]
}

@test "AI commands support temperature setting" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -E '(temperature|TEMPERATURE)' config/10-ai.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Full AI Workflow Integration
# =============================================================================

@test "AI modules load in correct order" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/10-ai.zsh' && source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh' 2>/dev/null && source '$NIVUUS_SHELL_DIR/config/22-ai-errors.zsh' 2>/dev/null && echo 'all loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"all loaded"* ]]
}

@test "AI modules work together with prompt" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && source '$NIVUUS_SHELL_DIR/config/10-ai.zsh' && source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh' 2>/dev/null && echo 'integrated'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"integrated"* ]]
}

@test "Full shell loads all AI modules" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/.zshrc' 2>/dev/null && typeset -f _ai_suggest"
    [ "$status" -eq 0 ]
}

# =============================================================================
# AI Feature Toggles
# =============================================================================

@test "ENABLE_AI_SUGGESTIONS toggle exists in .zshrc" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'ENABLE_AI_SUGGESTIONS' .zshrc"
    [ "$status" -eq 0 ]
}

@test "ENABLE_AI_TERMINAL_TITLES toggle exists in .zshrc" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'ENABLE_AI_TERMINAL_TITLES' .zshrc"
    [ "$status" -eq 0 ]
}

@test "AI_INLINE_MODE toggle exists in .zshrc" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'AI_INLINE_MODE' .zshrc"
    [ "$status" -eq 0 ]
}

@test "ENABLE_AI_AUTO_DEBOUNCE toggle exists in .zshrc" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'ENABLE_AI_AUTO_DEBOUNCE' .zshrc"
    [ "$status" -eq 0 ]
}

# =============================================================================
# AI Performance Tests
# =============================================================================

@test "AI modules load quickly" {
    start=$(date +%s%N)
    zsh -c "source '$NIVUUS_SHELL_DIR/config/10-ai.zsh' && source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh' 2>/dev/null" >/dev/null
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

# =============================================================================
# AI Safety Tests
# =============================================================================

@test "AI suggestions don't block prompt" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'background\|async\|&)' config/19-ai-suggestions.zsh | head -3"
    [ "$status" -eq 0 ]
}

@test "AI error handling is non-blocking" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 'preexec' config/22-ai-errors.zsh | grep '&'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# AI Nord Color Integration
# =============================================================================

@test "AI suggestions use Nord colors" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -E '(NORD_|%F\\{)' config/19-ai-suggestions.zsh"
    [ "$status" -eq 0 ]
}

@test "AI error messages use Nord colors" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -E '(NORD_|%F\\{)' config/22-ai-errors.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# AI Cache Behavior
# =============================================================================

@test "AI suggestions cache prevents duplicate calls" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 '_AI_CACHE' config/19-ai-suggestions.zsh | grep -E '(if.*cache|return)'"
    [ "$status" -eq 0 ]
}

@test "AI cache has reasonable TTL (5 minutes)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -E '(300|5.*min|cache_ttl.*300)' config/19-ai-suggestions.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Module Coverage Tests
# =============================================================================

@test "AI module files exist" {
    [ -f "$NIVUUS_SHELL_DIR/config/10-ai.zsh" ]
    [ -f "$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh" ]
    [ -f "$NIVUUS_SHELL_DIR/config/22-ai-errors.zsh" ]
    [ -f "$NIVUUS_SHELL_DIR/config/23-ai-terminal-titles.zsh" ]
}

@test "All AI modules are in .zshrc config_files" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && sed -n '/config_files=(/,/)$/p' .zshrc | grep -c -E '(10-ai|19-ai-suggestions|22-ai-errors|23-ai-terminal-titles)'"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -eq 4 ]
}
