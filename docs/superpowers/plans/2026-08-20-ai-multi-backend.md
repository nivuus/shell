# AI Multi-Backend Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generalize the shell's AI helper from a Gemini-only integration into a provider-agnostic backend layer (Gemini/OpenAI/Anthropic via API key), plus an optional Gemini `cli` auth mode that shells out to Antigravity CLI (`agy`) to spend a Google AI Pro/Ultra subscription's quota instead of a metered key.

**Architecture:** `config/09-ai-core.zsh` becomes a thin dispatcher (`_ai_api_call`, `_ai_get_api_key`, `_ai_resolve_model`, `_ai_json_escape`) that routes to one `config/09-ai-backend-<name>.zsh` file per provider, each implementing `_ai_backend_<name>_call PROMPT [MODEL] [MAX_TOKENS] [TEMPERATURE] [TIMEOUT_SECS]`. Existing consumers (`10-ai.zsh`, `19-ai-suggestions.zsh`, `20-terminal-title.zsh`, `22-ai-errors.zsh`) keep calling `_ai_api_call`/`_ai_get_api_key` unchanged in shape, but stop hardcoding a Gemini model name so they work correctly under any `AI_BACKEND`.

**Tech Stack:** zsh, curl, jq (required for the new backends; Gemini keeps its grep fallback), bats for tests.

**Spec:** `docs/superpowers/specs/2026-08-20-ai-multi-backend-design.md`

## Global Constraints

- `AI_BACKEND` env var: `gemini` (default) | `openai` | `anthropic`. Unknown value → `_ai_api_call` returns 1 and prints a clear error naming the valid choices.
- Default models: Gemini `gemini-3.5-flash-lite` (override `GEMINI_MODEL`), OpenAI `gpt-5.6-luna` (override `OPENAI_MODEL`), Anthropic `claude-haiku-4-5` (override `ANTHROPIC_MODEL`).
- API key env vars: `GOOGLE_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` — one per backend, resolved by `_ai_get_api_key` based on the active `$AI_BACKEND`.
- OpenAI and Anthropic backends require `jq`; no grep fallback (unlike Gemini) — fail with a clear message if `jq` is missing.
- Gemini `GEMINI_AUTH_MODE`: `api-key` (default) | `cli`. In `cli` mode, shell out to `agy` (Antigravity CLI) — never `gemini`/`gemini-cli`, which was discontinued for subscription/free-tier accounts on 2026-06-18.
- No OAuth code lives in this repo. No real network calls in tests — everything mocked via zsh function overrides (`curl`, `agy`) sourced before the code under test, matching the existing `mock_gemini`-style convention in `tests/helpers/mocks.zsh`.
- Every new/changed shell function must keep the "prints response text to stdout on success, returns 1 on any failure" contract.

---

### Task 1: Core dispatcher + Gemini backend extraction

**Files:**
- Modify: `config/09-ai-core.zsh` (full rewrite, currently 77 lines)
- Create: `config/09-ai-backend-gemini.zsh`
- Modify: `config/10-ai.zsh:50,94,96,103,109,121,133,145`
- Modify: `config/19-ai-suggestions.zsh:23`
- Modify: `config/20-terminal-title.zsh:32`
- Modify: `config/22-ai-errors.zsh:22`
- Modify: `.zshrc:80` (config_files array)
- Modify: `doc/CLAUDE.md:146-151,276`
- Test: `tests/unit/test_ai_backends.bats` (new)

**Interfaces:**
- Produces (from `09-ai-core.zsh`): `_ai_resolve_model()` (no args, prints active backend's default/overridden model), `_ai_json_escape STRING` (prints escaped string), `_ai_get_api_key()` (prints key, returns 1 if unset), `_ai_api_call PROMPT [MODEL] [MAX_TOKENS] [TEMPERATURE] [TIMEOUT_SECS]` (dispatches to `_ai_backend_${AI_BACKEND}_call`).
- Produces (from `09-ai-backend-gemini.zsh`): `_ai_gemini_get_api_key()`, `_ai_backend_gemini_call PROMPT [MODEL] [MAX_TOKENS] [TEMPERATURE] [TIMEOUT_SECS]`.
- Consumes: nothing from later tasks — this is the foundation task 2-5 build on.

- [ ] **Step 1: Write the failing dispatcher/model-resolution tests**

Create `tests/unit/test_ai_backends.bats`:

```bats
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
    run zsh -c '
curl() { printf "%s" "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"mocked gemini response\"}]}}]}"; }
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `NIVUUS_SHELL_DIR="$(pwd)" bats tests/unit/test_ai_backends.bats`
Expected: FAIL — `config/09-ai-backend-gemini.zsh` does not exist yet, `_ai_resolve_model` is undefined.

- [ ] **Step 3: Rewrite `config/09-ai-core.zsh` as the dispatcher**

Replace the full file content with:

```zsh
#!/usr/bin/env zsh
# =============================================================================
# AI Core - Backend Dispatcher
# =============================================================================
# Routes AI calls to the active backend (gemini/openai/anthropic).
# Shared by config/10-ai.zsh, config/19-ai-suggestions.zsh,
# config/20-terminal-title.zsh and config/22-ai-errors.zsh.
# =============================================================================

typeset -g AI_BACKEND="${AI_BACKEND:-gemini}"

# Return the default model for the active backend, honoring per-backend
# overrides (GEMINI_MODEL / OPENAI_MODEL / ANTHROPIC_MODEL).
_ai_resolve_model() {
    case "$AI_BACKEND" in
        openai) print -r -- "${OPENAI_MODEL:-gpt-5.6-luna}" ;;
        anthropic) print -r -- "${ANTHROPIC_MODEL:-claude-haiku-4-5}" ;;
        *) print -r -- "${GEMINI_MODEL:-gemini-3.5-flash-lite}" ;;
    esac
}

# Escape a string for embedding in a JSON string value.
_ai_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/}"
    s="${s//$'\t'/\\t}"
    print -r -- "$s"
}

# Resolve the API key/credential for the active backend.
_ai_get_api_key() {
    case "$AI_BACKEND" in
        openai)
            [[ -n "$OPENAI_API_KEY" ]] || return 1
            print -r -- "$OPENAI_API_KEY"
            ;;
        anthropic)
            [[ -n "$ANTHROPIC_API_KEY" ]] || return 1
            print -r -- "$ANTHROPIC_API_KEY"
            ;;
        *)
            _ai_gemini_get_api_key
            ;;
    esac
}

# Call the active backend and print the response text.
# Usage: _ai_api_call PROMPT [MODEL] [MAX_TOKENS] [TEMPERATURE] [TIMEOUT_SECS]
_ai_api_call() {
    local prompt="$1"
    local model="${2:-$(_ai_resolve_model)}"
    local max_tokens="${3:-1024}"
    local temperature="${4:-0.3}"
    local timeout_secs="${5:-15}"

    case "$AI_BACKEND" in
        openai)
            _ai_backend_openai_call "$prompt" "$model" "$max_tokens" "$temperature" "$timeout_secs"
            ;;
        anthropic)
            _ai_backend_anthropic_call "$prompt" "$model" "$max_tokens" "$temperature" "$timeout_secs"
            ;;
        gemini)
            _ai_backend_gemini_call "$prompt" "$model" "$max_tokens" "$temperature" "$timeout_secs"
            ;;
        *)
            print -u2 -- "AI_BACKEND: unknown backend '$AI_BACKEND' (expected gemini, openai, or anthropic)"
            return 1
            ;;
    esac
}
```

- [ ] **Step 4: Create `config/09-ai-backend-gemini.zsh`**

```zsh
#!/usr/bin/env zsh
# =============================================================================
# AI Backend - Gemini
# =============================================================================
# Talks to the Gemini REST API directly. When GEMINI_AUTH_MODE=cli, shells
# out to Antigravity CLI (agy) instead, to spend a Google AI Pro/Ultra
# subscription's quota rather than a metered API key.
# =============================================================================

typeset -g GEMINI_AUTH_MODE="${GEMINI_AUTH_MODE:-api-key}"

# Resolve the Google API key: explicit env var first, then fall back to the
# apiKey stored by a previously installed gemini-cli, for a smooth migration.
_ai_gemini_get_api_key() {
    if [[ -n "$GOOGLE_API_KEY" ]]; then
        print -r -- "$GOOGLE_API_KEY"
        return 0
    fi

    local config_file="$HOME/.gemini-cli/config.json"
    if [[ -f "$config_file" ]]; then
        local key=$(grep -o '"apiKey"[[:space:]]*:[[:space:]]*"[^"]*"' "$config_file" | cut -d'"' -f4)
        if [[ -n "$key" ]]; then
            print -r -- "$key"
            return 0
        fi
    fi

    return 1
}

_ai_backend_gemini_call() {
    local prompt="$1"
    local model="${2:-${GEMINI_MODEL:-gemini-3.5-flash-lite}}"
    local max_tokens="${3:-1024}"
    local temperature="${4:-0.3}"
    local timeout_secs="${5:-15}"

    if [[ "$GEMINI_AUTH_MODE" == "cli" ]]; then
        _ai_gemini_cli_call "$prompt" "$model" "$timeout_secs"
        return $?
    fi

    local api_key
    api_key=$(_ai_gemini_get_api_key) || return 1

    local api_url="https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${api_key}"
    local escaped_prompt=$(_ai_json_escape "$prompt")
    local json_payload="{\"contents\":[{\"parts\":[{\"text\":\"$escaped_prompt\"}]}],\"generationConfig\":{\"temperature\":${temperature},\"maxOutputTokens\":${max_tokens}}}"

    local api_response=$(timeout "$timeout_secs" curl -s -X POST "$api_url" \
        -H 'Content-Type: application/json' \
        -d "$json_payload" 2>/dev/null)

    [[ -z "$api_response" ]] && return 1

    # jq handles embedded quotes/escapes correctly; grep-based extraction
    # breaks as soon as the text itself contains a `"`.
    local result=""
    if command -v jq &>/dev/null; then
        result=$(print -r -- "$api_response" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)
    else
        result=$(print -r -- "$api_response" | grep -o '"text"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4 | sed 's/\\n/\n/g; s/\\"/"/g')
    fi

    [[ -z "$result" ]] && return 1

    print -r -- "$result"
}
```

(`_ai_gemini_cli_call` is added in Task 4 — leave it unimplemented for now; `GEMINI_AUTH_MODE` stays `api-key` by default so nothing calls it yet.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `NIVUUS_SHELL_DIR="$(pwd)" bats tests/unit/test_ai_backends.bats`
Expected: 8/8 PASS

- [ ] **Step 6: Fix consumer model-fallback and add the new files to the load order**

`config/10-ai.zsh`: replace every `"${GEMINI_MODEL:-$AI_DEFAULT_MODEL}"` second argument with nothing (drop the argument so `_ai_api_call` fills in the backend-correct default). Concretely:

- Line 50 (inside the `aihelp` heredoc): `Model: ${GEMINI_MODEL:-$AI_DEFAULT_MODEL}` → `Model: $(_ai_resolve_model)`
- Line 94: `_ai_api_call "Suggest useful zsh commands and shell tricks" "${GEMINI_MODEL:-$AI_DEFAULT_MODEL}"` → `_ai_api_call "Suggest useful zsh commands and shell tricks"`
- Line 96: `_ai_api_call "Suggest zsh commands for: $query" "${GEMINI_MODEL:-$AI_DEFAULT_MODEL}"` → `_ai_api_call "Suggest zsh commands for: $query"`
- Line 103: `_ai_api_call "Git command help: $query. Provide the exact command to run." "${GEMINI_MODEL:-$AI_DEFAULT_MODEL}"` → `_ai_api_call "Git command help: $query. Provide the exact command to run."`
- Line 109: `_ai_api_call "GitHub CLI (gh) help: $query. Provide the exact command to run." "${GEMINI_MODEL:-$AI_DEFAULT_MODEL}"` → `_ai_api_call "GitHub CLI (gh) help: $query. Provide the exact command to run."`
- Line 121: `_ai_api_call "Explain this command concisely: $cmd" "${GEMINI_MODEL:-$AI_DEFAULT_MODEL}"` → `_ai_api_call "Explain this command concisely: $cmd"`
- Line 133: `_ai_api_call "Provide a detailed explanation of this command, including each option: $cmd" "${GEMINI_MODEL:-$AI_DEFAULT_MODEL}"` → `_ai_api_call "Provide a detailed explanation of this command, including each option: $cmd"`
- Line 145: `_ai_api_call "$question" "${GEMINI_MODEL:-$AI_DEFAULT_MODEL}"` → `_ai_api_call "$question"`

`config/19-ai-suggestions.zsh:23`:
```zsh
typeset -g AI_SUGGESTION_MODEL="${AI_SUGGESTION_MODEL:-gemini-3.1-flash-lite}"  # Model for suggestions
```
becomes:
```zsh
typeset -g AI_SUGGESTION_MODEL="${AI_SUGGESTION_MODEL:-$(_ai_resolve_model)}"  # Model for suggestions
```

`config/20-terminal-title.zsh:32`:
```zsh
    export AI_TITLE_MODEL="${AI_TITLE_MODEL:-gemini-3.1-flash-lite}"
```
becomes:
```zsh
    export AI_TITLE_MODEL="${AI_TITLE_MODEL:-$(_ai_resolve_model)}"
```

`config/22-ai-errors.zsh:22`:
```zsh
: ${AI_ERROR_MODEL:="${GEMINI_MODEL:-gemini-3.1-flash-lite}"}
```
becomes:
```zsh
: ${AI_ERROR_MODEL:="$(_ai_resolve_model)"}
```

`.zshrc` — insert the two new backend files right after `09-ai-core.zsh` in the `config_files` array (around line 80):

```zsh
    09-ai-core.zsh
    09-ai-backend-gemini.zsh
    09-ai-backend-openai.zsh
    09-ai-backend-anthropic.zsh
    09-nodejs.zsh
```

(`09-ai-backend-openai.zsh` and `09-ai-backend-anthropic.zsh` are created in Tasks 2-3; adding them to the array now is harmless — the loader already guards with `[[ -f "$config_path" ]]`.)

`doc/CLAUDE.md:146-151` — replace:

```
`config/10-ai.zsh` calls the Gemini REST API directly via the shared helper in `config/09-ai-core.zsh` (`_ai_api_call`, `_ai_get_api_key`) - no `gemini-cli` binary dependency:

- **No fallback**: If `GOOGLE_API_KEY` is not set (and no `~/.gemini-cli/config.json` apiKey is found), shows setup instructions
- **Model config**: `GEMINI_MODEL` unset by default (falls back to `gemini-3.1-flash-lite` in `config/09-ai-core.zsh`)
- Functions (`??`, `?git`, `?gh`, `why`, `explain`, `ask`) call `_ai_api_call` from `config/09-ai-core.zsh`
- `config/19-ai-suggestions.zsh`, `config/20-terminal-title.zsh` and `config/22-ai-errors.zsh` share the same helper
```

with:

```
`config/09-ai-core.zsh` is a multi-backend dispatcher (`_ai_api_call`, `_ai_get_api_key`, `_ai_resolve_model`) routing to `config/09-ai-backend-{gemini,openai,anthropic}.zsh` based on `AI_BACKEND` (default `gemini`). `config/10-ai.zsh` and friends call the dispatcher, never a backend file directly:

- **Backend selection**: `AI_BACKEND=gemini|openai|anthropic`; per-backend model override `GEMINI_MODEL`/`OPENAI_MODEL`/`ANTHROPIC_MODEL`; per-backend key `GOOGLE_API_KEY`/`OPENAI_API_KEY`/`ANTHROPIC_API_KEY`
- **No fallback**: If the active backend's key is not set (Gemini also checks `~/.gemini-cli/config.json`), shows setup instructions
- **Gemini `cli` auth mode**: `GEMINI_AUTH_MODE=cli` shells out to Antigravity CLI (`agy`) instead of the REST API, to use a Google AI Pro/Ultra subscription's quota
- Functions (`??`, `?git`, `?gh`, `why`, `explain`, `ask`) call `_ai_api_call` from `config/09-ai-core.zsh`
- `config/19-ai-suggestions.zsh`, `config/20-terminal-title.zsh` and `config/22-ai-errors.zsh` share the same dispatcher
```

`doc/CLAUDE.md:276` — replace:

```
- **`config/09-ai-core.zsh`**: Shared Gemini REST API helper (`_ai_api_call`, `_ai_get_api_key`)
```

with:

```
- **`config/09-ai-core.zsh`**: Multi-backend AI dispatcher (`_ai_api_call`, `_ai_get_api_key`, `_ai_resolve_model`)
- **`config/09-ai-backend-gemini.zsh`** / **`09-ai-backend-openai.zsh`** / **`09-ai-backend-anthropic.zsh`**: Per-provider REST (and, for Gemini, Antigravity CLI) implementations
```

- [ ] **Step 7: Run the full unit suite to check nothing else broke**

Run: `NIVUUS_SHELL_DIR="$(pwd)" bats tests/unit/`
Expected: all PASS (including the pre-existing `test_ai_suggestions.bats`, which only greps for structural markers and isn't affected by these edits)

- [ ] **Step 8: Commit**

```bash
git add config/09-ai-core.zsh config/09-ai-backend-gemini.zsh config/10-ai.zsh \
    config/19-ai-suggestions.zsh config/20-terminal-title.zsh config/22-ai-errors.zsh \
    .zshrc doc/CLAUDE.md tests/unit/test_ai_backends.bats
git commit -m "refactor(ai): split AI core into a multi-backend dispatcher + Gemini backend"
```

---

### Task 2: OpenAI backend

**Files:**
- Create: `config/09-ai-backend-openai.zsh`
- Test: `tests/unit/test_ai_backends.bats` (append)

**Interfaces:**
- Consumes: `_ai_json_escape` (Task 1, `09-ai-core.zsh`).
- Produces: `_ai_backend_openai_call PROMPT [MODEL] [MAX_TOKENS] [TEMPERATURE] [TIMEOUT_SECS]`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_ai_backends.bats`:

```bats
# --- OpenAI backend ---

@test "openai backend parses choices content via curl+jq" {
    run zsh -c '
curl() { printf "%s" "{\"choices\":[{\"message\":{\"content\":\"mocked openai response\"}}]}"; }
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `NIVUUS_SHELL_DIR="$(pwd)" bats tests/unit/test_ai_backends.bats`
Expected: the 3 new tests FAIL — `config/09-ai-backend-openai.zsh` does not exist yet.

- [ ] **Step 3: Create `config/09-ai-backend-openai.zsh`**

```zsh
#!/usr/bin/env zsh
# =============================================================================
# AI Backend - OpenAI
# =============================================================================
# Talks to the OpenAI Chat Completions REST API.
# =============================================================================

_ai_backend_openai_call() {
    local prompt="$1"
    local model="${2:-${OPENAI_MODEL:-gpt-5.6-luna}}"
    local max_tokens="${3:-1024}"
    local temperature="${4:-0.3}"
    local timeout_secs="${5:-15}"

    if ! command -v jq &>/dev/null; then
        print -u2 -- "The openai backend requires jq to parse API responses."
        return 1
    fi

    local api_key="$OPENAI_API_KEY"
    [[ -z "$api_key" ]] && return 1

    local escaped_prompt=$(_ai_json_escape "$prompt")
    local json_payload="{\"model\":\"${model}\",\"messages\":[{\"role\":\"user\",\"content\":\"$escaped_prompt\"}],\"max_tokens\":${max_tokens},\"temperature\":${temperature}}"

    local api_response=$(timeout "$timeout_secs" curl -s -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Authorization: Bearer ${api_key}" \
        -H 'Content-Type: application/json' \
        -d "$json_payload" 2>/dev/null)

    [[ -z "$api_response" ]] && return 1

    local result=$(print -r -- "$api_response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)

    [[ -z "$result" ]] && return 1

    print -r -- "$result"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `NIVUUS_SHELL_DIR="$(pwd)" bats tests/unit/test_ai_backends.bats`
Expected: all PASS (11/11 so far)

- [ ] **Step 5: Commit**

```bash
git add config/09-ai-backend-openai.zsh tests/unit/test_ai_backends.bats
git commit -m "feat(ai): add OpenAI backend"
```

---

### Task 3: Anthropic backend

**Files:**
- Create: `config/09-ai-backend-anthropic.zsh`
- Test: `tests/unit/test_ai_backends.bats` (append)

**Interfaces:**
- Consumes: `_ai_json_escape` (Task 1, `09-ai-core.zsh`).
- Produces: `_ai_backend_anthropic_call PROMPT [MODEL] [MAX_TOKENS] [TEMPERATURE] [TIMEOUT_SECS]`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_ai_backends.bats`:

```bats
# --- Anthropic backend ---

@test "anthropic backend parses content text via curl+jq" {
    run zsh -c '
curl() { printf "%s" "{\"content\":[{\"type\":\"text\",\"text\":\"mocked anthropic response\"}]}"; }
export ANTHROPIC_API_KEY=test-key
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-core.zsh"
source "'"$NIVUUS_SHELL_DIR"'/config/09-ai-backend-anthropic.zsh"
_ai_backend_anthropic_call "hello" "claude-haiku-4-5" 100 0.3 5
'
    [ "$status" -eq 0 ]
    [ "$output" = "mocked anthropic response" ]
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `NIVUUS_SHELL_DIR="$(pwd)" bats tests/unit/test_ai_backends.bats`
Expected: the 3 new tests FAIL — `config/09-ai-backend-anthropic.zsh` does not exist yet.

- [ ] **Step 3: Create `config/09-ai-backend-anthropic.zsh`**

```zsh
#!/usr/bin/env zsh
# =============================================================================
# AI Backend - Anthropic
# =============================================================================
# Talks to the Anthropic Messages REST API.
# =============================================================================

_ai_backend_anthropic_call() {
    local prompt="$1"
    local model="${2:-${ANTHROPIC_MODEL:-claude-haiku-4-5}}"
    local max_tokens="${3:-1024}"
    local temperature="${4:-0.3}"
    local timeout_secs="${5:-15}"

    if ! command -v jq &>/dev/null; then
        print -u2 -- "The anthropic backend requires jq to parse API responses."
        return 1
    fi

    local api_key="$ANTHROPIC_API_KEY"
    [[ -z "$api_key" ]] && return 1

    local escaped_prompt=$(_ai_json_escape "$prompt")
    local json_payload="{\"model\":\"${model}\",\"max_tokens\":${max_tokens},\"temperature\":${temperature},\"messages\":[{\"role\":\"user\",\"content\":\"$escaped_prompt\"}]}"

    local api_response=$(timeout "$timeout_secs" curl -s -X POST "https://api.anthropic.com/v1/messages" \
        -H "x-api-key: ${api_key}" \
        -H "anthropic-version: 2023-06-01" \
        -H 'Content-Type: application/json' \
        -d "$json_payload" 2>/dev/null)

    [[ -z "$api_response" ]] && return 1

    local result=$(print -r -- "$api_response" | jq -r '.content[0].text // empty' 2>/dev/null)

    [[ -z "$result" ]] && return 1

    print -r -- "$result"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `NIVUUS_SHELL_DIR="$(pwd)" bats tests/unit/test_ai_backends.bats`
Expected: all PASS (14/14 so far)

- [ ] **Step 5: Commit**

```bash
git add config/09-ai-backend-anthropic.zsh tests/unit/test_ai_backends.bats
git commit -m "feat(ai): add Anthropic backend"
```

---

### Task 4: Gemini `cli` auth mode (Antigravity CLI)

**Files:**
- Modify: `config/09-ai-backend-gemini.zsh`
- Test: `tests/unit/test_ai_backends.bats` (append)

**Interfaces:**
- Consumes: `GEMINI_AUTH_MODE` (Task 1, typeset in `09-ai-backend-gemini.zsh`).
- Produces: `_ai_gemini_cli_call PROMPT MODEL TIMEOUT_SECS` (internal helper, called from `_ai_backend_gemini_call` when `GEMINI_AUTH_MODE=cli`).

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_ai_backends.bats`:

```bats
# --- Gemini backend (cli / Antigravity mode) ---

@test "gemini cli mode shells out to agy and parses .response" {
    local fake_bin_dir="$BATS_TEST_TMPDIR/fake-agy"
    mkdir -p "$fake_bin_dir"
    cat > "$fake_bin_dir/agy" <<'EOF'
#!/usr/bin/env bash
echo '{"response":"mocked agy response","status":"SUCCESS"}'
EOF
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `NIVUUS_SHELL_DIR="$(pwd)" bats tests/unit/test_ai_backends.bats`
Expected: the first two new tests FAIL (`_ai_gemini_cli_call` is undefined); the third already passes (from Task 1's `typeset -g GEMINI_AUTH_MODE="${GEMINI_AUTH_MODE:-api-key}"`).

- [ ] **Step 3: Add `_ai_gemini_cli_call` to `config/09-ai-backend-gemini.zsh`**

Append at the end of the file:

```zsh

# Shell out to Antigravity CLI (agy) to spend a Google AI Pro/Ultra
# subscription's quota instead of a metered API key. agy owns its own
# OAuth session (one-time interactive `agy` login, cached credentials) —
# no OAuth code lives in this repo. gemini-cli was discontinued for
# subscription/free-tier accounts on 2026-06-18; agy is its replacement.
_ai_gemini_cli_call() {
    local prompt="$1"
    local model="$2"
    local timeout_secs="$3"

    if ! command -v agy &>/dev/null; then
        print -u2 -- "GEMINI_AUTH_MODE=cli but 'agy' (Antigravity CLI) is not installed. Install it, or set GEMINI_AUTH_MODE=api-key."
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        print -u2 -- "GEMINI_AUTH_MODE=cli requires jq to parse the agy JSON response."
        return 1
    fi

    local cli_response
    cli_response=$(timeout "$timeout_secs" agy -p "$prompt" --model "$model" \
        --output-format json --print-timeout "${timeout_secs}s" 2>/dev/null)

    [[ -z "$cli_response" ]] && return 1

    local result
    result=$(print -r -- "$cli_response" | jq -r '.response // empty' 2>/dev/null)

    [[ -z "$result" ]] && return 1

    print -r -- "$result"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `NIVUUS_SHELL_DIR="$(pwd)" bats tests/unit/test_ai_backends.bats`
Expected: all PASS (17/17 so far)

- [ ] **Step 5: Commit**

```bash
git add config/09-ai-backend-gemini.zsh tests/unit/test_ai_backends.bats
git commit -m "feat(ai): add Gemini cli auth mode via Antigravity CLI"
```

---

### Task 5: `aihelp` multi-backend status display + integration test

**Files:**
- Modify: `config/10-ai.zsh:1-57` (the `aihelp` function and file header)
- Modify: `tests/integration/test_ai_workflow.bats`
- Modify: `doc/CLAUDE.md` (spot check, no further changes expected — verification only)

**Interfaces:**
- Consumes: `_ai_get_api_key`, `_ai_resolve_model`, `$AI_BACKEND`, `$GEMINI_AUTH_MODE` (all from Tasks 1-4).
- Produces: nothing new consumed elsewhere — `aihelp` is a leaf command.

- [ ] **Step 1: Write the failing test**

Append to `tests/integration/test_ai_workflow.bats` (after the existing "AI help shows command information" test):

```bats
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `NIVUUS_SHELL_DIR="$(pwd)" bats tests/integration/test_ai_workflow.bats`
Expected: the 2 new tests FAIL — `aihelp` doesn't print "Backend:" or Antigravity CLI status yet.

- [ ] **Step 3: Rewrite the `aihelp` function in `config/10-ai.zsh`**

Replace lines 1-57 (file header comment through the end of `aihelp()`) with:

```zsh
#!/usr/bin/env zsh
# =============================================================================
# AI-Powered Commands - Multi-Backend Integration
# =============================================================================
# Talks to the active AI backend (Gemini/OpenAI/Anthropic) via
# config/09-ai-core.zsh - no gemini-cli dependency for API-key mode.
# =============================================================================

# =============================================================================
# AI Help (always available)
# =============================================================================

aihelp() {
    local status_line

    if [[ "$AI_BACKEND" == "gemini" && "$GEMINI_AUTH_MODE" == "cli" ]]; then
        if command -v agy &>/dev/null; then
            status_line="✓ Antigravity CLI (agy) found"
        else
            status_line="✗ Antigravity CLI (agy) not found"
        fi
    elif _ai_get_api_key &>/dev/null; then
        status_line="✓ Configured"
    else
        status_line="✗ Not configured"
    fi

    # Use /bin/cat to bypass bat alias
    /bin/cat <<EOF
Nivuus AI Commands

General:
  ??                     - Get command suggestions
  ?? "find large files"  - Ask for specific task

Git:
  ?git "undo commit"     - Git-specific help
  ?gh "create repo"      - GitHub CLI help

Explain:
  why "tar -xzf file"    - Quick explanation
  explain "complex cmd"  - Detailed breakdown
  ask "how to compress"  - General question

AI Suggestions (Interactive):
  Manual:  Ctrl+↓ or Ctrl+2 - Show AI menu
  Auto:    export ENABLE_AI_AUTO_DEBOUNCE=true
  Delay:   Menu appears after 2s of inactivity
  Help:    ai_suggestions_help

AI Terminal Titles:
  Creative terminal titles powered by AI
  Enable:  export ENABLE_AI_TERMINAL_TITLES=true
  Stats:   ai-title-stats
  Help:    ai-title-help

Configuration:
  Backend: $AI_BACKEND
  Model: $(_ai_resolve_model)
  Status: $status_line

Setup:
  Gemini:    export GOOGLE_API_KEY='...' (get one: https://aistudio.google.com/apikey)
             or export GEMINI_AUTH_MODE=cli (uses Antigravity CLI + your AI Pro/Ultra subscription)
  OpenAI:    export AI_BACKEND=openai OPENAI_API_KEY='...'
  Anthropic: export AI_BACKEND=anthropic ANTHROPIC_API_KEY='...'
EOF
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `NIVUUS_SHELL_DIR="$(pwd)" bats tests/integration/test_ai_workflow.bats`
Expected: all PASS

- [ ] **Step 5: Run the full test suite**

Run: `NIVUUS_SHELL_DIR="$(pwd)" bats tests/unit/ tests/integration/`
Expected: all PASS

- [ ] **Step 6: Commit**

```bash
git add config/10-ai.zsh tests/integration/test_ai_workflow.bats
git commit -m "feat(ai): show active backend and auth status in aihelp"
```
