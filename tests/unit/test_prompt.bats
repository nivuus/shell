#!/usr/bin/env bats

# Unit tests for prompt module (config/05-prompt.zsh)

# Helper to run zsh with correct NIVUUS_SHELL_DIR
setup() {
    # Test the tree this file belongs to, never whatever NIVUUS_SHELL_DIR the
    # environment happens to point at.
    NIVUUS_SHELL_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export NIVUUS_SHELL_DIR
}

run_zsh() {
    run zsh -c "export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR' && $1"
}

# =============================================================================
# Module Loading Tests
# =============================================================================

@test "Prompt module loads without errors" {
    run zsh -c "export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR' && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "PROMPT_SUBST is enabled" {
    run zsh -c "export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR' && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' 2>/dev/null; source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && setopt | grep -i promptsubst"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Helper Functions Tests
# =============================================================================

@test "is_ssh function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && typeset -f is_ssh"
    [ "$status" -eq 0 ]
}

@test "is_root function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && typeset -f is_root"
    [ "$status" -eq 0 ]
}

@test "is_ssh detects SSH_CLIENT" {
    run zsh -c "export SSH_CLIENT='1.2.3.4' && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && is_ssh"
    [ "$status" -eq 0 ]
}

@test "is_ssh detects SSH_TTY" {
    run zsh -c "export SSH_TTY='/dev/pts/0' && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && is_ssh"
    [ "$status" -eq 0 ]
}

@test "is_ssh returns false when not SSH" {
    run zsh -c "unset SSH_CLIENT SSH_TTY SESSION_TYPE && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && is_ssh"
    [ "$status" -ne 0 ]
}

# =============================================================================
# Git Prompt Tests
# =============================================================================

@test "git_prompt_info function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && typeset -f git_prompt_info"
    [ "$status" -eq 0 ]
}

@test "git_prompt_info returns empty when not in git repo" {
    run zsh -c "cd /tmp && export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR' && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' 2>/dev/null; source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && git_prompt_info"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Git cache variables are initialized" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '_GIT_PROMPT_CACHE' config/05-prompt.zsh | grep 'typeset -g'"
    [ "$status" -eq 0 ]
}

@test "Git cache uses configurable TTL" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'GIT_PROMPT_CACHE_TTL:-2' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Git prompt shows branch name" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'symbolic-ref' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Git prompt detects dirty state" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'git status --porcelain' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Git prompt uses THEME_GIT_PREFIX/THEME_GIT_BRANCH/THEME_SUCCESS/THEME_ERROR" {
    local repo="$BATS_TEST_TMPDIR/themed"
    git init -q -b main "$repo"
    run zsh -c "
source '$NIVUUS_SHELL_DIR/themes/nord.zsh'; source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh'
THEME_GIT_PREFIX='<P>' THEME_GIT_BRANCH='<B>' THEME_SUCCESS='<S>' THEME_ERROR='<E>'
cd '$repo'
git_prompt_info
touch dirty; _GIT_PROMPT_CACHE_TIME=0
git_prompt_info"
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == *'<P>'*'git:('*'<B>'*'main'*'<S>'* ]]
    [[ "${lines[1]}" == *'<E>'* ]]
}

# =============================================================================
# Python Virtual Environment Tests
# =============================================================================

@test "prompt_python_venv function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'prompt_python_venv()' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Python prompt detects VIRTUAL_ENV" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'VIRTUAL_ENV' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Python prompt detects CONDA" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'CONDA_DEFAULT_ENV' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Python prompt detects Poetry" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'POETRY_ACTIVE' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Python prompt uses the theme's magenta color" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 22 'prompt_python_venv()' config/05-prompt.zsh | grep 'THEME_COLORS\[magenta\]'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Cloud Context Tests
# =============================================================================

@test "prompt_cloud_context function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'prompt_cloud_context()' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Cloud prompt detects AWS_PROFILE" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'AWS_PROFILE' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Cloud prompt detects GCP project" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'CLOUDSDK_CORE_PROJECT' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Cloud prompt detects Azure subscription" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'AZURE_SUBSCRIPTION' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Firebase Prompt Tests
# =============================================================================

@test "prompt_firebase function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'prompt_firebase()' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Firebase prompt can be disabled" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'ENABLE_FIREBASE_PROMPT' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Firebase cache variables are initialized" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '_FIREBASE_PROMPT_CACHE' config/05-prompt.zsh | grep 'typeset -g'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Background Jobs Tests
# =============================================================================

@test "background_jobs_info function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'background_jobs_info()' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Background jobs uses jobstates" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'jobstates' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Background jobs shows running indicator" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '▶' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Background jobs shows suspended indicator" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '⏸' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Build Prompt Tests
# =============================================================================

@test "build_prompt function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && typeset -f build_prompt"
    [ "$status" -eq 0 ]
}

@test "build_prompt generates output" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && build_prompt"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

# =============================================================================
# PROMPT and RPROMPT Tests
# =============================================================================

@test "PROMPT is set" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'PROMPT=' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "RPROMPT is set for background jobs" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'RPROMPT=' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Theme Color Usage Tests
# =============================================================================
# The prompt no longer hardcodes ANSI codes: it reads $THEME_* variables and
# $THEME_COLORS[...] entries set by whichever themes/*.zsh is loaded.

@test "Prompt uses THEME_GIT_PREFIX/THEME_GIT_BRANCH for git decorations" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'THEME_GIT_PREFIX\|THEME_GIT_BRANCH' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 2 ]
}

@test "Prompt uses THEME_ERROR for errors/dirty status" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'THEME_ERROR' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 2 ]
}

@test "Prompt uses THEME_SUCCESS for success" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c 'THEME_SUCCESS' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 2 ]
}

@test "Prompt contains no hardcoded ANSI-256 color literals" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -cE '%F\{[0-9]+\}' config/05-prompt.zsh"
    [ "$status" -eq 1 ] || [ "${output}" -eq 0 ]
}

# =============================================================================
# Theme Pluggability Tests
# =============================================================================

@test "NIVUUS_THEME=dracula changes the loaded theme colors" {
    run zsh -c "export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR' && export NIVUUS_THEME='dracula' && source '$NIVUUS_SHELL_DIR/config/00-core.zsh' >/dev/null 2>&1 && echo \"\$THEME_BAT_NAME\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dracula"* ]]
}

@test "unknown NIVUUS_THEME falls back to nord" {
    run zsh -c "export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR' && export NIVUUS_THEME='does-not-exist' && source '$NIVUUS_SHELL_DIR/config/00-core.zsh' >/dev/null 2>&1 && echo \"\$THEME_BAT_NAME\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nord"* ]]
}

# =============================================================================
# Prompt Format Template Tests
# =============================================================================

@test "NIVUUS_PROMPT_FORMAT customizes which segments build_prompt renders" {
    run zsh -c "export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR' && export NIVUUS_PROMPT_FORMAT='{path}' && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' >/dev/null 2>&1 && build_prompt"
    [ "$status" -eq 0 ]
    [ "$output" = '$(prompt_segment_path)' ]
}

@test "default build_prompt output matches the documented default template" {
    run zsh -c "export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR' && unset NIVUUS_PROMPT_FORMAT && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' >/dev/null 2>&1 && build_prompt"
    [ "$status" -eq 0 ]
    [ "$output" = '$(prompt_segment_ssh)$(prompt_segment_root)$(prompt_segment_status) $(prompt_segment_path)$(prompt_python_venv)${_CLOUD_PROMPT_VALUE}${_FIREBASE_PROMPT_CACHE_VALUE}${_GIT_PROMPT_CACHE_VALUE} ' ]
}

# =============================================================================
# Cache Performance Tests
# =============================================================================

@test "Git cache TTL defaults to 2 seconds" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'GIT_PROMPT_CACHE_TTL:-2' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Firebase cache has TTL" {
    local proj="$BATS_TEST_TMPDIR/fb"
    mkdir -p "$proj"
    printf '{"projects":{"staging":"first-project"}}\n' > "$proj/.firebaserc"
    run env HOME="$BATS_TEST_TMPDIR" zsh -c "
source '$NIVUUS_SHELL_DIR/themes/nord.zsh'; source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh'
zmodload zsh/datetime
cd '$proj'
prompt_firebase >/dev/null
print -r -- \"A=\$_FIREBASE_PROMPT_CACHE_VALUE\"
printf '{\"projects\":{\"staging\":\"second-project\"}}\\n' > .firebaserc
prompt_firebase >/dev/null
print -r -- \"B=\$_FIREBASE_PROMPT_CACHE_VALUE\"
FIREBASE_PROMPT_CACHE_TTL=0 prompt_firebase >/dev/null
print -r -- \"C=\$_FIREBASE_PROMPT_CACHE_VALUE\""
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == *"first-project"* ]]
    [[ "${lines[1]}" == *"first-project"* ]]   # within the TTL: cached
    [[ "${lines[2]}" == *"second-project"* ]]  # TTL elapsed: re-read
}

@test "Azure cache has TTL, even when az fails" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\necho run >> "%s"\n[ -n "$AZ_FAIL" ] && exit 1\necho My Subscription\n' \
        "$BATS_TEST_TMPDIR/az.log" > "$BATS_TEST_TMPDIR/bin/az"
    chmod +x "$BATS_TEST_TMPDIR/bin/az"
    run zsh -c "
PATH='$BATS_TEST_TMPDIR/bin':\$PATH
source '$NIVUUS_SHELL_DIR/themes/nord.zsh'; source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh'
export AZURE_SUBSCRIPTION_ID=sub-id
_nivuus_cloud_prompt_refresh; print -r -- \"A=\$_CLOUD_PROMPT_VALUE\"
_nivuus_cloud_prompt_refresh; print -r -- \"B=\$_CLOUD_PROMPT_VALUE\"
AZ_FAIL=1 AZURE_PROMPT_CACHE_TTL=0 _nivuus_cloud_prompt_refresh
AZ_FAIL=1 _nivuus_cloud_prompt_refresh; print -r -- \"C=\$_CLOUD_PROMPT_VALUE\""
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == *"az:My Subscription"* ]]
    [[ "${lines[1]}" == *"az:My Subscription"* ]]
    [[ "${lines[2]}" == *"az:sub-id"* ]]
    # First refresh, then the forced one; the second and the last were cached.
    [ "$(wc -l < "$BATS_TEST_TMPDIR/az.log")" -eq 2 ]
}

# =============================================================================
# The caches hold across real prompts
# =============================================================================
# Each prompt used to evaluate $(git_prompt_info), $(prompt_firebase) and
# $(prompt_cloud_context) in a subshell: the cache they wrote died with it,
# so git, jq and az ran at every prompt whatever the TTL. Count the git runs
# of an interactive shell, behind a real terminal, over several prompts.

_count_git_over_prompts() {
    local repo="$BATS_TEST_TMPDIR/repo" bin="$BATS_TEST_TMPDIR/bin"
    git init -q -b main "$repo"
    mkdir -p "$bin"
    printf '#!/bin/sh\necho "$1" >> "%s"\nexec %s "$@"\n' "$BATS_TEST_TMPDIR/git.log" "$(command -v git)" > "$bin/git"
    chmod +x "$bin/git"
    printf '%s\n' \
        "export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR' GIT_PROMPT_CACHE_TTL=600" \
        "source '$NIVUUS_SHELL_DIR/themes/nord.zsh'; source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh'" \
        "PROMPT+='%(?:<OK>:<KO>)'" \
        "PATH='$bin':\$PATH; cd '$repo'; : > '$BATS_TEST_TMPDIR/git.log'" \
        "true" "true" "false" "true" "exit" > "$BATS_TEST_TMPDIR/input"
    script -qec "zsh --no-rcs -i" /dev/null < "$BATS_TEST_TMPDIR/input" | tr -d '\r' > "$BATS_TEST_TMPDIR/screen"
}

@test "the git segment runs git once per TTL, not at every prompt" {
    _count_git_over_prompts
    # Five prompts after the log was reset; one refresh in the TTL.
    [ "$(grep -c '^rev-parse' "$BATS_TEST_TMPDIR/git.log")" -eq 1 ]
    grep -q 'git:(' "$BATS_TEST_TMPDIR/screen"
}

@test "refreshing the caches before a prompt keeps the last exit status" {
    _count_git_over_prompts
    # After `false` the status segment must still see the failure.
    grep -q '<KO>' "$BATS_TEST_TMPDIR/screen"
    grep -q '<OK>' "$BATS_TEST_TMPDIR/screen"
}

@test "a cached segment follows a change of directory at once" {
    local repo="$BATS_TEST_TMPDIR/repo2"
    git init -q -b topic "$repo"
    run zsh -c "
source '$NIVUUS_SHELL_DIR/themes/nord.zsh'; source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh'
GIT_PROMPT_CACHE_TTL=600
cd '$repo'; _nivuus_prompt_precmd; print -rP -- \"A=\$PROMPT\"
cd /; _nivuus_prompt_precmd; print -rP -- \"B=\$PROMPT\""
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == *"git:("*"topic"* ]]
    [[ "${lines[1]}" != *"git:("* ]]
}

# =============================================================================
# Spacing: the template, not the segment, separates {status} from {path}
# =============================================================================

@test "prompt_segment_status carries no trailing space" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' >/dev/null 2>&1 && prompt_segment_status"
    [ "$status" -eq 0 ]
    [[ "$output" != *" " ]]
}

@test "the rendered prompt has exactly one space between > and the path" {
    run zsh -c "cd /tmp && export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR' && unset NIVUUS_PROMPT_FORMAT && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' >/dev/null 2>&1 && print -P -- \"\$(prompt_segment_root)\$(prompt_segment_status) \$(prompt_segment_path)\" | sed 's/\x1b\[[0-9;]*m//g'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"> /tmp"* ]]
    [[ "$output" != *">  /tmp"* ]]
}

# =============================================================================
# Untrusted values in prompt segments
# =============================================================================
# Segment output is rendered as prompt escapes, so a value the user does not
# control (a branch name chosen by whoever published the repository, a venv
# directory, a profile name) must reach the screen literally: its `%` must not
# become a prompt escape, and nothing in it may be evaluated.

_render_prompt_in() {
    run zsh -c "
export NIVUUS_SHELL_DIR='$NIVUUS_SHELL_DIR'
source '$NIVUUS_SHELL_DIR/themes/nord.zsh'
source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh'
cd ${1@Q}
$2
_nivuus_prompt_precmd
print -rP -- \"\$PROMPT\"
"
}

@test "a git branch name is rendered literally in the prompt" {
    local repo="$BATS_TEST_TMPDIR/repo"
    git init -q -b 'fix%F{red}x$(touch${IFS}BRANCH_MARKER)' "$repo"
    _render_prompt_in "$repo" ""
    [ "$status" -eq 0 ]
    [ ! -e "$repo/BRANCH_MARKER" ]
    [[ "$output" == *'fix%F{red}x$(touch${IFS}BRANCH_MARKER)'* ]]
}

@test "venv and cloud profile names are rendered literally in the prompt" {
    _render_prompt_in "$BATS_TEST_TMPDIR" "
export VIRTUAL_ENV='/opt/env%Bvenv' AWS_PROFILE='prof%F{red}ile'
"
    [ "$status" -eq 0 ]
    [[ "$output" == *'(env%Bvenv)'* ]]
    [[ "$output" == *'aws:prof%F{red}ile'* ]]
}
