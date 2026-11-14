#!/usr/bin/env zsh
# =============================================================================
# Python Virtual Environment Detection & Management
# =============================================================================
# Detects and displays active Python virtual environments
# Supports: venv, virtualenv, conda, poetry
# =============================================================================

# Skip if explicitly disabled
[[ "${ENABLE_PYTHON_VENV:-true}" != "true" ]] && return

# =============================================================================
# Virtual Environment Detection
# =============================================================================

# Get active virtual environment name
get_python_venv() {
    local venv_name=""

    # Check for Conda environment
    if [[ -n "$CONDA_DEFAULT_ENV" ]]; then
        # Don't show 'base' unless explicitly activated
        if [[ "$CONDA_DEFAULT_ENV" != "base" ]] || [[ -n "$CONDA_PREFIX" ]]; then
            venv_name="conda:$CONDA_DEFAULT_ENV"
        fi
    # Check for standard virtual environment (venv/virtualenv)
    elif [[ -n "$VIRTUAL_ENV" ]]; then
        # Get just the directory name, not full path
        venv_name=$(basename "$VIRTUAL_ENV")
    # Check for Poetry environment
    elif [[ -n "$POETRY_ACTIVE" ]]; then
        venv_name="poetry"
    fi

    echo "$venv_name"
}

# =============================================================================
# Auto-activation (Optional)
# =============================================================================

# Auto-activate venv when entering directory with venv/
_python_auto_activate() {
    [[ "${ENABLE_PYTHON_AUTO_ACTIVATE:-false}" != "true" ]] && return
    # chpwd hooks fire in non-interactive shells too: without a terminal
    # this output would land in the standard output of a script or an agent.
    nivuus_has_terminal || return 0

    # Look for common venv directories
    local venv_dirs=("venv" ".venv" "env" ".env")

    for dir in $venv_dirs; do
        if [[ -f "$PWD/$dir/bin/activate" ]]; then
            # Only activate if not already in a venv
            if [[ -z "$VIRTUAL_ENV" ]]; then
                source "$PWD/$dir/bin/activate"
                echo "✓ Activated Python venv: $dir"
            fi
            return
        fi
    done
}

# Hook into directory change (optional)
if [[ "${ENABLE_PYTHON_AUTO_ACTIVATE:-false}" == "true" ]]; then
    autoload -U add-zsh-hook
    add-zsh-hook chpwd _python_auto_activate
fi

# =============================================================================
# Utility Functions
# =============================================================================

# Create and activate a new virtual environment
venv-create() {
    local venv_name="${1:-.venv}"

    if [[ -d "$venv_name" ]]; then
        echo "⚠️  Virtual environment '$venv_name' already exists"
        return 1
    fi

    echo "Creating virtual environment: $venv_name"
    python3 -m venv "$venv_name"

    if [[ $? -eq 0 ]]; then
        echo "✓ Created successfully"
        echo "Activate with: source $venv_name/bin/activate"
    else
        echo "✗ Failed to create virtual environment"
        return 1
    fi
}

# Quick venv activation
venv-activate() {
    local venv_dirs=(".venv" "venv" "env" ".env")

    # If argument provided, use it
    if [[ -n "$1" ]]; then
        if [[ -f "$1/bin/activate" ]]; then
            source "$1/bin/activate"
            return
        else
            echo "✗ No activate script found in $1"
            return 1
        fi
    fi

    # Auto-detect common venv directories
    for dir in $venv_dirs; do
        if [[ -f "$dir/bin/activate" ]]; then
            source "$dir/bin/activate"
            echo "✓ Activated: $dir"
            return
        fi
    done

    echo "✗ No virtual environment found"
    echo "Looked for: ${(j:, :)venv_dirs}"
    return 1
}

# Deactivate current venv
venv-deactivate() {
    if [[ -n "$VIRTUAL_ENV" ]]; then
        deactivate
        echo "✓ Deactivated virtual environment"
    else
        echo "No active virtual environment"
    fi
}

# Show venv info
venv-info() {
    local venv=$(get_python_venv)

    if [[ -z "$venv" ]]; then
        echo "No active virtual environment"
        return
    fi

    echo "Active environment: $venv"

    if [[ -n "$VIRTUAL_ENV" ]]; then
        echo "Path: $VIRTUAL_ENV"
        echo "Python: $(which python)"
        echo "Version: $(python --version)"
    elif [[ -n "$CONDA_DEFAULT_ENV" ]]; then
        echo "Conda env: $CONDA_DEFAULT_ENV"
        echo "Python: $(which python)"
        echo "Version: $(python --version)"
    fi
}

# =============================================================================
# Aliases
# =============================================================================

alias venv='venv-activate'
alias venv-new='venv-create'
alias venv-off='venv-deactivate'
alias venv-status='venv-info'
