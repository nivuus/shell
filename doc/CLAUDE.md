# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Nivuus Shell is a modern, performance-focused ZSH configuration framework with:
- **Performance target**: <300ms startup time
- **Theme**: Nord color scheme throughout (prompt, vim, all output)
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

1. **Theme First** (`themes/nord.zsh`) - Loads Nord color palette before any other module needs it
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

The prompt is built synchronously in `config/05-prompt.zsh` via `build_prompt()`:

```
[SSH] [ROOT] STATUS PATH (VENV) CLOUD [FIREBASE] GIT      [JOBS]
                                                           (RPROMPT)
```

**Main Prompt (left)**:
- **SSH detection**: Checks `$SSH_CLIENT`, `$SSH_TTY`, `$SESSION_TYPE`
- **Root detection**: Checks `$EUID` and `whoami`
- **Status color**: Uses previous command exit code (`$?`)
- **Python venv**: Shows `(venv)`, `(conda:name)`, or `(poetry)` in purple (180)
- **Cloud context**: Shows AWS/GCP/Azure active context
  - AWS: `aws:profile` in orange (214)
  - GCP: `gcp:project` in cyan (110)
  - Azure: `az:subscription` in blue (67)
- **Firebase**: Optional, parses `~/.config/configstore/firebase-tools.json`
- **Git info**: Cached with TTL, shows branch + status circles
  - `○` (red, empty circle): dirty/modified
  - `●` (green, filled circle): clean

**Right Prompt (RPROMPT)**:
- **Background jobs**: Shows running/stopped jobs via `background_jobs_info()`
- Uses ZSH native variables: `${(kv)jobstates}` and `${jobtexts}`
- Intelligent display:
  - ≤ 2 jobs: Shows names (`▶ vim ⏸ npm`)
  - \> 2 jobs: Shows counts (`▶ 3 ⏸ 1`)
- Colors: green (143) for running, red (167) for stopped
- Updates automatically on every prompt without manual `jobs` command

All colors use Nord palette via `themes/nord.zsh` color mappings.

### Vim Integration

The vim system (`config/08-vim.zsh` + `.vimrc.nord`) uses environment detection:

1. **Auto-detection** via `detect_vim_env()` checks for SSH, VS Code, web terminals
2. **Command wrappers**: `vedit`, `vim.modern`, `vim.ssh` load different configs
3. **Nord theme**: `.vimrc.nord` has inline Nord color definitions (no external vim plugins)
4. **Clipboard handling**: Auto-detects system clipboard support, falls back to internal registers

### AI Command System

`config/10-ai.zsh` calls the Gemini REST API directly via the shared helper in `config/09-ai-core.zsh` (`_ai_api_call`, `_ai_get_api_key`) - no `gemini-cli` binary dependency:

- **No fallback**: If `GOOGLE_API_KEY` is not set (and no `~/.gemini-cli/config.json` apiKey is found), shows setup instructions
- **Model config**: `GEMINI_MODEL` unset by default (falls back to `gemini-3.1-flash-lite` in `config/09-ai-core.zsh`)
- Functions (`??`, `?git`, `?gh`, `why`, `explain`, `ask`) call `_ai_api_call` from `config/09-ai-core.zsh`
- `config/19-ai-suggestions.zsh`, `config/20-terminal-title.zsh` and `config/22-ai-errors.zsh` share the same helper

## Critical Implementation Details

### Never Use These

- **Oh-My-Zsh** or similar frameworks - conflicts with modular architecture
- **Powerlevel10k** - we have custom Nord prompt
- **Heavy plugins** - breaks <300ms target
- **Bash syntax** in `.zsh` files - this is ZSH-specific

### Nord Color Palette

When modifying prompts or adding colored output, use these variables from `themes/nord.zsh`:

```zsh
$NORD_PATH          # Cyan (paths)
$NORD_SUCCESS       # Green (success indicators)
$NORD_ERROR         # Red (errors, git dirty)
$NORD_SSH           # Blue (SSH hostname)
$NORD_GIT_PREFIX    # Cyan (git decorations)
$NORD_GIT_BRANCH    # Red (branch names)
$NORD_FIREBASE      # Yellow (Firebase project)
$NORD_RESET         # Reset colors
```

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
source themes/nord.zsh          # Always load theme first
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
2. Call from `build_prompt()` in correct order
3. Use Nord colors only
4. Keep synchronous (no async prompt updates)

## File Purpose Reference

- **`.zshrc`**: Entry point, loads modules in order, measures startup time
- **`themes/nord.zsh`**: Nord color palette, must load before all other modules
- **`config/03-completion.zsh`**: Lazy-loaded completion system (loads on first TAB) - saves ~300ms startup
- **`config/05-prompt.zsh`**: Prompt builder, git caching, Firebase detection, Python venv, cloud context
- **`config/08-vim.zsh`**: Vim wrapper functions, environment detection
- **`config/09-nodejs.zsh`**: NVM lazy loading, auto-switch with .nvmrc, project detection
- **`config/09-python.zsh`**: Python virtual environment detection and management (venv/conda/poetry)
- **`config/09-ai-core.zsh`**: Shared Gemini REST API helper (`_ai_api_call`, `_ai_get_api_key`)
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
