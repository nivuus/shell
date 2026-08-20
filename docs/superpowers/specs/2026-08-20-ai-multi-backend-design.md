# AI multi-backend support

Date: 2026-08-20
Status: Approved for implementation

## Context

`config/09-ai-core.zsh` currently hardcodes a single AI backend: the Gemini
REST API, called directly via `curl`/`jq` with a `GOOGLE_API_KEY`. This is
shared by four consumers: `10-ai.zsh` (help/suggestions commands),
`19-ai-suggestions.zsh` (interactive completion menu),
`20-terminal-title.zsh` (AI terminal titles), `22-ai-errors.zsh` (AI error
explanations).

Goal: generalize to a provider-agnostic backend layer supporting Gemini,
OpenAI, and Anthropic via API key, while keeping the existing `_ai_api_call`
contract stable for all four consumers. Additionally, add an optional mode
for Gemini that shells out to the official `gemini` CLI binary so users with
a Google AI Pro/Ultra subscription can use their subscription quota (via
Google's Code Assist backend) instead of metered API-key billing.

### Rejected approach: custom Gemini OAuth device-code flow

Investigated implementing a device-code OAuth flow directly in zsh
(`oauth4webapi`-equivalent by hand) to draw on the user's Gemini
subscription quota without any external binary. Rejected because:

- Subscription-tier quota is served through Google's internal Code Assist
  API (`cloudcode-pa.googleapis.com`), not the public Generative Language
  API used elsewhere in this project.
- The OAuth client credentials that unlock that quota are first-party,
  hardcoded into `gemini-cli` itself ("ghost project"). Reusing them from
  third-party code violates Google's terms of service and risks account
  restriction.
- Registering an independent OAuth client does not help: the Code Assist
  API is not open to arbitrary third-party OAuth clients — even legitimate
  `gemini-cli` personal-account logins hit `403`/project-binding errors on
  this path (see `google-gemini/gemini-cli` issues #25189, #25167, #4723,
  #26105).

The only ToS-compliant way to spend subscription quota is to invoke an
official Google binary that owns that OAuth relationship itself. As of
2026-06-18, Google discontinued `gemini-cli` for Google AI Pro/Ultra and
free-tier accounts, migrating them to **Antigravity CLI** (`agy`) — so that
is the binary this project shells out to, not `gemini-cli`. See "Gemini
`cli` auth mode" below.

## Architecture

### File layout

- `config/09-ai-core.zsh` — dispatcher only: `_ai_api_call` (routes to
  `_ai_backend_${AI_BACKEND}_call`), `_ai_get_api_key` (routes to the active
  backend's key resolution), shared JSON-escaping helper
  (`_ai_json_escape`).
- `config/09-ai-backend-gemini.zsh` — existing Gemini REST logic (moved
  as-is) plus the new `cli` auth mode.
- `config/09-ai-backend-openai.zsh` — OpenAI Chat Completions.
- `config/09-ai-backend-anthropic.zsh` — Anthropic Messages API.

All backend functions share one contract:

```
_ai_backend_<name>_call PROMPT [MODEL] [MAX_TOKENS] [TEMPERATURE] [TIMEOUT_SECS]
# prints response text to stdout on success, returns 1 on any failure
```

### Backend selection

- `AI_BACKEND` env var: `gemini` (default, backward compatible) | `openai`
  | `anthropic`. Unknown value → clear error naming the valid choices.
- Per-backend model override: `GEMINI_MODEL`, `OPENAI_MODEL`,
  `ANTHROPIC_MODEL`. Defaults:
  - Gemini: `gemini-3.5-flash-lite`
  - OpenAI: `gpt-5.6-luna`
  - Anthropic: `claude-haiku-4-5`
- Per-backend API key env var: `GOOGLE_API_KEY`, `OPENAI_API_KEY`,
  `ANTHROPIC_API_KEY`. `_ai_get_api_key` resolves the one matching
  `$AI_BACKEND` (Gemini keeps its existing gemini-cli-config fallback).

### Backend-aware model resolution across existing consumers

Today, `10-ai.zsh`, `19-ai-suggestions.zsh` (`AI_SUGGESTION_MODEL`),
`20-terminal-title.zsh` (`AI_TITLE_MODEL`), and `22-ai-errors.zsh`
(`AI_ERROR_MODEL`) each hardcode `gemini-3.1-flash-lite` (or
`${GEMINI_MODEL:-gemini-3.1-flash-lite}`) as their fallback model, and pass
it explicitly to `_ai_api_call`. Left as-is, switching `AI_BACKEND=openai`
would still send a Gemini model name to the OpenAI API and fail. Fix:

- `09-ai-core.zsh` gains `_ai_resolve_model()`, which returns the correct
  default model for the currently active `$AI_BACKEND`:
  ```
  _ai_resolve_model() {
      case "$AI_BACKEND" in
          openai) print -r -- "${OPENAI_MODEL:-gpt-5.6-luna}" ;;
          anthropic) print -r -- "${ANTHROPIC_MODEL:-claude-haiku-4-5}" ;;
          *) print -r -- "${GEMINI_MODEL:-gemini-3.5-flash-lite}" ;;
      esac
  }
  ```
- `10-ai.zsh`: all 7 call sites drop the explicit
  `"${GEMINI_MODEL:-$AI_DEFAULT_MODEL}"` argument; `_ai_api_call` fills in
  the model itself via `_ai_resolve_model` whenever the MODEL argument is
  empty.
- `19-ai-suggestions.zsh`, `20-terminal-title.zsh`, `22-ai-errors.zsh` keep
  their dedicated override vars (a user may want a different model for
  suggestions than for the general default), but their fallback changes
  from the hardcoded Gemini string to `$(_ai_resolve_model)`, e.g.:
  ```
  typeset -g AI_SUGGESTION_MODEL="${AI_SUGGESTION_MODEL:-$(_ai_resolve_model)}"
  ```
- `AI_DEFAULT_MODEL` (currently in `09-ai-core.zsh`) is removed —
  superseded by `_ai_resolve_model`.
- `_ai_api_call`: when its MODEL argument is empty, call
  `_ai_resolve_model` before dispatching to the backend function.

### OpenAI backend

```
POST https://api.openai.com/v1/chat/completions
Authorization: Bearer $OPENAI_API_KEY
Body: {"model":..,"messages":[{"role":"user","content":<prompt>}],
       "max_tokens":..,"temperature":..}
Parse: jq -r '.choices[0].message.content // empty'
```

### Anthropic backend

```
POST https://api.anthropic.com/v1/messages
x-api-key: $ANTHROPIC_API_KEY
anthropic-version: 2023-06-01
Body: {"model":..,"max_tokens":..,"temperature":..,
       "messages":[{"role":"user","content":<prompt>}]}
Parse: jq -r '.content[0].text // empty'
```

OpenAI and Anthropic backends require `jq` — no grep-based fallback parser
(unlike Gemini's existing fallback), since their nested JSON shapes make
grep-parsing unreliable. If `jq` is missing, fail with a clear message
rather than attempting a fragile parse.

### Gemini `cli` auth mode (Antigravity CLI)

- New var `GEMINI_AUTH_MODE`: `api-key` (default) | `cli`.
- When `cli` and the `agy` binary (Antigravity CLI) is present in `$PATH`,
  `_ai_backend_gemini_call` shells out instead of calling `curl`:
  ```
  timeout "$timeout_secs" agy -p "$prompt" --model "$model" \
      --output-format json --print-timeout "${timeout_secs}s"
  ```
  and parses `.response` via `jq` (confirmed against
  `antigravity.google/docs/cli/headless`: JSON envelope has `response`,
  `status`, `usage`, `duration_seconds`; non-zero exit / non-`SUCCESS`
  `status` on failure).
- If `GEMINI_AUTH_MODE=cli` but `agy` is not on `$PATH`, fail with a
  message pointing at installing Antigravity CLI or switching back to
  `api-key`.
- Antigravity CLI's own OAuth/token storage/refresh is untouched — this
  project only invokes the already-authenticated binary (one-time
  interactive `agy` login by the user), no OAuth code lives in this repo.
- `_ai_get_api_key` is not called at all in `cli` mode.
- Note: `gemini-cli` was discontinued for Google AI Pro/Ultra and free-tier
  accounts on 2026-06-18, migrated to Antigravity CLI — this is why `agy`
  is the shell-out target, not the `gemini` binary.

### `aihelp` output

Displays the active `AI_BACKEND`, the active model, and — depending on
`GEMINI_AUTH_MODE` when the backend is `gemini` — either the API key status
or an `agy --version` check; for `openai`/`anthropic`, the matching API
key status.

## Testing

- `tests/unit/test_ai_backends.bats` (new): per backend, mock `curl` and
  assert URL/headers/payload construction and response parsing (success,
  empty response, HTTP error JSON).
- Dispatcher test: `AI_BACKEND=openai` routes to
  `_ai_backend_openai_call`; unset defaults to `gemini`; unknown value
  errors clearly.
- Gemini `cli` mode: fake `agy` script placed on `PATH` in the test,
  assert invocation shape and JSON parsing; separate case for binary
  absent.
- `tests/integration/test_ai_workflow.bats`: update for the new `aihelp`
  output (active backend + key/CLI status).
- No real network calls, consistent with existing test suite — everything
  mocked.

## Out of scope

- Custom Gemini OAuth device-code flow (rejected above).
- Local/offline backends (e.g. Ollama) — not requested for this iteration.
- Auto-detection of backend from whichever API key happens to be set —
  explicit `AI_BACKEND` only.
