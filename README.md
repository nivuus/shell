# Nivuus Shell

> A modern, fast, AI-powered ZSH shell with a configurable theme/prompt and intelligent features

[![Version](https://img.shields.io/github/v/release/maximeallanic/nivuus-shell?label=version)](https://github.com/maximeallanic/nivuus-shell/releases)
[![Tests](https://github.com/maximeallanic/nivuus-shell/actions/workflows/tests.yml/badge.svg?branch=master)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/tests.yml)
[![uninstall verified](https://github.com/maximeallanic/nivuus-shell/actions/workflows/uninstall-verified.yml/badge.svg?branch=master)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/uninstall-verified.yml)
[![Matrix](https://github.com/maximeallanic/nivuus-shell/actions/workflows/matrix.yml/badge.svg?branch=master)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/matrix.yml)
<!-- badge-proof: tests/performance/test_startup.bats -->
[![startup <300ms](https://img.shields.io/badge/startup-<300ms-brightgreen.svg)](https://github.com/maximeallanic/nivuus-shell/actions/workflows/matrix.yml)

## ✨ Features

- ⚡ **Fast, and held to it** - A CI test fails the build if an interactive shell takes more than 300ms to start
- 🎨 **Configurable Theme & Prompt** - Nord by default, swap themes or the prompt layout via `~/.zsh_local`
- 🤖 **Optional AI, your key, your provider** - `AI_BACKEND=gemini|openai|anthropic`, plus a command-not-found that names the package to install. Nivuus works fully without it
- 📝 **Modern Vim** - Ctrl+C/V/X/A shortcuts
- 🔍 **Smart Navigation** - History prefix search with ↑/↓
- 📦 **Auto Node.js** - Version switching with .nvmrc
- 🐍 **Python Venv** - Auto-detection in prompt (venv/conda/poetry)
- ☁️ **Cloud Context** - AWS/GCP/Azure in prompt
- 🛡️ **Safety Checks** - Warns before dangerous commands
- 🌿 **Git Integration** - Fast shortcuts, plus branch and dirty state in the prompt
- 🛠️ **Works unconfigured** - Sensible defaults; `~/.zsh_local` when you want otherwise

## 🚀 Quick Start

### Installation

```bash
curl -fsSL https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh | sh
```

The one-liner downloads the latest release archive, **verifies its SHA-256 checksum**, installs
into `~/.nivuus-shell` and adds a delimited block to your `~/.zshrc`. It leaves no git repository
and no temporary directory behind, needs no `sudo`, and does not require `git`. `wget` works too
(`wget -qO- <url> | sh`).

Other ways to install (manual download with checksum verification, development checkout,
per-platform prerequisites, `--minimal`, `--dry-run`, `--prefix`, pinning a version): see
**[doc/INSTALL.md](doc/INSTALL.md)**.

> Nivuus est conçu pour être empaqueté : quand il provient d'un gestionnaire
> de paquets, les mises à jour automatiques se désactivent et l'activation
> reste un acte par utilisateur (`nivuus enable`). Voir
> **[doc/PACKAGING.md](doc/PACKAGING.md)**.

### Uninstall

```bash
nivuus uninstall              # removes everything Nivuus wrote, restores your .zshrc
nivuus uninstall --purge      # also removes Nivuus's internal state (manifest, backups)
nivuus uninstall --dry-run    # shows what would be removed, changes nothing
```

Every modified file is restored byte-for-byte from the backup recorded at install time.
`~/.zsh_local` and `~/.zsh_history` are never deleted.

If Nivuus was installed by the old one-liner (before v3.1), a git repository was created in
`~/.nivuus-shell` and has been blocking updates ever since. `nivuus migrate` moves it aside
(it is moved, never deleted, and the path is printed); `nivuus doctor` reports it.

### Vérifier le trousseau de signature à l'installation (optionnel)

Les mises à jour sont authentifiées par des clés publiques livrées avec
l'installation. Tu peux épingler ce trousseau au moment de l'installer :

```bash
curl -fsSL https://raw.githubusercontent.com/maximeallanic/nivuus-shell/master/install.sh \
  | sh -s -- --verify-key <empreinte>
```

L'empreinte est publiée dans [SECURITY.md](SECURITY.md). Si le trousseau
embarqué ne correspond pas, l'installation est refusée **avant** la moindre
écriture.

**Limite honnête** : cela ne résout pas la **première installation**. Le
dépôt et la clé publique viennent de la même origine — qui contrôle cette
origine à cet instant sert son installeur *et* sa clé. Aucune signature ne
peut résoudre ça (first install / première installation : voir
[SECURITY.md](SECURITY.md)). Ce que la signature protège, c'est le canal de
**mise à jour** : récurrent, automatique, invisible, sur toutes les
machines, pour toujours.

### Restart Your Terminal

```bash
exec zsh
# or just restart your terminal
```

## 🧪 Plateformes testées

Chaque nuit, et avant chaque release, Nivuus est installé puis désinstallé sur chacune de ces
cibles ; l'empreinte de `$HOME` doit être identique bit pour bit avant et après. Le badge
**uninstall verified** ci-dessus rougit dès qu'une trace subsiste.

| Cible | Niveau de preuve |
|---|---|
| Ubuntu 22.04 | installation, shell réel, désinstallation, empreinte |
| Ubuntu 24.04 | installation, shell réel, désinstallation, empreinte |
| Debian 12 | installation, shell réel, désinstallation, empreinte |
| Arch Linux | installation, shell réel, désinstallation, empreinte |
| Fedora 41 | installation, shell réel, désinstallation, empreinte |
| Alpine 3.20 (musl) | installation, shell réel, désinstallation, empreinte — valide le chemin sans coreutils GNU |
| Ubuntu (GitHub runner) | matrice complète, quatre niveaux |
| macOS 14 (arm64) | installation, désinstallation, empreinte |
| WSL2 | **simulé** : marqueurs `/proc/version` et `WSL_DISTRO_NAME` injectés dans un conteneur Ubuntu. Valide la branche de code, pas l'environnement. |

Cette liste est vérifiée contre `.github/matrix.json` par `tests/unit/test_readme_badges.bats` :
ajouter une cible à la matrice sans l'ajouter ici fait échouer la CI, et inversement.

## 📖 Usage

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
- `AI_BACKEND` selects the provider: `gemini` (default), `openai`, `anthropic`
- Configure the matching key: `GOOGLE_API_KEY`, `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`
- Without a key, every AI command tells you so and everything else works

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
# 1..9                  Jump to the Nth directory in the stack
```

### Git Shortcuts

```bash
gs                      # git status
ga                      # git add
gc                      # git commit
gp                      # git push
gl                      # git log (graph, one line per commit)
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
ll                      # Detailed file list
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
nivuus doctor           # Diagnose an installation that misbehaves
benchmark               # Performance testing
cleanup                 # Clean cache and temp files
zsh_info                # Show shell configuration
nivuus update           # Check for a new release and install it
```

## 🎨 Theme & Prompt

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

## 📊 Performance

The startup budget is **enforced**, not observed: `tests/performance/test_startup.bats`
fails the build past 300ms. That is what makes the number worth printing.

- **Enforced budget:** 300ms — see [tests/performance/](tests/performance/)
- Typical times measured on the CI matrix: 26–46 ms — see [tests/performance/](tests/performance/)
- **Lazy-loaded completion** - compinit loads on first TAB
- **Lazy loading** for NVM and heavy features
- **Git caching** with 2s TTL
- **Compiled ZSH files** for faster loading
- **No external plugins** - pure ZSH

### Benchmark Your Shell

```bash
benchmark               # Run performance tests
```

## 🛠️ Configuration

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

Nivuus keeps two kinds of backup, and they are not interchangeable:

- **Install-time backup** — every file `nivuus install` was about to overwrite is
  copied, content-addressed, into `~/.local/state/nivuus/backups/`. This is what
  `nivuus uninstall` restores from, byte for byte. Removed only by
  `nivuus uninstall --purge`.
- **Manual config backup** — `config_backup` / `config_restore`, for your own
  snapshots of the shell configuration.

## 🔄 Updating

Nivuus Shell includes an automatic update system that checks for new releases weekly and installs them automatically. Each release is **signed**; an update whose signature does not verify against a key shipped with your installation is refused outright.

### Check and update

```bash
nivuus update               # Check for a new release and install it, signature verified
nivuus doctor               # Diagnose an installation that misbehaves
```

### Automatic Updates

- **Weekly checks** - Checks for new releases every 7 days
- **Release-based** - Updates from official GitHub Releases (stable versions only)
- **Signature verification** — chaque release est signée ; une mise à jour
  dont la signature n'est pas valide est refusée, sans repli sur la simple
  empreinte. Voir [SECURITY.md](SECURITY.md) pour ce que cela garantit —
  et ce que cela ne garantit pas, notamment pour la première installation.
- **Automatic installation** - Updates installed automatically with backup
- **Safe rollback** - Previous versions backed up to `~/.config/nivuus-shell-backup/`

### Manual Update

```bash
nivuus update               # Check for and install updates manually
```

The update system will:
1. Check the latest release on GitHub
2. Download the release archive, its `SHA256SUMS` and its signatures
3. **Verify the signature of `SHA256SUMS`** against the keys in `keys/`
   (signature first — comparing a digest against an unauthenticated
   `SHA256SUMS` proves nothing)
4. Verify the SHA256 digest of the archive
5. Create a backup of your current installation
6. Install the new version
7. Recompile ZSH files

If either verification fails, the update is refused **before** anything is
written, and your installation is left untouched. There is no fallback.

### Configuration

Customize auto-update behavior in `~/.zsh_local`:

```bash
# Disable auto-updates
export ENABLE_AUTOUPDATE=false

# Change check frequency (days)
export AUTOUPDATE_CHECK_FREQUENCY_DAYS=14

# Désactive UNIQUEMENT la comparaison d'empreinte SHA256 (déconseillé).
# Sans effet sur la vérification de signature, qui n'est jamais
# désactivable sur le chemin automatique.
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

## 🔧 Development

Test changes without installing:

```bash
git clone https://github.com/maximeallanic/nivuus-shell.git
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

## 🔧 Requirements

### Required
- **ZSH** 5.0+
- **Git** 2.0+
- **Curl** 7.0+

### Optional
- **An AI API key** - Optional. `AI_BACKEND` selects the provider: `gemini`
  (`GOOGLE_API_KEY`, or `GEMINI_AUTH_MODE=cli` with the Antigravity CLI),
  `openai` (`OPENAI_API_KEY`), `anthropic` (`ANTHROPIC_API_KEY`).
  Without a key, every AI command tells you so and everything else works.
- **jq** - Robust JSON parsing for AI responses (falls back to grep/sed if absent)
- **NVM** - For Node.js version management
- **fd** - Fast file search (`cargo install fd-find`)
- **ripgrep** - Fast content search (`cargo install ripgrep`)
- **bat** - Better cat (`cargo install bat`)
- **eza** - Modern ls (`cargo install eza`)

## 📚 Documentation

- **[FEATURES.md](doc/FEATURES.md)** - Complete feature guide
- **[PROMPT.md](doc/PROMPT.md)** - Prompt configuration details
- **[CLAUDE.md](doc/CLAUDE.md)** - Developer guide and architecture

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📝 License

MIT License - see LICENSE file for details

## 🙏 Credits

- **Nord Theme** - [Arctic Ice Studio](https://www.nordtheme.com/)
- **Gemini AI** - [Google](https://ai.google.dev/)

## 🐛 Troubleshooting

The answer to "it does not work" is `nivuus doctor`: it checks the tree, the
`~/.zshrc` block, the manifest and the signing keyring, and prints what to run.

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

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/maximeallanic/nivuus-shell/issues)
- **Discussions**: [GitHub Discussions](https://github.com/maximeallanic/nivuus-shell/discussions)

---

**Made with ❄️ and the Nord theme**

