#!/usr/bin/env bash
# =============================================================================
# Nivuus Shell - Installation Script
# =============================================================================
# Modern, fast, AI-powered ZSH shell with Nord theme
# Supports both user and system-wide installation
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
VERSION="3.0.0"
REPO_URL="https://github.com/maximeallanic/nivuus-shell"
GIT_REMOTE="git@github.com:maximeallanic/nivuus-shell.git"
GIT_BRANCH="master"

# =============================================================================
# Functions
# =============================================================================

print_header() {
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Nivuus Shell v${VERSION}${NC}"
    echo -e "${BLUE}  Installation${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Show usage
show_usage() {
    cat << EOF
Nivuus Shell Installation Script

Usage:
  ./install.sh [OPTIONS]

Options:
  --system              Install system-wide (requires sudo)
  --non-interactive     Skip confirmation prompts
  --health-check        Run health check after installation
  --no-backup           Skip backup of existing configuration
  --help                Show this help message

Examples:
  ./install.sh                          # User installation
  ./install.sh --system                 # System-wide installation
  ./install.sh --non-interactive        # Silent installation

EOF
    exit 0
}

# Parse arguments
parse_args() {
    INSTALL_MODE="user"
    INTERACTIVE=true
    RUN_HEALTH_CHECK=false
    BACKUP=true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --system)
                INSTALL_MODE="system"
                shift
                ;;
            --non-interactive)
                INTERACTIVE=false
                shift
                ;;
            --health-check)
                RUN_HEALTH_CHECK=true
                shift
                ;;
            --no-backup)
                BACKUP=false
                shift
                ;;
            --help)
                show_usage
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Run with --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Check if running as root
check_root() {
    if [[ "$INSTALL_MODE" == "system" ]] && [[ $EUID -ne 0 ]]; then
        print_error "System-wide installation requires sudo"
        echo "Run: sudo $0 --system"
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    echo "Checking dependencies..."

    local missing=()

    command -v zsh &>/dev/null || missing+=("zsh")
    command -v git &>/dev/null || missing+=("git")
    command -v curl &>/dev/null || missing+=("curl")

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing[*]}"
        echo ""
        echo "Install them with:"

        if command -v apt-get &>/dev/null; then
            echo "  sudo apt-get install ${missing[*]}"
        elif command -v yum &>/dev/null; then
            echo "  sudo yum install ${missing[*]}"
        elif command -v brew &>/dev/null; then
            echo "  brew install ${missing[*]}"
        else
            echo "  Use your package manager to install: ${missing[*]}"
        fi

        exit 1
    fi

    print_success "All required dependencies found"
}

# Backup existing configuration
backup_config() {
    if [[ "$BACKUP" != true ]]; then
        return
    fi

    echo ""
    echo "Backing up existing configuration..."

    local backup_dir="$HOME/.config/nivuus-shell-backup/pre-install-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"

    # Backup .zshrc
    if [[ -f "$HOME/.zshrc" ]]; then
        cp "$HOME/.zshrc" "$backup_dir/"
        print_success "Backed up .zshrc"
    fi

    # Backup .zsh_local
    if [[ -f "$HOME/.zsh_local" ]]; then
        cp "$HOME/.zsh_local" "$backup_dir/"
        print_success "Backed up .zsh_local"
    fi

    # Backup .zsh_history
    if [[ -f "$HOME/.zsh_history" ]]; then
        cp "$HOME/.zsh_history" "$backup_dir/"
        print_success "Backed up .zsh_history"
    fi

    # Backup existing Nivuus installation
    if [[ -d "$HOME/.nivuus-shell" ]]; then
        cp -r "$HOME/.nivuus-shell" "$backup_dir/"
        print_success "Backed up existing Nivuus Shell"
    fi

    print_info "Backup saved to: $backup_dir"
}

# Install Nivuus Shell
install_nivuus() {
    echo ""
    echo "Installing Nivuus Shell..."

    # Determine installation directory
    if [[ "$INSTALL_MODE" == "system" ]]; then
        INSTALL_DIR="/etc/nivuus-shell"
    else
        INSTALL_DIR="$HOME/.nivuus-shell"
    fi

    # Get script directory (current directory)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Create installation directory
    mkdir -p "$INSTALL_DIR"

    # Clean up old .zwc files in destination to avoid permission issues
    find "$INSTALL_DIR" -name '*.zwc' -type f -delete 2>/dev/null

    # Copy files (suppress .zwc permission errors)
    cp -r "$SCRIPT_DIR/config" "$INSTALL_DIR/" 2>&1 | grep -v "\.zwc.*Permission denied" || true
    cp -r "$SCRIPT_DIR/themes" "$INSTALL_DIR/" 2>/dev/null
    cp -r "$SCRIPT_DIR/bin" "$INSTALL_DIR/" 2>/dev/null
    cp "$SCRIPT_DIR/.vimrc.nord" "$INSTALL_DIR/" 2>/dev/null
    cp "$SCRIPT_DIR/.zshrc" "$INSTALL_DIR/" 2>/dev/null

    # Copy plugins directory if it exists
    if [[ -d "$SCRIPT_DIR/plugins" ]]; then
        cp -r "$SCRIPT_DIR/plugins" "$INSTALL_DIR/" 2>&1 | grep -v "\.zwc.*Permission denied" || true
    fi

    # Remove any compiled files that got copied (they will be regenerated)
    find "$INSTALL_DIR" -name '*.zwc' -type f -delete 2>/dev/null

    print_success "Copied Nivuus Shell files to $INSTALL_DIR"

    # Setup .zshrc
    echo ""
    echo "Configuring shell..."

    if [[ "$INSTALL_MODE" == "system" ]]; then
        # System-wide: create .zshrc in /etc/skel for new users
        cat > "/etc/skel/.zshrc" << EOF
# Nivuus Shell Configuration
export NIVUUS_SHELL_DIR="/etc/nivuus-shell"
source "\$NIVUUS_SHELL_DIR/.zshrc"
EOF
        print_success "Created /etc/skel/.zshrc for new users"

        # Update existing user's .zshrc
        if [[ -n "$SUDO_USER" ]]; then
            local user_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
            cat > "$user_home/.zshrc" << EOF
# Nivuus Shell Configuration
export NIVUUS_SHELL_DIR="/etc/nivuus-shell"
source "\$NIVUUS_SHELL_DIR/.zshrc"
EOF
            chown "$SUDO_USER:$SUDO_USER" "$user_home/.zshrc"
            print_success "Updated $SUDO_USER's .zshrc"
        fi
    else
        # User installation
        cat > "$HOME/.zshrc" << EOF
# Nivuus Shell Configuration
export NIVUUS_SHELL_DIR="$INSTALL_DIR"
source "\$NIVUUS_SHELL_DIR/.zshrc"
EOF
        print_success "Created ~/.zshrc"
    fi

    # Make bin scripts executable
    chmod +x "$INSTALL_DIR/bin"/*
    print_success "Made utility scripts executable"

    # Create version file for update tracking
    echo "$VERSION" > "$INSTALL_DIR/.version"
    print_success "Created version file (v$VERSION)"
}

# Install fzf + fzf-tab (real multi-select on TAB in completion menus)
install_fzf_tab() {
    echo ""
    echo "Setting up fzf-tab (multi-select completion)..."

    # Install fzf itself if missing (best-effort, never fatal)
    if ! command -v fzf &>/dev/null; then
        if command -v apt-get &>/dev/null; then
            sudo apt-get install -y fzf &>/dev/null && print_success "Installed fzf" \
                || print_warning "Could not install fzf automatically (install it manually for multi-select completion)"
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y fzf &>/dev/null && print_success "Installed fzf" \
                || print_warning "Could not install fzf automatically (install it manually for multi-select completion)"
        elif command -v yum &>/dev/null; then
            sudo yum install -y fzf &>/dev/null && print_success "Installed fzf" \
                || print_warning "Could not install fzf automatically (install it manually for multi-select completion)"
        elif command -v brew &>/dev/null; then
            brew install fzf &>/dev/null && print_success "Installed fzf" \
                || print_warning "Could not install fzf automatically (install it manually for multi-select completion)"
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm fzf &>/dev/null && print_success "Installed fzf" \
                || print_warning "Could not install fzf automatically (install it manually for multi-select completion)"
        else
            print_warning "No known package manager found - install fzf manually for multi-select completion"
        fi
    else
        print_success "fzf already installed"
    fi

    # Vendor the fzf-tab plugin (not packaged by distros, so we manage it ourselves)
    local fzf_tab_dir="$INSTALL_DIR/plugins/fzf-tab"
    if command -v git &>/dev/null; then
        if [[ -d "$fzf_tab_dir/.git" ]]; then
            git -C "$fzf_tab_dir" pull --ff-only &>/dev/null && print_success "Updated fzf-tab plugin" \
                || print_warning "Could not update fzf-tab plugin (keeping existing copy)"
        else
            rm -rf "$fzf_tab_dir" 2>/dev/null
            git clone --depth 1 https://github.com/Aloxaf/fzf-tab.git "$fzf_tab_dir" &>/dev/null \
                && print_success "Installed fzf-tab plugin" \
                || print_warning "Could not clone fzf-tab plugin (multi-select completion will stay disabled)"
        fi
    else
        print_warning "git not found - skipping fzf-tab plugin install"
    fi
}

# Create local configuration file
create_local_config() {
    if [[ -f "$HOME/.zsh_local" ]]; then
        print_info ".zsh_local already exists, skipping creation"
        return
    fi

    echo ""
    echo "Creating local configuration..."

    cat > "$HOME/.zsh_local" << 'EOF'
# Nivuus Shell - Local Configuration
# This file is for your personal customizations

# =============================================================================
# AI Configuration (Gemini API)
# =============================================================================

# Required for AI features - get a key at https://aistudio.google.com/apikey
# export GOOGLE_API_KEY='your-api-key'

# Optional: override the default Gemini model
# export GEMINI_MODEL='gemini-3.1-flash-lite'

# =============================================================================
# Performance Tuning
# =============================================================================

# Disable features for faster startup
# export ENABLE_SYNTAX_HIGHLIGHTING=false
# export ENABLE_PROJECT_DETECTION=false
# export ENABLE_FIREBASE_PROMPT=false
# export GIT_PROMPT_CACHE_TTL=5

# =============================================================================
# Custom Aliases & Functions
# =============================================================================

# Add your custom aliases here
# alias myalias='my command'

# Add your custom functions here
# myfunction() {
#     echo "Hello, World!"
# }

EOF

    print_success "Created ~/.zsh_local"
    print_info "Edit ~/.zsh_local to add your customizations"
}

# Initialize git repository for auto-updates
init_git_repo() {
    echo ""
    echo "Configuring auto-update system..."

    # Only for user installations (system installations don't need git)
    if [[ "$INSTALL_MODE" == "system" ]]; then
        print_info "System-wide installation: auto-update not configured"
        return
    fi

    # Initialize git if not already a repo
    if [[ ! -d "$INSTALL_DIR/.git" ]]; then
        (
            cd "$INSTALL_DIR"
            git init &>/dev/null
            git remote add origin "$GIT_REMOTE" &>/dev/null || true
            git add . &>/dev/null
            git commit -m "Initial Nivuus Shell installation" &>/dev/null || true
            git branch -M "$GIT_BRANCH" &>/dev/null
            git fetch origin "$GIT_BRANCH" &>/dev/null || true
        )
        print_success "Initialized git repository for auto-updates"
    else
        print_info "Git repository already initialized"
    fi

    # Create update check timestamp file
    date +%s > "$HOME/.nivuus-shell-last-update-check"
    print_success "Auto-update system configured (checks weekly)"
}

# Suggest optional tools
suggest_optional_tools() {
    echo ""
    echo -e "${BLUE}Optional Tools${NC}"
    echo "─────────────────────────────────────────────"

    local suggestions=()

    # AI tools
    [[ -n "$GOOGLE_API_KEY" ]] || suggestions+=("GOOGLE_API_KEY: get a key at https://aistudio.google.com/apikey (AI commands)")

    # Modern command replacements (colorization)
    command -v eza &>/dev/null || suggestions+=("eza: cargo install eza (colorized ls)")
    command -v bat &>/dev/null || suggestions+=("bat: cargo install bat (colorized cat)")
    command -v delta &>/dev/null || suggestions+=("delta: cargo install git-delta (colorized git diff)")
    command -v rg &>/dev/null || suggestions+=("ripgrep: cargo install ripgrep (colorized grep)")
    command -v grc &>/dev/null || suggestions+=("grc: apt install grc (generic colorizer)")

    # Other useful tools
    command -v fd &>/dev/null || suggestions+=("fd: cargo install fd-find (fast find)")
    [[ ! -d "$HOME/.nvm" ]] && suggestions+=("nvm: Run 'nvm-install' after installation")

    if [[ ${#suggestions[@]} -eq 0 ]]; then
        print_success "All optional tools already installed!"
    else
        echo "Consider installing these optional tools for enhanced experience:"
        echo ""
        for suggestion in "${suggestions[@]}"; do
            echo "  • $suggestion"
        done
        echo ""
        print_info "Run 'colorhelp' after installation to see colorization features"
    fi
}

# Set ZSH as default shell
set_default_shell() {
    if [[ "$SHELL" == "$(command -v zsh)" ]]; then
        print_success "ZSH is already your default shell"
        return
    fi

    if [[ "$INTERACTIVE" == true ]]; then
        echo ""
        read -p "Set ZSH as your default shell? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Skipped setting ZSH as default shell"
            return
        fi
    fi

    chsh -s "$(command -v zsh)"
    print_success "Set ZSH as default shell (restart terminal to apply)"
}

# Run health check
run_health_check() {
    if [[ "$RUN_HEALTH_CHECK" != true ]]; then
        return
    fi

    echo ""
    echo -e "${BLUE}Running health check...${NC}"
    echo ""

    if [[ -x "$INSTALL_DIR/bin/healthcheck" ]]; then
        "$INSTALL_DIR/bin/healthcheck"
    else
        print_warning "Health check script not found"
    fi
}

# Print final message
print_completion() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  Installation Complete!${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo ""

    echo "Next steps:"
    echo "  1. Restart your terminal or run: source ~/.zshrc"
    echo "  2. Run 'healthcheck' to verify installation"
    echo "  3. Run 'benchmark' to test performance"
    echo ""

    echo "Quick tips:"
    echo "  • ?? - Get AI command suggestions"
    echo "  • vedit <file> - Edit with modern vim (Ctrl+C/V)"
    echo "  • ↑ - Smart history search with prefix"
    echo "  • aihelp - Show all AI commands"
    echo "  • nivuus-update - Check for and install updates"
    echo ""

    echo "Documentation:"
    echo "  • Features: doc/FEATURES.md"
    echo "  • Prompt: doc/PROMPT.md"
    echo "  • Developer guide: doc/CLAUDE.md"
    echo ""

    print_info "Enjoy your new shell! ✨"
}

# =============================================================================
# Main Installation Flow
# =============================================================================

main() {
    # Parse arguments
    parse_args "$@"

    # Print header
    print_header

    # Check if running as root (if needed)
    check_root

    # Check dependencies
    check_dependencies

    # Confirm installation
    if [[ "$INTERACTIVE" == true ]]; then
        echo ""
        if [[ "$INSTALL_MODE" == "system" ]]; then
            echo "This will install Nivuus Shell system-wide for all users."
        else
            echo "This will install Nivuus Shell for the current user."
        fi
        read -p "Continue? (Y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            echo "Installation cancelled."
            exit 0
        fi
    fi

    # Backup existing configuration
    backup_config

    # Install Nivuus Shell
    install_nivuus

    # Install fzf-tab (multi-select completion)
    install_fzf_tab

    # Create local configuration
    create_local_config

    # Initialize git repository for auto-updates
    init_git_repo

    # Suggest optional tools
    suggest_optional_tools

    # Set ZSH as default shell
    set_default_shell

    # Run health check
    run_health_check

    # Print completion message
    print_completion
}

# Run main function
main "$@"
