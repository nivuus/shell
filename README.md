# Nivuus Shell

> A modern, fast, AI-powered ZSH shell with a configurable theme/prompt and intelligent features

![Version](https://img.shields.io/github/v/release/nivuus/shell?label=version)
![License](https://img.shields.io/badge/license-MIT-black.svg)
![Shell](https://img.shields.io/badge/shell-ZSH-black.svg)
![Performance](https://img.shields.io/badge/startup-<100ms-black.svg)
![Tests](https://github.com/nivuus/shell/workflows/Tests/badge.svg)

## Features

- **Lightning Fast** - Sub-100ms startup time (lazy-loaded completion)
- **Configurable Theme & Prompt** - Nord by default, swap themes or the prompt layout via `~/.zsh_local`
- **AI-Powered** - Command suggestions via the Gemini API
- **Modern Vim** - Ctrl+C/V/X/A shortcuts
- **Smart Navigation** - History prefix search with ↑/↓
- **Auto Node.js** - Version switching with .nvmrc
- **Python Venv** - Auto-detection in prompt (venv/conda/poetry)
- **Cloud Context** - AWS/GCP/Azure in prompt
- **Safety Checks** - Warns before dangerous commands
- **Git Integration** - Fast shortcuts + beautiful prompt
- **Zero Config** - Works out of the box

## Quick Start

### One-Line Installation

Install Nivuus Shell with a single command:

```bash
git clone https://github.com/nivuus/shell.git /tmp/nivuus-shell && /tmp/nivuus-shell/install.sh --non-interactive && rm -rf /tmp/nivuus-shell && exec zsh
```

This will:
1. Clone the repository to `/tmp/nivuus-shell`
2. Run the installation automatically (no prompts)
3. Clean up the temporary directory
4. Restart your shell with Nivuus

### Manual Installation

#### User Installation (Recommended)
```bash
git clone https://github.com/nivuus/shell.git
cd nivuus-shell
./install.sh
```

#### System-Wide Installation
```bash
git clone https://github.com/nivuus/shell.git
cd nivuus-shell
sudo ./install.sh --system
```
> **Note:** `--system` is temporarily unavailable (it now exits with an error). Per-user installation above is unaffected.

### Restart Your Terminal

```bash
exec zsh
# or just restart your terminal
```

## Usage

### AI Commands

Get intelligent command suggestions powered by Gemini:

```bash
??                      # Get command suggestions
?? "find large files"   # Ask for specific task
?git "undo commit"      # Git-specific help
why "tar -xzf file"     # Explain a command
explain "complex cmd"   # Detailed explanation
ask "how to compress"   # General question
aihelp                  # Show all AI commands
```

**Setup AI:**
- AI commands require a Google Gemini API key
- Get a key: https://aistudio.google.com/apikey
- Configure: `export GOOGLE_API_KEY='your-api-key'`

### Modern Vim Editing

Edit files with familiar keyboard shortcuts:

```bash
vedit myfile.txt        # Edit with auto environment detection
vim.modern myfile.txt   # Full-featured local vim
vim.ssh myfile.txt      # Optimized for SSH
vim_help                # Show all shortcuts
```

**Shortcuts in Vim:**
- **Ctrl+C** - Copy
- **Ctrl+X** - Cut
- **Ctrl+V** - Paste
- **Ctrl+A** - Select all
- **Ctrl+S** - Save
- **Ctrl+Z** - Undo

### Smart Navigation

Type a command prefix, then press ↑ or ↓ to search history:

```bash
# Type 'git' then press ↑/↓ to cycle through:
git status
git add .
git commit -m "..."
git push
```

**Directory shortcuts:**
```bash
..                      # Go up one directory
...                     # Go up two directories
....                    # Go up three directories
d                       # List recent directories
1-5                     # Jump to directory in stack
```

### Git Shortcuts

```bash
gs                      # git status
ga                      # git add
gc                      # git commit
gp                      # git push
gl                      # git log (beautiful)
gd                      # git diff
gb                      # git branch
gco                     # git checkout
```

### Node.js Auto-Switching

Nivuus automatically switches Node.js versions when you enter a directory with `.nvmrc`:

```bash
# Just cd into a project
cd my-project           # Automatically loads correct Node.js version

# NVM utilities
nvm-install             # Install NVM
nvm-health              # Check NVM status
```

### Python Virtual Environments

Automatic detection and display of Python virtual environments:

```bash
venv                    # Activate venv in current directory
venv-create             # Create new .venv
venv-info               # Show active environment info
```

**Prompt shows:**
- `(venv)` for venv/virtualenv
- `(conda:myenv)` for Conda environments
- `(poetry)` for Poetry

### Cloud Provider Context

See your active cloud context in the prompt:

```bash
# AWS
export AWS_PROFILE=production    # Shows: aws:production

# GCP
gcloud config set project myapp  # Shows: gcp:myapp

# Azure
az account set --subscription X  # Shows: az:X
```

### Command Safety

Automatic protection against dangerous commands:

```bash
rm -rf /                # Requires typing 'yes' to confirm
chmod 777 file          # Shows warning
safe-rm .env            # Extra protection for important files
```

### File Management

```bash
ll                      # Beautiful file list
tree                    # Directory tree
f <pattern>             # Fast file search
search <pattern>        # Search file contents
mkcd mydir              # Create and enter directory
extract archive.tar.gz  # Extract any archive
backup myfile           # Create timestamped backup
```

### Network Tools

```bash
myip                    # Show public IP
localip                 # Show local IPs
ports                   # List open ports
weather Paris           # Get weather forecast
```

### System Monitoring

```bash
healthcheck             # Complete system diagnostics
benchmark               # Performance testing
cleanup                 # Clean cache and temp files
zsh_info                # Show shell configuration
nivuus-version          # Show current version
nivuus-version --check  # Check for updates
nivuus-update           # Install latest update
```

## Theme & Prompt

Nivuus ships with the [Nord color scheme](https://www.nordtheme.com/) by default, but the theme
and the prompt layout are both configurable — no code changes needed.

### Prompt Format (default)

```
[hostname] > ~/path (venv) aws:prod [firebase-project] git:(branch)○     [jobs]
```

- **Green `>`** - Last command succeeded
- **Red `>`** - Last command failed
- **[hostname]** - Shows in SSH sessions
- **(venv)** - Active Python virtual environment
- **aws:prod** - Cloud provider context (AWS/GCP/Azure)
- **[project]** - Active Firebase project
- **git:(branch)○** - Git branch with status (○ dirty, ● clean)
- **[jobs]** - Background jobs on the right (RPROMPT)

### Customization

Edit `~/.zsh_local` to customize:

```bash
# --- Theme ---
export NIVUUS_THEME='dracula'          # Built-in: nord (default), dracula
# export NIVUUS_THEME_DIR="$HOME/.config/nivuus-shell/themes"  # custom theme folder
# export NIVUUS_THEME_FILE="$HOME/my-theme.zsh"                # or one specific file

# --- Prompt layout ---
# Tokens: {ssh} {root} {status} {path} {venv} {cloud} {firebase} {git} {jobs}
export NIVUUS_PROMPT_FORMAT='{status} {path}{git} '
export NIVUUS_RPROMPT_FORMAT='{jobs}'

# Performance tuning
export GIT_PROMPT_CACHE_TTL=5          # Git cache (default: 2s)
export ENABLE_FIREBASE_PROMPT=false    # Disable Firebase info
export ENABLE_PROJECT_DETECTION=false  # Disable project detection

# Python virtual environments
export ENABLE_PYTHON_VENV=false        # Disable venv in prompt
export ENABLE_PYTHON_AUTO_ACTIVATE=true # Auto-activate venv on cd

# Cloud provider context
export ENABLE_CLOUD_PROMPT=false       # Disable cloud context in prompt

# Command safety
export ENABLE_SAFETY_CHECKS=false      # Disable safety warnings
export ENABLE_SAFE_ALIASES=true        # Override rm/chmod with safe versions

# bat (cat) styling
export BAT_STYLE="plain"                # Options: plain, auto, numbers, grid, header
                                        # Combine: "numbers,grid"

# AI configuration
export GOOGLE_API_KEY='your-api-key'   # https://aistudio.google.com/apikey
export GEMINI_MODEL='gemini-3.1-flash-lite'
```

See [PROMPT.md](doc/PROMPT.md) for the full list of prompt tokens and the theme file contract
(to write your own theme, copy `themes/nord.zsh` or `themes/dracula.zsh`).

## Performance

Nivuus is optimized for speed:

- **Actual:** <100ms startup time (typically 40-60ms)
- **Lazy-loaded completion** - compinit loads on first TAB (~300ms saved!)
- **Lazy loading** for NVM and heavy features
- **Git caching** with 2s TTL
- **Compiled ZSH files** for faster loading
- **No external plugins** - pure ZSH

### Benchmark Your Shell

```bash
benchmark               # Run performance tests
```

## Configuration

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

Automatic backups are created at:
- During installation: `~/.config/nivuus-shell-backup/`
- Auto-maintenance: Weekly cleanup

## Updating

Nivuus Shell includes an automatic update system that checks for new releases weekly and installs them automatically with checksum verification.

### Check Current Version

```bash
nivuus-version              # Show current version
nivuus-version --check      # Check for available updates
```

### Automatic Updates

- **Weekly checks** - Checks for new releases every 7 days
- **Release-based** - Updates from official GitHub Releases (stable versions only)
- **Checksum verification** - SHA256 verification for security
- **Automatic installation** - Updates installed automatically with backup
- **Safe rollback** - Previous versions backed up to `~/.config/nivuus-shell-backup/`

### Manual Update

```bash
nivuus-update               # Check for and install updates manually
```

The update system will:
1. Check the latest release on GitHub
2. Download the release archive
3. Verify SHA256 checksum
4. Create a backup of your current installation
5. Install the new version
6. Recompile ZSH files

### Configuration

Customize auto-update behavior in `~/.zsh_local`:

```bash
# Disable auto-updates
export ENABLE_AUTOUPDATE=false

# Change check frequency (days)
export AUTOUPDATE_CHECK_FREQUENCY_DAYS=14

# Disable checksum verification (not recommended)
export NIVUUS_VERIFY_CHECKSUMS=false

# Use different GitHub repository
export NIVUUS_GITHUB_REPO=yourfork/nivuus-shell
```

### Rollback

If an update causes issues, restore from the timestamped backup:

```bash
# List backups
ls ~/.config/nivuus-shell-backup/

# Restore from backup
cp -r ~/.config/nivuus-shell-backup/pre-update-YYYYMMDD-HHMMSS/nivuus-shell ~/.nivuus-shell
exec zsh
```

### Release Process

Nivuus Shell uses semantic versioning (MAJOR.MINOR.PATCH):
- **MAJOR** - Breaking changes
- **MINOR** - New features (backward compatible)
- **PATCH** - Bug fixes

See [CHANGELOG.md](CHANGELOG.md) for release history.

## Development

Test changes without installing:

```bash
git clone https://github.com/nivuus/shell.git
cd nivuus-shell
./dev.sh
```

This launches a dev shell with:
- No file copying (uses repo directly)
- No compilation (instant reload)
- All changes take effect immediately

Edit any file, then restart the shell to see changes:
```bash
exec zsh
```

## Project Structure

```
nivuus-shell/
├── .github/
│   └── workflows/
│       ├── ci.yml         # CI entry point, delegates to nivuus/.github reusable workflows
│       └── release.yml    # Release automation
├── .zshrc                 # Main entry point
├── .vimrc.nord            # Vim configuration with Nord theme
├── install.sh             # Installation script
├── config/                # Modular configuration
│   ├── 00-core.zsh        # Core ZSH settings
│   ├── 05-prompt.zsh      # Configurable prompt (theme + format template)
│   ├── 06-git.zsh         # Git aliases
│   ├── 07-navigation.zsh  # Smart navigation
│   ├── 08-vim.zsh         # Vim integration
│   ├── 09-nodejs.zsh      # Node.js/NVM
│   ├── 10-ai.zsh          # AI commands
│   ├── 20-autoupdate.zsh  # Auto-update system (release-based)
│   └── ...                # Other modules
├── themes/
│   ├── nord.zsh           # Default color palette
│   └── dracula.zsh        # Second built-in theme / custom-theme template
├── bin/
│   ├── healthcheck        # System diagnostics
│   └── benchmark          # Performance testing
├── doc/
│   ├── FEATURES.md        # Complete feature list
│   ├── PROMPT.md          # Prompt documentation
│   └── CLAUDE.md          # Developer guide
├── CHANGELOG.md           # Release history
└── README.md              # This file
```

## Requirements

### Required
- **ZSH** 5.0+
- **Git** 2.0+
- **Curl** 7.0+

### Optional
- **Gemini API key** - For AI commands (get one at https://aistudio.google.com/apikey)
- **jq** - Robust JSON parsing for AI responses (falls back to grep/sed if absent)
- **NVM** - For Node.js version management
- **fd** - Fast file search (`cargo install fd-find`)
- **ripgrep** - Fast content search (`cargo install ripgrep`)
- **bat** - Better cat (`cargo install bat`)
- **eza** - Modern ls (`cargo install eza`)

## Documentation

- **[FEATURES.md](doc/FEATURES.md)** - Complete feature guide
- **[PROMPT.md](doc/PROMPT.md)** - Prompt configuration details
- **[CLAUDE.md](doc/CLAUDE.md)** - Developer guide and architecture

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details

## Credits

- **Nord Theme** - [Arctic Ice Studio](https://www.nordtheme.com/)
- **Gemini AI** - [Google](https://ai.google.dev/)

## Troubleshooting

### Shell loads slowly

```bash
# Disable features in ~/.zsh_local
export ENABLE_SYNTAX_HIGHLIGHTING=false
export ENABLE_PROJECT_DETECTION=false
export GIT_PROMPT_CACHE_TTL=5
```

### AI commands not working

```bash
# Set your Gemini API key (https://aistudio.google.com/apikey)
export GOOGLE_API_KEY='your-api-key'
```

### Git prompt not showing

```bash
# Check if in git repository
git status

# Increase cache if needed
export GIT_PROMPT_CACHE_TTL=5
```

### Vim shortcuts not working

```bash
# Check clipboard support
vim --version | grep clipboard

# Use fallback if needed
vim.ssh myfile  # Uses internal clipboard
```

## Support

- **Issues**: [GitHub Issues](https://github.com/nivuus/shell/issues)
- **Discussions**: [GitHub Discussions](https://github.com/nivuus/shell/discussions)

---

**Made with ❄️ and the Nord theme**

