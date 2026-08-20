# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Nivuus Shell is a modern, performance-focused ZSH configuration framework with:
- **Performance target**: <300ms startup time
- **Theme**: Configurable via `NIVUUS_THEME` (default: Nord). Prompt colors, vim, and command
  colorization all read from the loaded theme's `$THEME_*` variables — see "Theming & Prompt
  Format" below.
- **AI Integration**: direct Gemini REST API calls for command assistance (not GitHub Copilot, no gemini-cli dependency)
- **Philosophy**: Pure ZSH, no external plugin frameworks (no Oh-My-Zsh, no Prezto)

## Development Commands

### Testing & Validation

```bash
# Syntax validation
zsh -n .zshrc                    # Check main config
for f in config/*.zsh; do        # Check all modules
    zsh -n "$f"
done

# Performance testing
./bin/benchmark                  # Measure startup and module load times

# System health
./bin/healthcheck               # Verify installation and dependencies

# Test installation locally (non-destructive)
NIVUUS_SHELL_DIR="$(pwd)" zsh   # Run from current directory without installing
```

### Installation Testing

```bash
# User installation (in test environment)
./install.sh --non-interactive

# System installation
sudo ./install.sh --system --non-interactive

# With health check
./install.sh --health-check
```

## Architecture

### Modular Loading System

The shell loads in a specific order via `.zshrc`:

1. **Theme First** (`config/00-core.zsh` resolves `NIVUUS_THEME`/`NIVUUS_THEME_FILE`/`NIVUUS_THEME_DIR`
   and sources the matching `themes/*.zsh`, default `themes/nord.zsh`) - Loads the color palette
   before any other module needs it
2. **Numbered Modules** (`config/00-*.zsh` through `config/15-*.zsh`) - Sequential loading ensures dependencies are met
3. **Cleanup Last** (`config/99-cleanup.zsh`) - Finalizes environment, compiles files, shows welcome

**Critical**: Module numbers matter. Modules depend on earlier modules:
- `05-prompt.zsh` requires colors from `themes/nord.zsh`
- `07-navigation.zsh` requires functions from `04-keybindings.zsh`
- All modules may use environment variables from `01-environment.zsh`

### Performance Architecture

**Lazy Loading Pattern - Completion System** (see `config/03-completion.zsh`):
```zsh
# compinit is NOT loaded on startup - loads on first TAB press
# This saves ~300ms at startup (the biggest performance win)
_nivuus_lazy_compinit() {
    unfunction _nivuus_lazy_compinit
    autoload -Uz compinit
    compinit -C -d "$ZCOMPDUMP"
    _nivuus_setup_completion_styles
    zle expand-or-complete
}
zle -N _nivuus_lazy_compinit
bindkey '^I' _nivuus_lazy_compinit
```

**Lazy Loading Pattern - External Tools** (see `config/09-nodejs.zsh`):
```zsh
# NVM is not loaded on startup - function wrapper loads it on first use
nvm() {
    unfunction nvm
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
    nvm "$@"
}
```

**Caching Pattern** (see `config/05-prompt.zsh`):
```zsh
# Git status cached for 2 seconds (configurable via GIT_PROMPT_CACHE_TTL)
# Uses global variables: _GIT_PROMPT_CACHE_DIR, _GIT_PROMPT_CACHE_TIME, _GIT_PROMPT_CACHE_VALUE
```

**Compilation** (see `config/99-cleanup.zsh`):
- All `.zsh` files are compiled to `.zwc` on first load
- Recompiled only if source is newer than compiled version
- Happens asynchronously to avoid blocking

### Prompt System

The prompt is built synchronously in `config/05-prompt.zsh` via `build_prompt()`/`build_rprompt()`,
which expand the `NIVUUS_PROMPT_FORMAT`/`NIVUUS_RPROMPT_FORMAT` template strings (see
`doc/PROMPT.md`). Default layout:

```
[SSH] [ROOT] STATUS PATH (VENV) CLOUD [FIREBASE] GIT      [JOBS]
                                                           (RPROMPT)
```

Each segment is a function (`prompt_segment_ssh`, `prompt_segment_root`, `prompt_segment_status`,
`prompt_segment_path`, `prompt_python_venv`, `prompt_cloud_context`, `prompt_firebase`,
`git_prompt_info`, `background_jobs_info`) mapped to a `{token}` in `_NIVUUS_PROMPT_TOKENS`. To
add a new prompt component, write a function returning its rendered string and add it to that
map — it's then usable in any user-defined `NIVUUS_PROMPT_FORMAT`.

**Main Prompt (left)**:
- **SSH detection**: Checks `$SSH_CLIENT`, `$SSH_TTY`, `$SESSION_TYPE`
- **Root detection**: Checks `$EUID` and `whoami`
- **Status color**: Uses previous command exit code (`$?`)
- **Python venv**: Shows `(venv)`, `(conda:name)`, or `(poetry)` in `$THEME_COLORS[magenta]`
- **Cloud context**: Shows AWS/GCP/Azure active context
  - AWS: `aws:profile` in `$THEME_COLORS[orange]`
  - GCP: `gcp:project` in `$THEME_GIT_PREFIX`
  - Azure: `az:subscription` in `$THEME_SSH`
- **Firebase**: Optional, parses `~/.config/configstore/firebase-tools.json`
- **Git info**: Cached with TTL, shows branch + status circles
  - `○` (`$THEME_ERROR`, empty circle): dirty/modified
  - `●` (`$THEME_SUCCESS`, filled circle): clean

**Right Prompt (RPROMPT)**:
- **Background jobs**: Shows running/stopped jobs via `background_jobs_info()`
- Uses ZSH native variables: `${(kv)jobstates}` and `${jobtexts}`
- Intelligent display:
  - ≤ 2 jobs: Shows names (`▶ vim ⏸ npm`)
  - \> 2 jobs: Shows counts (`▶ 3 ⏸ 1`)
- Colors: `$THEME_SUCCESS` for running, `$THEME_ERROR` for stopped
- Updates automatically on every prompt without manual `jobs` command

All colors come from the loaded theme's `$THEME_*` variables / `$THEME_COLORS[...]` — never
hardcode an ANSI-256 code or hex value directly in prompt/colorization code.

### Vim Integration

The vim system (`config/08-vim.zsh` + `.vimrc.nord`) uses environment detection:

1. **Auto-detection** via `detect_vim_env()` checks for SSH, VS Code, web terminals
2. **Command wrappers**: `vedit`, `vim.modern`, `vim.ssh` load different configs
3. **Nord theme**: `.vimrc.nord` has inline Nord color definitions (no external vim plugins)
4. **Clipboard handling**: Auto-detects system clipboard support, falls back to internal registers

### AI Command System

`config/09-ai-core.zsh` is a multi-backend dispatcher (`_ai_api_call`, `_ai_get_api_key`, `_ai_resolve_model`) routing to `config/09-ai-backend-{gemini,openai,anthropic}.zsh` based on `AI_BACKEND` (default `gemini`). `config/10-ai.zsh` and friends call the dispatcher, never a backend file directly:

- **Backend selection**: `AI_BACKEND=gemini|openai|anthropic`; per-backend model override `GEMINI_MODEL`/`OPENAI_MODEL`/`ANTHROPIC_MODEL`; per-backend key `GOOGLE_API_KEY`/`OPENAI_API_KEY`/`ANTHROPIC_API_KEY`
- **No fallback**: If the active backend's key is not set (Gemini also checks `~/.gemini-cli/config.json`), shows setup instructions
- **Gemini `cli` auth mode**: `GEMINI_AUTH_MODE=cli` shells out to Antigravity CLI (`agy`) instead of the REST API, to use a Google AI Pro/Ultra subscription's quota
- **agy daemon** (`config/09-ai-agy-daemon.zsh`): in `cli` mode, calls go through one long-lived `agy --input-format stream-json` process instead of a fresh `agy -p` each time. A cold one-shot costs 3-6s of session startup for a ~2s model turn; the daemon brings that to ~1s per call (~5.5s for the first). One daemon per model, shared by every shell through a FIFO pair in `$XDG_RUNTIME_DIR/nivuus-agy-$UID/<model>/`, serialized with `flock`, prewarmed from `config/99-cleanup.zsh`, recycled every `AGY_DAEMON_MAX_TURNS` turns (the conversation grows ~6k input tokens per turn). Any failure falls back to the one-shot path. Manage with `ai-daemon`, disable with `AGY_DAEMON_ENABLED=false`
- **agy CLI gotchas**: `-p` takes an optional value, so `agy -p --input-format ...` silently makes `"--input-format"` the *prompt* — always use `--print=""` when the prompt comes from stdin. The stream-json input schema is `{"event":"user","message":{"role":"user","content":"..."}}` (`event`, not `type`)
- Functions (`??`, `?git`, `?gh`, `why`, `explain`, `ask`) call `_ai_api_call` from `config/09-ai-core.zsh`
- `config/19-ai-suggestions.zsh`, `config/20-terminal-title.zsh` and `config/22-ai-errors.zsh` share the same dispatcher

## Critical Implementation Details

### Never Use These

- **Oh-My-Zsh** or similar frameworks - conflicts with modular architecture
- **Powerlevel10k** - we have a custom, theme-configurable prompt (see "Theming & Prompt Format")
- **Heavy plugins** - breaks <300ms target
- **Bash syntax** in `.zsh` files - this is ZSH-specific
- **Hardcoded ANSI-256/hex color codes** in prompt/colorization/syntax-highlighting code - always
  go through the theme contract below, so the whole shell stays theme-agnostic

### Theming & Prompt Format

Nivuus Shell ships with a pluggable theme system and a template-driven prompt format — neither
is hardcoded. See `doc/PROMPT.md` for the user-facing docs.

**Theme contract** — every file in `themes/*.zsh` (loaded via `NIVUUS_THEME` /
`NIVUUS_THEME_FILE` / `NIVUUS_THEME_DIR`, resolved in `config/00-core.zsh`) must define:

```zsh
$THEME_COLORS[...]   # assoc array, ANSI-256 codes: bg_main, bg_light, bg_select, comment,
                      # fg_main, fg_light, fg_bright, cyan_light, cyan, blue_light, blue,
                      # red, orange, yellow, green, magenta
$THEME_HEX[...]       # assoc array, same keys, hex codes (for fzf/eza/delta)
$THEME_PATH $THEME_SUCCESS $THEME_ERROR $THEME_SSH $THEME_ROOT
$THEME_GIT_PREFIX $THEME_GIT_BRANCH $THEME_ACCENT $THEME_MUTED $THEME_RESET
$THEME_BAT_NAME       # e.g. "Nord", "Dracula" - passed to `bat --theme`
$THEME_DELTA_SYNTAX    # passed to `git config delta.syntax-theme`
$LS_COLORS $GREP_COLORS
```

Built-in themes: `themes/nord.zsh` (default), `themes/dracula.zsh` (second example proving the
contract is truly pluggable). Copy either one as a template for a custom theme.

**Prompt format contract** — `config/05-prompt.zsh` expands `NIVUUS_PROMPT_FORMAT`/
`NIVUUS_RPROMPT_FORMAT` template strings, replacing `{token}` with a call to the mapped segment
function (`_NIVUUS_PROMPT_TOKENS`, see "Prompt System" above). Never reintroduce a hardcoded
segment order in `build_prompt()` — add new segments as functions + token map entries instead.

### Config File Patterns

When adding new config modules:

1. **Numbering**: Use `XX-name.zsh` where XX determines load order
2. **Safety checks**: Always check if commands exist before aliasing:
   ```zsh
   if ! command -v git &>/dev/null; then
       return
   fi
   ```
3. **Feature toggles**: Respect `ENABLE_*` variables for optional features
4. **Async patterns**: Use `(command &)` for non-blocking operations (suggestions, maintenance)

### Installation Script Architecture

`install.sh` supports two modes:

- **User mode** (default): Installs to `~/.nivuus-shell`, modifies `~/.zshrc`
- **System mode** (`--system`): Installs to `/etc/nivuus-shell`, creates `/etc/skel/.zshrc`

**Backup system**: Always backs up to `~/.config/nivuus-shell-backup/` before modifying configs.

## Testing Modifications

### Prompt Changes

```zsh
# Test prompt in isolated shell
NIVUUS_SHELL_DIR="$(pwd)" zsh -c 'source .zshrc; echo $PROMPT'

# Test git prompt caching
cd /path/to/git/repo
NIVUUS_SHELL_DIR="$(pwd)" zsh -c 'source .zshrc; git_prompt_info; git_prompt_info'  # Second call should be cached
```

### Performance Impact

After any changes, verify startup time:

```bash
./bin/benchmark
# Target: Average <300ms

# Detailed module timing
./bin/benchmark | grep "Individual Module"
```

### Module Changes

Test module in isolation:

```zsh
export NIVUUS_SHELL_DIR="$(pwd)"
source themes/nord.zsh          # Always load a theme first (nord or dracula)
source config/XX-yourmodule.zsh # Then your module
# Test functions/aliases here
```

## Common Patterns

### Adding New Aliases

Add to `config/15-aliases.zsh` - this is the catch-all for general aliases.
Git aliases go in `config/06-git.zsh`.

### Adding New Functions

Add to `config/14-functions.zsh` - this is the catch-all for utility functions.
Module-specific functions go in their respective modules.

### Adding Performance Toggles

```zsh
# In the relevant config file
if [[ "${ENABLE_FEATURE_NAME:-true}" != "true" ]]; then
    return
fi
```

Document in README.md under "Performance" section.

### Extending the Prompt

Modify `config/05-prompt.zsh`:
1. Add component function (e.g., `prompt_kubernetes()`)
2. Add it to `_NIVUUS_PROMPT_TOKENS` as a new `{token}`, and to the default
   `NIVUUS_PROMPT_FORMAT`/`NIVUUS_RPROMPT_FORMAT` in `.zshrc` if it should show by default
3. Use `$THEME_*` / `$THEME_COLORS[...]` only, never a hardcoded color code
4. Keep synchronous (no async prompt updates)

## File Purpose Reference

- **`.zshrc`**: Entry point, loads modules in order, measures startup time, sets
  `NIVUUS_THEME`/`NIVUUS_PROMPT_FORMAT`/`NIVUUS_RPROMPT_FORMAT` defaults
- **`themes/nord.zsh`**: Default color palette, must load before all other modules
- **`themes/dracula.zsh`**: Second built-in theme, also serves as a custom-theme template
- **`config/03-completion.zsh`**: Lazy-loaded completion system (loads on first TAB) - saves ~300ms startup
- **`config/05-prompt.zsh`**: Prompt builder, git caching, Firebase detection, Python venv, cloud context
- **`config/08-vim.zsh`**: Vim wrapper functions, environment detection
- **`config/09-nodejs.zsh`**: NVM lazy loading, auto-switch with .nvmrc, project detection
- **`config/09-python.zsh`**: Python virtual environment detection and management (venv/conda/poetry)
- **`config/09-ai-core.zsh`**: Multi-backend AI dispatcher (`_ai_api_call`, `_ai_get_api_key`, `_ai_resolve_model`)
- **`config/09-ai-agy-daemon.zsh`**: Persistent Antigravity CLI process (`_agy_daemon_call`, `ai-daemon`) - removes agy's 3-6s per-call startup
- **`config/09-ai-backend-gemini.zsh`** / **`09-ai-backend-openai.zsh`** / **`09-ai-backend-anthropic.zsh`**: Per-provider REST (and, for Gemini, Antigravity CLI) implementations
- **`config/10-ai.zsh`**: AI command wrappers (`??`, `?git`, `?gh`, `why`, `explain`, `ask`), calls the Gemini API directly
- **`config/21-safety.zsh`**: Command safety checks, dangerous pattern detection, safe alternatives
- **`config/99-cleanup.zsh`**: Compilation, welcome messages, final cleanup
- **`.vimrc.nord`**: Standalone vim config with inline Nord theme (no plugins)
- **`bin/healthcheck`**: Diagnostic script for installation verification
- **`bin/benchmark`**: Performance measurement script

## Documentation

- **[FEATURES.md](FEATURES.md)**: User-facing feature documentation
- **[PROMPT.md](PROMPT.md)**: Technical prompt architecture in French
- **[README.md](../README.md)**: User guide with installation, usage, troubleshooting
