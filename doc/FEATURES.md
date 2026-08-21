# Nivuus Shell - Feature List

Complete guide of what you can do with Nivuus Shell.

## Table of Contents

1. [AI-Powered Commands](#ai-powered-commands)
   - [Backends](#backends)
   - [Command not found](#command-not-found)
2. [Modern Text Editing](#modern-text-editing)
3. [Smart Navigation](#smart-navigation)
4. [Git Commands](#git-commands)
5. [Node.js Development](#nodejs-development)
6. [System Monitoring](#system-monitoring)
7. [File Management](#file-management)
8. [Network Tools](#network-tools)
9. [Configuration](#configuration)

---

## AI-Powered Commands

Get instant help and command suggestions from the AI provider of your choice.

### Backends

Nivuus talks to one of three providers. The active one is `AI_BACKEND`:

| `AI_BACKEND` | Credential | Model override | Default model |
|---|---|---|---|
| `gemini` (default) | `GOOGLE_API_KEY`, or `GEMINI_AUTH_MODE=cli` + the `agy` CLI | `GEMINI_MODEL` / `GEMINI_CLI_MODEL` | `gemini-3.5-flash-lite` |
| `openai` | `OPENAI_API_KEY` | `OPENAI_MODEL` | `gpt-5.6-luna` |
| `anthropic` | `ANTHROPIC_API_KEY` | `ANTHROPIC_MODEL` | `claude-haiku-4-5` |

```bash
# In ~/.zsh_local
export AI_BACKEND=anthropic
export ANTHROPIC_API_KEY=sk-ant-...
```

`GEMINI_AUTH_MODE=cli` spends a Google AI subscription's quota through the
Antigravity CLI (`agy`) instead of a metered API key. A persistent `agy`
daemon (`AGY_DAEMON_ENABLED`, on by default) avoids paying 3-6 s of process
startup on every call.

**No key, no breakage.** Every AI feature degrades to a message that names the
variable to set. Nothing else in the shell depends on it.

### Command not found

When you type a command that does not exist, Nivuus does not stop at
`command not found`. It looks up which package provides it -- first from the
system's own package database, then, if that fails, by asking the AI -- and
offers the exact install command for your distribution.

```bash
$ rg TODO src/
zsh: command not found: rg
  ripgrep provides `rg`
  -> sudo apt-get install -y ripgrep       [Enter to run, Ctrl-C to skip]
```

| Variable | Default | Effect |
|---|---|---|
| `ENABLE_AI_COMMAND_NOT_FOUND` | `true` | Turn the whole handler off |
| `AI_CNF_AUTO_PROMPT` | `true` | Offer to run the install command |
| `AI_CNF_RE_EXECUTE` | `true` | Re-run your original command after a successful install |
| `AI_CNF_TIMEOUT` | `8` | Give up rather than hang the prompt |
| `AI_COMMAND_NOT_FOUND_CACHE_TTL` | `86400` | Cache lifetime for a resolved lookup |

Answers are cached in `AI_COMMAND_NOT_FOUND_CACHE_DIR`, so the second miss on
the same command costs nothing.

```bash
ai-cnf-lookup rg        # ask without mistyping anything
ai-cnf-stats            # cache hit rate
ai-cnf-clear-cache      # forget everything it learned
ai-cnf-help             # the short version of this section
```

The native lookup needs no key. Only the AI fallback does.

### Quick Help
```bash
??                      # Get command suggestions
?? "find large files"   # Ask for specific task
?git "undo commit"      # Git-specific help
?gh "create repo"       # GitHub CLI assistance
```

### Command Understanding
```bash
why "tar -xzf file"     # Explain what a command does
explain "complex cmd"   # Get detailed explanation
ask "compress folder"   # General command help
aihelp                  # Show all AI commands
```

---

## Modern Text Editing

Edit files with modern keyboard shortcuts that work everywhere.

### Vim Shortcuts
- **Ctrl+C** - Copy selection
- **Ctrl+X** - Cut selection
- **Ctrl+V** - Paste
- **Ctrl+A** - Select all

### Commands
```bash
vedit <file>            # Edit file with modern shortcuts
vim.modern              # Full-featured vim
vim.ssh <file>          # Optimized for SSH/remote
vim_help                # Show vim shortcuts
```

**Automatic detection** - Adapts to local, SSH, VS Code, and web environments.

---

## Smart Navigation

Navigate your terminal efficiently with intelligent shortcuts.

### History Search
Type any command prefix, then use **↑** or **↓** to cycle through matching commands.

**Examples:**
```bash
# Type 'git' then press ↑/↓ to see:
git status
git add .
git commit -m "..."
git push

# Type 'npm' then press ↑/↓ to see:
npm install
npm run dev
npm test
```

### Keyboard Shortcuts
- **↑ / ↓** - Navigate history with prefix filtering
- **Ctrl+P / Ctrl+N** - Alternative navigation
- **Ctrl+R** - Search full history
- **Ctrl+S** - Forward search

### Directory Shortcuts
```bash
..                      # Go up one directory
...                     # Go up two directories
....                    # Go up three directories
.....                   # Go up four directories

d                       # List recent directories
1                       # Jump to previous directory
2-5                     # Jump to directory in stack
```

---

## Git Commands

Fast shortcuts for common git operations.

### Basic Operations
```bash
gs                      # git status (short format)
ga                      # git add
gaa                     # git add --all
gc                      # git commit
gcm                     # git commit -m "message"
gp                      # git push
gpl                     # git pull
```

### Advanced Operations
```bash
gd                      # git diff
gds                     # git diff --staged
gb                      # git branch
gba                     # git branch -a (all branches)
gco                     # git checkout
gcb                     # git checkout -b (new branch)
gl                      # git log (beautiful graph, last 10)
gla                     # git log (all branches)
```

**Prompt integration** - See current branch and git status in your prompt.

---

## Node.js Development

Automatic Node.js version management with zero configuration.

### Auto-Switching
- **Detects `.nvmrc`** - Automatically switches to project's Node.js version
- **Returns to default** - When leaving project directory
- **Works in VS Code** - Seamless integration with editor

### Commands
```bash
nvm-install             # Install NVM
nvm-update              # Update NVM to latest
nvm-health              # Check NVM status
nvm use <version>       # Switch Node.js version
nvm install <version>   # Install specific version
```

### Project Detection
Automatically detects and suggests commands for:
- 📦 **Node.js** - Shows `npm install`, `npm start`, `npm test`
- 🐍 **Python** - Shows `pip install`, `python main.py`
- 🦀 **Rust** - Shows `cargo build`, `cargo run`
- 🐹 **Go** - Shows `go mod download`, `go run .`

---

## Python Development

Python virtual environment detection and management with automatic display in prompt.

### Virtual Environment Detection
- **venv/virtualenv** - Shows `(venv)` in prompt
- **Conda** - Shows `(conda:env-name)` in prompt
- **Poetry** - Shows `(poetry)` in prompt
- **Auto-activation** - Optional auto-activation when entering project (disabled by default)

### Commands
```bash
venv                    # Activate venv in current directory (.venv, venv, env)
venv-create [name]      # Create new virtual environment (default: .venv)
venv-new [name]         # Alias for venv-create
venv-off                # Deactivate current virtual environment
venv-info               # Show info about active environment
venv-status             # Alias for venv-info
activate                # Quick activate for ./venv/bin/activate
```

### Configuration
```bash
# Enable auto-activation when entering directory with venv/
export ENABLE_PYTHON_AUTO_ACTIVATE=true

# Disable Python venv in prompt
export ENABLE_PYTHON_VENV=false
```

### Examples
```bash
# Create and use venv
venv-create             # Creates .venv
venv                    # Activates .venv

# Multiple venvs
venv-create myenv       # Create named venv
venv myenv              # Activate named venv

# Check status
venv-info               # Shows active venv details
```

---

## Cloud Provider Context

Display active cloud provider context in your prompt for AWS, GCP, and Azure.

### Supported Providers
- **AWS** - Shows active profile: `aws:production`
- **GCP** - Shows project: `gcp:my-project`
- **Azure** - Shows subscription: `az:my-subscription`

### What's Displayed
- **AWS**: `$AWS_PROFILE` (only if not "default")
- **GCP**: `$CLOUDSDK_CORE_PROJECT` (only if Firebase prompt disabled)
- **Azure**: `$AZURE_SUBSCRIPTION_ID` or subscription name

### Configuration
```bash
# Disable cloud context in prompt
export ENABLE_CLOUD_PROMPT=false
```

### Examples
```bash
# AWS
export AWS_PROFILE=production
# Prompt shows: aws:production

# GCP
gcloud config set project my-project
# Prompt shows: gcp:my-project

# Azure
az account set --subscription "My Subscription"
# Prompt shows: az:My Subscription
```

---

## Command Safety Checks

Protection against dangerous commands with automatic warnings and confirmations.

### Critical Checks (Require 'yes' confirmation)
- `rm -rf /` or `rm -rf ~` - Deleting critical directories
- `chmod 777 /` - Dangerous permissions on root
- `dd` to `/dev/sd*` - Raw disk writes
- `mkfs`, `fdisk` - Filesystem operations
- Removing `/boot`, `/etc`, `/usr`, `/var` - System directories
- Removing `sudo` package - Loss of admin access

### Warning Checks (Press Enter to continue)
- `rm -rf` - Recursive force deletion
- `git push --force` - Force push
- `sudo rm` - Root deletion
- `chmod 777` - World-writable permissions
- `find ... -delete` - Mass deletion

### Safe Alternatives
```bash
safe-rm <files>         # Warns before deleting important files
safe-chmod <mode>       # Warns about dangerous permissions
safety-help             # Show safety system help
```

### Configuration
```bash
# Disable all safety checks
export ENABLE_SAFETY_CHECKS=false

# Enable safe aliases (override rm and chmod)
export ENABLE_SAFE_ALIASES=true
```

### Examples
```bash
# This will require typing 'yes':
rm -rf /tmp/important

# This will show a warning:
chmod 777 myfile.sh

# Safe alternative with automatic checks:
safe-rm .env .npmrc
```

---

## System Monitoring

Keep your system healthy and performant.

### Health Checks
```bash
healthcheck             # Complete system analysis
benchmark               # Performance benchmarking
zsh_info                # Configuration details
```

### Maintenance
```bash
cleanup                 # Clean temporary files and cache
update_system           # Update packages and config
```

**Automatic maintenance** runs weekly to:
- Remove duplicate history entries
- Clean cache and temporary files
- Refresh completion database

---

## File Management

Modern, faster alternatives to traditional file commands.

### File Listing
```bash
ll                      # Beautiful file list with icons
la                      # List all files (including hidden)
tree                    # Directory tree view
```

### File Search
```bash
f <pattern>             # Fast file search
fd <pattern>            # Find files by name
rg <pattern>            # Search file contents
```

### File Operations
```bash
mkcd <directory>        # Create and enter directory
extract <archive>       # Extract any archive format
backup <file>           # Create timestamped backup
size <path>             # Show directory sizes
```

**Supported archives:** `.tar`, `.tar.gz`, `.zip`, `.rar`, `.7z`, `.bz2`

---

## Network Tools

Quick access to network information and utilities.

### Commands
```bash
myip                    # Show your public IP address
localip                 # Show local network addresses
ports                   # List open ports and processes
weather [city]          # Get weather forecast
```

### Examples
```bash
myip                    # 203.0.113.42
weather Paris           # 5-day forecast for Paris
ports                   # All listening ports with processes
```

---

## Configuration

Manage your shell configuration easily.

### Edit Configuration
```bash
config_edit             # Edit main config
config_edit local       # Edit local customizations
config_edit functions   # Edit custom functions
config_edit aliases     # Edit custom aliases
```

### Backup & Restore
```bash
config_backup           # Create manual backup
config_restore          # Restore from backup
```

`config_backup` writes to `~/.config/nivuus-shell-backup/`. It is *not* the
install-time backup: `nivuus install` records every file it was about to
overwrite in `~/.local/state/nivuus/backups/`, and that is what
`nivuus uninstall` restores from.

### Performance Tuning

Adjust performance vs features:

```bash
# In your ~/.zshrc, add:
export ENABLE_SYNTAX_HIGHLIGHTING=false  # Faster startup
export ENABLE_PROJECT_DETECTION=true     # Show project suggestions
```

---

## Quick Command Reference

### AI & Help
- `??`, `?git`, `?gh` - Command suggestions
- `why`, `explain`, `ask` - Understand commands
- `aihelp` - Show AI features

### Text Editing
- `vedit <file>` - Edit with modern shortcuts
- `Ctrl+C/X/V/A` - Copy/Cut/Paste/Select all

### Navigation
- `↑/↓` - Smart history search
- `..`, `...`, `....` - Go up directories
- `d`, `1-5` - Jump to recent directories

### Git
- `gs`, `ga`, `gc`, `gp` - Status, Add, Commit, Push
- `gl`, `gd`, `gb` - Log, Diff, Branch

### Node.js
- Auto-switches versions with `.nvmrc`
- `nvm-health` - Check installation

### System
- `healthcheck` - System diagnostics
- `cleanup` - Clean cache and temp files
- `benchmark` - Performance test

### Files
- `ll`, `tree` - List files beautifully
- `f <pattern>`, `rg <pattern>` - Search files
- `mkcd`, `extract`, `backup` - File utilities

### Network
- `myip`, `localip`, `ports`, `weather`

### Config
- `config_edit` - Edit configuration
- `config_backup` - Create backup

---

## Installation Modes

### User Installation (Default)
```bash
curl -fsSL https://github.com/maximeallanic/nivuus-shell/releases/latest/download/install.sh | bash
```

Install for current user only.

### System-Wide Installation

For a whole machine, use the administrator command rather than piping the network
into a privileged shell:

```bash
sudo nivuus install --system
```

It lays a shared tree under `/usr/local/share/nivuus-shell`, writes to **no** `$HOME`
and runs `chsh` for nobody: each user activates it with `nivuus enable`.
See [INSTALL.md](INSTALL.md) for the full administrator guide, including `--skel`,
`nivuus enable --all`, updates and removal.

### Options
```bash
./install.sh --help              # Show all options
./install.sh --non-interactive   # Silent installation
./install.sh --health-check      # Check installation health
```

---

## What You Get

✅ **Sub-100ms startup** - Lightning-fast shell
✅ **AI command help** - Google Gemini AI integration
✅ **Modern vim** - Ctrl+C/V shortcuts everywhere
✅ **Smart history** - Type prefix then ↑/↓
✅ **Auto Node.js** - Version switching with `.nvmrc`
✅ **Beautiful files** - Modern `ls`, `cat`, `grep`
✅ **Git shortcuts** - Fast git operations
✅ **Auto-maintenance** - Weekly cleanup
✅ **Cross-platform** - Linux, macOS, WSL2

---

## Documentation

- **[README.md](../README.md)** - Getting started guide
- **[CLAUDE.md](CLAUDE.md)** - Developer guide and architecture
- **[PROMPT.md](PROMPT.md)** - Prompt configuration reference

---

**License:** MIT
**Last Updated:** January 2025
