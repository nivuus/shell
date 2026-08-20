#!/usr/bin/env bats

# Unit tests for terminal markdown rendering
# (config/09-ai-core.zsh, config/10-ai.zsh, config/17-colorization.zsh)

setup() {
    unset NIVUUS_MARKDOWN_RENDERER _NIVUUS_CACHED_MD_RENDERER ENABLE_MARKDOWN_RENDERING FORCE_MARKDOWN_COLOR NIVUUS_COLORIZATION_LOADED
}

@test "_nivuus_get_markdown_renderer returns explicit user override" {
    run zsh -c "export NIVUUS_MARKDOWN_RENDERER=glow; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; _nivuus_get_markdown_renderer"
    [ "$status" -eq 0 ]
    [ "$output" = "glow" ]
}

@test "_nivuus_get_markdown_renderer detects rich when python3 has rich.markdown" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; _nivuus_get_markdown_renderer"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^(glow|mdcat|rich|bat|batcat|cat)$ ]]
}

@test "_render_markdown passes plain text when output is not a terminal" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; _render_markdown '# Hello World'"
    [ "$status" -eq 0 ]
    [ "$output" = "# Hello World" ]
}

@test "_render_markdown passes plain text when ENABLE_MARKDOWN_RENDERING=false" {
    run zsh -c "export ENABLE_MARKDOWN_RENDERING=false FORCE_MARKDOWN_COLOR=true; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; _render_markdown '# Plain Text'"
    [ "$status" -eq 0 ]
    [ "$output" = "# Plain Text" ]
}

@test "_render_markdown passes plain text from stdin when not a terminal" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; echo '## From Stdin' | _render_markdown"
    [ "$status" -eq 0 ]
    [ "$output" = "## From Stdin" ]
}

@test "_render_markdown renders file argument" {
    local tmp_md="$BATS_TEST_TMPDIR/test.md"
    echo "# File Title" > "$tmp_md"
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; _render_markdown '$tmp_md'"
    [ "$status" -eq 0 ]
    [ "$output" = "# File Title" ]
}

@test "_render_markdown invokes rich renderer when FORCE_MARKDOWN_COLOR=true and renderer is rich" {
    run zsh -c "export NIVUUS_MARKDOWN_RENDERER=rich FORCE_MARKDOWN_COLOR=true; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; _render_markdown '# Formatted Title'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Formatted Title"* ]]
}

@test "mdview function is available in 17-colorization.zsh" {
    run zsh -c "unset NIVUUS_COLORIZATION_LOADED; export TERM=xterm-256color; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; source '$NIVUUS_SHELL_DIR/config/17-colorization.zsh'; typeset -f mdview"
    [ "$status" -eq 0 ]
    [[ "$output" == *"mdview ()"* ]]
}

@test "markdown alias points to mdview in 17-colorization.zsh" {
    run zsh -c "unset NIVUUS_COLORIZATION_LOADED; export TERM=xterm-256color; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; source '$NIVUUS_SHELL_DIR/config/17-colorization.zsh'; alias markdown"
    [ "$status" -eq 0 ]
    [[ "$output" == *"markdown=mdview"* ]]
}

@test "ask renders markdown output from AI backend" {
    local fake_bin_dir="$BATS_TEST_TMPDIR/fake-agy-ask"
    mkdir -p "$fake_bin_dir"
    cat > "$fake_bin_dir/agy" <<'EOF'
#!/usr/bin/env bash
echo '{"response":"### Reponse IA\n**Texte gras**","status":"SUCCESS"}'
EOF
    chmod +x "$fake_bin_dir/agy"

    run zsh -c "export PATH=\"$fake_bin_dir:\$PATH\" GEMINI_AUTH_MODE=cli; unset GOOGLE_API_KEY; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-backend-gemini.zsh'; source '$NIVUUS_SHELL_DIR/config/10-ai.zsh'; ask 'question'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Reponse IA"* ]]
}

@test "why renders markdown output from AI backend" {
    local fake_bin_dir="$BATS_TEST_TMPDIR/fake-agy-why"
    mkdir -p "$fake_bin_dir"
    cat > "$fake_bin_dir/agy" <<'EOF'
#!/usr/bin/env bash
echo '{"response":"Explanation: `tar -xzf` extracts gzip archive","status":"SUCCESS"}'
EOF
    chmod +x "$fake_bin_dir/agy"

    run zsh -c "export PATH=\"$fake_bin_dir:\$PATH\" GEMINI_AUTH_MODE=cli; unset GOOGLE_API_KEY; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-backend-gemini.zsh'; source '$NIVUUS_SHELL_DIR/config/10-ai.zsh'; why 'tar -xzf file.tar.gz'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"tar -xzf"* ]]
}
