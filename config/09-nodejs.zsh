#!/usr/bin/env zsh
# =============================================================================
# Node.js Development - NVM Integration
# =============================================================================
# Lazy loading + automatic version switching with .nvmrc
# =============================================================================

# =============================================================================
# NVM Lazy Loading
# =============================================================================

# Only load NVM when actually needed
if [[ -d "$HOME/.nvm" ]]; then
    # Lazy load NVM
    nvm() {
        unfunction nvm
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"
        nvm "$@"
    }

    # Lazy load node
    node() {
        unfunction node
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
        node "$@"
    }

    # Lazy load npm
    npm() {
        unfunction npm
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
        npm "$@"
    }
fi

# =============================================================================
# Auto-switch Node.js Version
# =============================================================================

# Function to load .nvmrc if present
load-nvmrc() {
    [[ ! "${ENABLE_PROJECT_DETECTION:-true}" == "true" ]] && return
    # chpwd hooks fire in non-interactive shells too: without a terminal
    # this output would land in the standard output of a script or an agent.
    nivuus_has_terminal || return 0

    local nvmrc_path="$(nvm_find_nvmrc)"

    if [[ -n "$nvmrc_path" ]]; then
        local nvmrc_node_version=$(nvm version "$(cat "${nvmrc_path}")")

        if [[ "$nvmrc_node_version" == "N/A" ]]; then
            nvm install
        elif [[ "$nvmrc_node_version" != "$(nvm version)" ]]; then
            nvm use --silent
        fi
    elif [[ -n "$(PWD=$OLDPWD nvm_find_nvmrc)" ]] && [[ "$(nvm version)" != "$(nvm version default)" ]]; then
        echo "Reverting to default Node.js version"
        nvm use default --silent
    fi
}

# Helper function to find .nvmrc
nvm_find_nvmrc() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.nvmrc" ]]; then
            echo "$dir/.nvmrc"
            return
        fi
        dir="${dir:h}"
    done
}

# Add hook to auto-switch on directory change
if [[ -d "$HOME/.nvm" ]]; then
    autoload -U add-zsh-hook
    add-zsh-hook chpwd load-nvmrc
fi

# =============================================================================
# Project Detection
# =============================================================================

# Detect project type and suggest commands
detect-project() {
    [[ ! "${ENABLE_PROJECT_DETECTION:-true}" == "true" ]] && return

    local detected=false

    if [[ -f "package.json" ]]; then
        echo "📦 Node.js project detected"
        echo "   npm install     - Install dependencies"
        echo "   npm start       - Start application"
        echo "   npm test        - Run tests"
        detected=true
    fi

    if [[ -f "requirements.txt" ]] || [[ -f "setup.py" ]]; then
        echo "🐍 Python project detected"
        echo "   pip install -r requirements.txt"
        echo "   python main.py"
        detected=true
    fi

    if [[ -f "Cargo.toml" ]]; then
        echo "🦀 Rust project detected"
        echo "   cargo build     - Build project"
        echo "   cargo run       - Run project"
        echo "   cargo test      - Run tests"
        detected=true
    fi

    if [[ -f "go.mod" ]]; then
        echo "🐹 Go project detected"
        echo "   go mod download - Download dependencies"
        echo "   go run .        - Run project"
        echo "   go test ./...   - Run tests"
        detected=true
    fi
}

# Show project info when entering a directory with project files
_check_project_on_cd() {
    # chpwd hooks fire in non-interactive shells too: without a terminal
    # this output would land in the standard output of a script or an agent.
    nivuus_has_terminal || return 0
    if [[ -f "package.json" ]] || [[ -f "requirements.txt" ]] || [[ -f "Cargo.toml" ]] || [[ -f "go.mod" ]] || [[ -f ".nvmrc" ]]; then
        detect-project
    fi
}

# Add hook (only if enabled)
if [[ "${ENABLE_PROJECT_DETECTION:-true}" == "true" ]]; then
    autoload -U add-zsh-hook
    add-zsh-hook chpwd _check_project_on_cd
fi

# =============================================================================
# NVM Helper Commands
# =============================================================================

# Install NVM
nvm-install() {
    if [[ -d "$HOME/.nvm" ]]; then
        echo "✓ NVM already installed at ~/.nvm"
        return 0
    fi

    echo "Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    echo "✓ NVM installed. Restart your shell or run: source ~/.zshrc"
}

# Update NVM
nvm-update() {
    if [[ ! -d "$HOME/.nvm" ]]; then
        echo "✗ NVM not installed. Run: nvm-install"
        return 1
    fi

    cd "$HOME/.nvm" && git pull
    echo "✓ NVM updated. Restart your shell or run: source ~/.zshrc"
}

# Check NVM health
nvm-health() {
    echo "NVM Health Check"
    echo "════════════════"

    if [[ -d "$HOME/.nvm" ]]; then
        echo "✓ NVM installed"

        # Load NVM to check version
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

        echo "  Version: $(nvm --version 2>/dev/null || echo 'unknown')"
        echo "  Location: $NVM_DIR"

        if command -v node &>/dev/null; then
            echo "✓ Node.js: $(node --version)"
        else
            echo "⚠  Node.js not active (run 'nvm use' in project)"
        fi

        if command -v npm &>/dev/null; then
            echo "✓ npm: $(npm --version)"
        else
            echo "✗ npm not found"
        fi
    else
        echo "✗ NVM not installed"
        echo "  Run: nvm-install"
    fi
}
