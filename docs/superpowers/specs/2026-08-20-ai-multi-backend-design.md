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

The only ToS-compliant way to spend subscription quota is to invoke the
official `gemini` binary, which owns that OAuth relationship itself. See
"Gemini `cli` auth mode" below.

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

### Gemini `cli` auth mode

- New var `GEMINI_AUTH_MODE`: `api-key` (default) | `cli`.
- When `cli` and the `gemini` binary is present in `$PATH`,
  `_ai_backend_gemini_call` shells out instead of calling `curl`:
  ```
  timeout "$timeout_secs" gemini -p "$prompt" --model "$model" \
      --output-format json
  ```
  and parses the response text field via `jq`.
- If `GEMINI_AUTH_MODE=cli` but `gemini` is not on `$PATH`, fail with a
  message pointing at installing gemini-cli or switching back to
  `api-key`.
- `gemini-cli`'s own OAuth/token storage/refresh (`~/.gemini/tokens.json`)
  is untouched — this project only invokes the already-authenticated
  binary, no OAuth code lives in this repo.
- `_ai_get_api_key` is not called at all in `cli` mode.

### `aihelp` output

Displays the active `AI_BACKEND`, the active model, and — depending on
`GEMINI_AUTH_MODE` when the backend is `gemini` — either the API key status
or a `gemini --version` check; for `openai`/`anthropic`, the matching API
key status.

## Testing

- `tests/unit/test_ai_backends.bats` (new): per backend, mock `curl` and
  assert URL/headers/payload construction and response parsing (success,
  empty response, HTTP error JSON).
- Dispatcher test: `AI_BACKEND=openai` routes to
  `_ai_backend_openai_call`; unset defaults to `gemini`; unknown value
  errors clearly.
- Gemini `cli` mode: fake `gemini` script placed on `PATH` in the test,
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
