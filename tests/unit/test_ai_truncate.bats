#!/usr/bin/env bats
# Truncation of text sent to, or received from, the AI backend
# (_ai_truncate in config/09-ai-core.zsh, used by config/20-terminal-title.zsh
# and config/19-ai-suggestions-generate.zsh).
#
# `cut -c` counts bytes: it cut a Japanese character or an emoji in the
# middle and left invalid UTF-8 in the terminal title and in the JSON body
# sent to the provider. Every case runs the real function in zsh with a
# UTF-8 locale and checks the result is valid UTF-8.

setup() {
    NIVUUS_SHELL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export NIVUUS_SHELL_DIR
    export LANG=C.UTF-8 LC_ALL=C.UTF-8
}

# truncate <max> <text>: print _ai_truncate's result between brackets.
truncate() {
    zsh -c "source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh' >/dev/null 2>&1
_ai_truncate \"\$1\" \"\$2\"; print -r -- \"[\$REPLY]\"" zsh "$@"
}

valid_utf8() {
    printf '%s' "$1" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1
}

@test "text within the limit is returned unchanged" {
    run truncate 30 "deploy 日本語 🚀"
    [ "$output" = "[deploy 日本語 🚀]" ]
}

@test "Japanese is cut between characters, not inside one" {
    run truncate 3 "日本語テスト"
    [ "$output" = "[日本語]" ]
    valid_utf8 "$output"
}

@test "Arabic is cut between characters, and keeps its harakat" {
    run truncate 5 "مرحبا بالعالم"
    [ "$output" = "[مرحبا]" ]
    valid_utf8 "$output"
    # مَ = meem + fatha (width 0): a cut between them drops both, a cut
    # after the fatha keeps both.
    run truncate 1 $'مَر'
    [ "$output" = "[]" ]
    run truncate 2 $'مَر'
    [ "$output" = $'[مَ]' ]
}

@test "a combining mark is never separated from its letter" {
    # "été" in decomposed form: e U+0301 t e U+0301.
    run truncate 1 $'été'
    [ "$output" = "[]" ]
    run truncate 2 $'été'
    [ "$output" = $'[é]' ]
    run truncate 4 $'été'
    [ "$output" = $'[ét]' ]
    valid_utf8 "$output"
}

@test "an emoji is kept whole or dropped whole" {
    run truncate 1 "🚀 Deploying"
    [ "$output" = "[🚀]" ]
    valid_utf8 "$output"
    # 👩‍💻 = woman, zero-width joiner, laptop: no dangling joiner.
    run truncate 2 $'\U0001F469‍\U0001F4BBx'
    [ "$output" = $'[\U0001F469]' ]
    run truncate 1 $'\U0001F469‍\U0001F4BBx'
    [ "$output" = "[]" ]
    # A flag is a pair of regional indicators: never half of one.
    run truncate 2 $'a\U0001F1EB\U0001F1F7'
    [ "$output" = "[a]" ]
    run truncate 3 $'a\U0001F1EB\U0001F1F7b'
    [ "$output" = $'[a\U0001F1EB\U0001F1F7]' ]
    # Emoji with a variation selector (width 0) stays with its base.
    run truncate 1 $'❤️x'
    [ "$output" = "[]" ]
}

@test "the AI terminal title is cut to 30 characters, not 30 bytes" {
    run zsh -c "
export TERM=xterm-256color ENABLE_AI_TERMINAL_TITLES=true AI_TITLE_CACHE_DIR='$BATS_TEST_TMPDIR/titles'
source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh' >/dev/null 2>&1
source '$NIVUUS_SHELL_DIR/config/20-terminal-title.zsh' >/dev/null 2>&1
_ai_credentials_ok() { return 0 }
_ai_api_call() { print -r -- '🚀 日本語のとても長いターミナルのタイトルです、本当に長いタイトル' }
_ai_get_terminal_title 'make build' 'shell'"
    [ "$status" -eq 0 ]
    valid_utf8 "$output"
    [ "$output" = "🚀 日本語のとても長いターミナルのタイトルです、本当に長いタ" ]
}

@test "the session history sent for the title is valid UTF-8 and at most 500 characters" {
    run zsh -c "
export TERM=xterm-256color ENABLE_AI_TERMINAL_TITLES=true AI_TITLE_CACHE_DIR='$BATS_TEST_TMPDIR/titles'
source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh' >/dev/null 2>&1
source '$NIVUUS_SHELL_DIR/config/20-terminal-title.zsh' >/dev/null 2>&1
_ai_credentials_ok() { return 0 }
_ai_api_call() { print -r -- \"\$1\" > '$BATS_TEST_TMPDIR/prompt'; print -r -- T }
_AI_TITLE_SESSION_HISTORY=()
for i in {1..40}; do _AI_TITLE_SESSION_HISTORY+=(\"cat ملف_\$i.txt 日本語_\$i.md\"); done
_ai_get_terminal_title 'x' 'shell' >/dev/null"
    [ "$status" -eq 0 ]
    local prompt history
    prompt="$(cat "$BATS_TEST_TMPDIR/prompt")"
    valid_utf8 "$prompt"
    history="${prompt#*in this terminal session: }"
    history="${history%%. Create a fun*}"
    [ "$(printf '%s' "$history" | wc -m)" -le 500 ]
    [ "$(printf '%s' "$history" | wc -m)" -ge 490 ]
    [[ "$history" == "cat ملف_1.txt 日本語_1.md;cat ملف_2.txt"* ]]
}

@test "a long non-ASCII PATH in the suggestion context stays valid UTF-8" {
    local dir="$BATS_TEST_TMPDIR/ディレクトリ"
    mkdir -p "$dir"
    run zsh -c "
source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh' >/dev/null 2>&1
source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh' >/dev/null 2>&1
cd '$dir'
PATH=\"\${(l:197::/:)}日本語のパス:/usr/bin:/bin\"
_ai_get_context | grep '^PATH: '"
    [ "$status" -eq 0 ]
    valid_utf8 "$output"
    [[ "$output" == "PATH: "*"日本語..." ]]
}
