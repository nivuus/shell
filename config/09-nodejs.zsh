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

# nvm is installed the way its README describes a manual install: a git
# clone of nvm-sh/nvm checked out at a release tag. No install script is
# piped into a shell (the lazy loader above sources nvm.sh itself, so nvm's
# profile edits are not needed). The tag is pinned together with the commit
# it must resolve to: a tag that was moved or rewritten is refused, never
# run. Bump both together, from `git ls-remote <repo> 'refs/tags/<tag>^{}'`.
: ${NIVUUS_NVM_REPO:=https://github.com/nvm-sh/nvm.git}
: ${NIVUUS_NVM_VERSION:=v0.41.0}
: ${NIVUUS_NVM_COMMIT:=4e8758a801eea9479b32a904f31093e410ddaba4}

# Check that the checkout in $1 is the pinned commit.
_nivuus_nvm_verify() {
    local head
    head=$(git -C "$1" rev-parse HEAD 2>/dev/null)
    if [[ "$head" != "$NIVUUS_NVM_COMMIT" ]]; then
        echo "✗ nvm $NIVUUS_NVM_VERSION resolves to ${head:-nothing}, expected $NIVUUS_NVM_COMMIT: refusing it" >&2
        return 1
    fi
}

# Install NVM
nvm-install() {
    if [[ -d "$HOME/.nvm" ]]; then
        echo "✓ NVM already installed at ~/.nvm"
        return 0
    fi
    if ! (( $+commands[git] )); then
        echo "✗ git is required to install NVM" >&2
        return 1
    fi

    echo "Installing NVM $NIVUUS_NVM_VERSION..."
    local staging
    staging=$(mktemp -d "$HOME/.nvm.install.XXXXXX") || return 1
    if ! git -c advice.detachedHead=false clone --quiet --depth 1 \
            --branch "$NIVUUS_NVM_VERSION" "$NIVUUS_NVM_REPO" "$staging" \
        || ! _nivuus_nvm_verify "$staging" \
        || ! mv -- "$staging" "$HOME/.nvm"; then
        rm -rf -- "$staging"
        echo "✗ NVM not installed" >&2
        return 1
    fi
    echo "✓ NVM $NIVUUS_NVM_VERSION installed. Restart your shell or run: source ~/.zshrc"
}

# Update NVM to the version pinned above
nvm-update() {
    if [[ ! -d "$HOME/.nvm" ]]; then
        echo "✗ NVM not installed. Run: nvm-install"
        return 1
    fi

    local nvm_dir="$HOME/.nvm"
    if ! git -C "$nvm_dir" fetch --quiet --depth 1 "$NIVUUS_NVM_REPO" \
            "+refs/tags/${NIVUUS_NVM_VERSION}:refs/tags/${NIVUUS_NVM_VERSION}"; then
        echo "✗ Could not fetch nvm $NIVUUS_NVM_VERSION" >&2
        return 1
    fi
    local tagged
    tagged=$(git -C "$nvm_dir" rev-parse "refs/tags/$NIVUUS_NVM_VERSION^{commit}" 2>/dev/null)
    if [[ "$tagged" != "$NIVUUS_NVM_COMMIT" ]]; then
        echo "✗ nvm $NIVUUS_NVM_VERSION resolves to ${tagged:-nothing}, expected $NIVUUS_NVM_COMMIT: refusing it" >&2
        return 1
    fi
    if ! git -C "$nvm_dir" -c advice.detachedHead=false checkout --quiet "$NIVUUS_NVM_COMMIT"; then
        echo "✗ Could not check out nvm $NIVUUS_NVM_VERSION" >&2
        return 1
    fi
    echo "✓ NVM at $NIVUUS_NVM_VERSION. Restart your shell or run: source ~/.zshrc"
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
