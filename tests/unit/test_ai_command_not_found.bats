#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load "${BATS_TEST_DIRNAME}/../helpers/pty"

# Unit tests for the AI command-not-found package suggestion system
# (config/24-ai-command-not-found.zsh)

setup() {
    export AI_COMMAND_NOT_FOUND_CACHE_DIR="$BATS_TEST_TMPDIR/ai-cnf-cache"
    mkdir -p "$AI_COMMAND_NOT_FOUND_CACHE_DIR"
    unset ENABLE_AI_COMMAND_NOT_FOUND
    unset AI_CNF_AUTO_PROMPT
    unset AI_CNF_RE_EXECUTE
}

teardown() {
    rm -rf "$AI_COMMAND_NOT_FOUND_CACHE_DIR"
}

# --- Module Loading & Definitions ---

@test "24-ai-command-not-found.zsh loads without errors" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; source '$NIVUUS_SHELL_DIR/config/24-ai-command-not-found.zsh' && echo loaded"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "command_not_found_handler is defined after loading" {
    pty_run "source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; source '$NIVUUS_SHELL_DIR/config/24-ai-command-not-found.zsh'; typeset -f command_not_found_handler"
    [ "$status" -eq 0 ]
}

@test "User commands (ai-cnf-lookup, ai-cnf-clear-cache, ai-cnf-stats, ai-cnf-help) are defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; source '$NIVUUS_SHELL_DIR/config/24-ai-command-not-found.zsh'; typeset -f ai-cnf-lookup ai-cnf-clear-cache ai-cnf-stats ai-cnf-help"
    [ "$status" -eq 0 ]
}

@test "Module respects ENABLE_AI_COMMAND_NOT_FOUND=false at load time" {
    run zsh -c "export ENABLE_AI_COMMAND_NOT_FOUND=false; source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; source '$NIVUUS_SHELL_DIR/config/24-ai-command-not-found.zsh'; typeset -f command_not_found_handler"
    [ "$status" -eq 1 ]
}

# --- System Context & Cache ---

@test "_ai_cnf_get_sys_context detects OS and architecture" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'; source '$NIVUUS_SHELL_DIR/config/24-ai-command-not-found.zsh'; _ai_cnf_get_sys_context"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OS:"* ]]
    [[ "$output" == *"Available package managers:"* ]]
}

@test "_ai_cnf_cache_set and _ai_cnf_cache_get work with TTL" {
    run zsh -c "
export AI_COMMAND_NOT_FOUND_CACHE_DIR='$AI_COMMAND_NOT_FOUND_CACHE_DIR'
source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'
source '$NIVUUS_SHELL_DIR/config/24-ai-command-not-found.zsh'
key=\$(_ai_cnf_cache_key 'spd-say' 'ctx')
_ai_cnf_cache_set \"\$key\" '{\"found\":true,\"package\":\"speech-dispatcher\"}'
_ai_cnf_cache_get \"\$key\"
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"speech-dispatcher"* ]]
}

@test "ai-cnf-clear-cache clears the cache directory" {
    run zsh -c "
export AI_COMMAND_NOT_FOUND_CACHE_DIR='$AI_COMMAND_NOT_FOUND_CACHE_DIR'
source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'
source '$NIVUUS_SHELL_DIR/config/24-ai-command-not-found.zsh'
_ai_cnf_cache_set 'k1' 'val1'
_ai_cnf_cache_set 'k2' 'val2'
ai-cnf-clear-cache
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cleared 2 cached"* ]]
}

# --- AI Lookup & Parsing ---

@test "_ai_cnf_ai_lookup parses mock AI JSON response correctly" {
    run zsh -c "
source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'
source '$NIVUUS_SHELL_DIR/config/24-ai-command-not-found.zsh'

_ai_credentials_ok() { return 0; }
_ai_api_call() {
    print -r -- '{\"found\":true,\"description\":\"Configurable talking cow\",\"package\":\"cowsay\",\"manager\":\"apt-get\"}'
}
_ai_cnf_supported_managers() { print -r -- apt-get }

_ai_cnf_ai_lookup 'cowsay' 'cowsay coucou' 'OS: Linux'
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"package\":\"cowsay\""* ]]
    [[ "$output" == *"\"manager\":\"apt-get\""* ]]
}

@test "_ai_cnf_ai_lookup handles unrecognized command with found=false" {
    run zsh -c "
source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'
source '$NIVUUS_SHELL_DIR/config/24-ai-command-not-found.zsh'

_ai_credentials_ok() { return 0; }
_ai_api_call() {
    print -r -- '{\"found\":false}'
}

res=\$(_ai_cnf_ai_lookup 'gibberish_xyz' 'gibberish_xyz' 'OS: Linux')
echo \"\$res\"
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\"found\":false"* || "$output" == *"\"found\": false"* ]]
}

@test "_ai_cnf_ai_lookup handles markdown code blocks around JSON from AI" {
    run zsh -c "
source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'
source '$NIVUUS_SHELL_DIR/config/24-ai-command-not-found.zsh'

_ai_credentials_ok() { return 0; }
_ai_api_call() {
    print -r -- '\`\`\`json
{
  \"found\": true,
  \"command\": \"spd-say\",
  \"description\": \"Speech Dispatcher output\",
  \"package\": \"speech-dispatcher\",
  \"install_command\": \"sudo apt install speech-dispatcher\",
  \"alternative_install\": \"\"
}
\`\`\`'
}

_ai_cnf_ai_lookup 'spd-say' 'spd-say hello' 'OS: Linux'
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"speech-dispatcher"* ]]
}

# --- Handler Execution & UX ---

@test "command_not_found_handler returns 127 and prints not found error to stderr" {
    pty_run "
export AI_COMMAND_NOT_FOUND_CACHE_DIR='$AI_COMMAND_NOT_FOUND_CACHE_DIR'
export AI_CNF_AUTO_PROMPT=false
source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'
source '$NIVUUS_SHELL_DIR/config/24-ai-command-not-found.zsh'

_ai_credentials_ok() { return 1; }

command_not_found_handler 'unknown_cmd_123' 'arg1'
"
    [ "$status" -eq 127 ]
    [[ "$output" == *"zsh: command not found: unknown_cmd_123"* ]]
}

@test "command_not_found_handler displays UI box when package is found" {
    pty_run "
export AI_COMMAND_NOT_FOUND_CACHE_DIR='$AI_COMMAND_NOT_FOUND_CACHE_DIR'
export AI_CNF_AUTO_PROMPT=false
source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'
source '$NIVUUS_SHELL_DIR/config/24-ai-command-not-found.zsh'

_ai_credentials_ok() { return 0; }
_ai_api_call() {
    print -r -- '{\"found\":true,\"description\":\"Configurable cow\",\"package\":\"cowsay\",\"manager\":\"apt-get\"}'
}
_ai_cnf_native_lookup() { return 1 }
_ai_cnf_install_argv() { reply=(apt-get install -y --no-install-recommends \"\$2\") }

command_not_found_handler 'cowsay' 'coucou'
"
    [ "$status" -eq 127 ]
    [[ "$output" == *"zsh: command not found: cowsay"* ]]
    [[ "$output" == *"Nivuus AI Package Assistant"* ]]
    [[ "$output" == *"Package:"* ]]
    [[ "$output" == *"cowsay"* ]]
    [[ "$output" == *"apt-get install -y --no-install-recommends cowsay"* ]]
}

@test "command_not_found_handler protects against infinite recursion" {
    pty_run "
export AI_COMMAND_NOT_FOUND_CACHE_DIR='$AI_COMMAND_NOT_FOUND_CACHE_DIR'
source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'
source '$NIVUUS_SHELL_DIR/config/24-ai-command-not-found.zsh'

_AI_CNF_ACTIVE=1 command_not_found_handler 'recurse_cmd'
"
    [ "$status" -eq 127 ]
    [[ "$output" == *"zsh: command not found: recurse_cmd"* ]]
}

@test "ai-cnf-stats displays statistics" {
    run zsh -c "
export AI_COMMAND_NOT_FOUND_CACHE_DIR='$AI_COMMAND_NOT_FOUND_CACHE_DIR'
source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'
source '$NIVUUS_SHELL_DIR/config/24-ai-command-not-found.zsh'
ai-cnf-stats
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AI Command Not Found Statistics"* ]]
    [[ "$output" == *"Cached suggestions:"* ]]
    [[ "$output" == *"System context:"* ]]
}

# --- The model names a package, never a command ---
# The reply is model output: nothing guarantees that a free-form install
# command shown is the one executed, so only a package manager name and a
# package name are accepted, and the command is built from lib/deps.sh.
# A fake apt-get records what would be executed; NIVUUS_UID=0 keeps sudo out.

_cnf_preamble() {
    local reply="$1"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/CALLS-apt-get"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/apt-get"
    chmod +x "$BATS_TEST_TMPDIR/bin/apt-get"
    echo "
cd ${BATS_TEST_TMPDIR@Q}
export PATH=${BATS_TEST_TMPDIR@Q}/bin:\$PATH NIVUUS_UID=0 AI_CNF_RE_EXECUTE=false
export AI_COMMAND_NOT_FOUND_CACHE_DIR='$AI_COMMAND_NOT_FOUND_CACHE_DIR'
source '$NIVUUS_SHELL_DIR/config/00-core.zsh'; source '$NIVUUS_SHELL_DIR/config/09-ai-core.zsh'
source '$NIVUUS_SHELL_DIR/config/24-ai-command-not-found.zsh'
_ai_cnf_native_lookup() { return 1 }
_ai_credentials_ok() { return 0 }
_ai_api_call() { print -r -- ${reply@Q} }
command_not_found_handler zzqtool arg
"
}

@test "a reply carrying a free-form install command offers nothing and runs nothing" {
    pty_run "$(_cnf_preamble '{"found":true,"description":"d","package":"zzqtool","install_command":"apt-get install zzqtool; touch CNF_MARKER"}')" <<< 'y'
    [ "$status" -eq 127 ]
    [[ "$output" != *"Install package now"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/CNF_MARKER" ]
    [ ! -e "$BATS_TEST_TMPDIR/CALLS-apt-get" ]
}

@test "a package name holding a command separator offers nothing and runs nothing" {
    pty_run "$(_cnf_preamble '{"found":true,"description":"d","package":"zzqtool;touch CNF_MARKER","manager":"apt-get"}')" <<< 'y'
    [ "$status" -eq 127 ]
    [[ "$output" != *"Install package now"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/CNF_MARKER" ]
    [ ! -e "$BATS_TEST_TMPDIR/CALLS-apt-get" ]
}

@test "escape sequences in the model's description are shown, not interpreted" {
    AI_CNF_AUTO_PROMPT=false pty_run "export AI_CNF_AUTO_PROMPT=false
$(_cnf_preamble '{"found":true,"description":"cow \u001b[2J\u001b]0;evil\u0007 end","package":"zzqtool","manager":"apt-get","install_command":"apt-get install zzqtool"}')"
    [[ "$output" == *"Nivuus AI Package Assistant"* ]]
    [[ "$output" == *'cow ^[[2J^[]0;evil^G end'* ]]
    [[ "$output" != *$'\e[2J'* ]]
}

@test "a valid reply offers and runs the command built by lib/deps.sh" {
    pty_run "$(_cnf_preamble '{"found":true,"description":"d","package":"zzqtool","manager":"apt-get"}')" <<< 'y'
    [[ "$output" == *"Install package now with 'apt-get install -y --no-install-recommends zzqtool'"* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/CALLS-apt-get")" = "install -y --no-install-recommends zzqtool" ]
}
