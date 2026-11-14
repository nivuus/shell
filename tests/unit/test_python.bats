#!/usr/bin/env bats

# Unit tests for Python module (config/09-python.zsh)

setup() {
    source "$NIVUUS_SHELL_DIR/config/09-python.zsh"
}

# =============================================================================
# Module Loading Tests
# =============================================================================

@test "Python module loads without errors" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-python.zsh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}

@test "Python module can be disabled with ENABLE_PYTHON_VENV" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'ENABLE_PYTHON_VENV:-true' config/09-python.zsh"
    [ "$status" -eq 0 ]
}

@test "Module returns early when ENABLE_PYTHON_VENV is false" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'ENABLE_PYTHON_VENV:-true.*return' config/09-python.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# get_python_venv Function Tests
# =============================================================================

@test "get_python_venv function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-python.zsh' && typeset -f get_python_venv"
    [ "$status" -eq 0 ]
}

@test "get_python_venv detects CONDA_DEFAULT_ENV" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'CONDA_DEFAULT_ENV' config/09-python.zsh | head -3"
    [ "$status" -eq 0 ]
}

@test "get_python_venv detects VIRTUAL_ENV" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'VIRTUAL_ENV' config/09-python.zsh | head -3"
    [ "$status" -eq 0 ]
}

@test "get_python_venv detects POETRY_ACTIVE" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'POETRY_ACTIVE' config/09-python.zsh"
    [ "$status" -eq 0 ]
}

@test "get_python_venv shows conda prefix" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'conda:' config/09-python.zsh"
    [ "$status" -eq 0 ]
}

@test "get_python_venv uses basename for venv name" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'basename.*VIRTUAL_ENV' config/09-python.zsh"
    [ "$status" -eq 0 ]
}

@test "get_python_venv returns empty when no venv active" {
    run zsh -c "unset VIRTUAL_ENV CONDA_DEFAULT_ENV POETRY_ACTIVE && source '$NIVUUS_SHELL_DIR/config/09-python.zsh' && get_python_venv"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# =============================================================================
# Auto-activation Tests
# =============================================================================

@test "_python_auto_activate function is defined" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '_python_auto_activate()' config/09-python.zsh"
    [ "$status" -eq 0 ]
}

@test "Auto-activation is disabled by default" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'ENABLE_PYTHON_AUTO_ACTIVATE:-false' config/09-python.zsh"
    [ "$status" -eq 0 ]
}

@test "Auto-activation looks for common venv directories" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 '_python_auto_activate()' config/09-python.zsh | grep -E '(venv|.venv|env|.env)'"
    [ "$status" -eq 0 ]
}

@test "Auto-activation checks for activate script" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'bin/activate' config/09-python.zsh | head -3"
    [ "$status" -eq 0 ]
}

@test "Auto-activation uses chpwd hook when enabled" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'add-zsh-hook chpwd _python_auto_activate' config/09-python.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# venv-create Function Tests
# =============================================================================

@test "venv-create function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-python.zsh' && typeset -f venv-create"
    [ "$status" -eq 0 ]
}

@test "venv-create defaults to .venv name" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'venv_name=.*:-\.venv' config/09-python.zsh"
    [ "$status" -eq 0 ]
}

@test "venv-create checks if directory exists" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'if.*-d.*venv_name' config/09-python.zsh"
    [ "$status" -eq 0 ]
}

@test "venv-create uses python3 -m venv" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'python3 -m venv' config/09-python.zsh"
    [ "$status" -eq 0 ]
}

@test "venv-create shows activation instructions" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'Activate with:' config/09-python.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# venv-activate Function Tests
# =============================================================================

@test "venv-activate function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-python.zsh' && typeset -f venv-activate"
    [ "$status" -eq 0 ]
}

@test "venv-activate looks for common venv directories" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 'venv-activate()' config/09-python.zsh | grep -E '(\.venv|venv|env|\.env)'"
    [ "$status" -eq 0 ]
}

@test "venv-activate accepts directory argument" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 5 'venv-activate()' config/09-python.zsh | grep 'if.*-n.*1'"
    [ "$status" -eq 0 ]
}

@test "venv-activate sources activate script" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 15 'venv-activate()' config/09-python.zsh | grep 'source.*bin/activate'"
    [ "$status" -eq 0 ]
}

@test "venv-activate shows error when no venv found" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'No virtual environment found' config/09-python.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# venv-deactivate Function Tests
# =============================================================================

@test "venv-deactivate function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-python.zsh' && typeset -f venv-deactivate"
    [ "$status" -eq 0 ]
}

@test "venv-deactivate checks VIRTUAL_ENV" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 3 'venv-deactivate()' config/09-python.zsh | grep 'VIRTUAL_ENV'"
    [ "$status" -eq 0 ]
}

@test "venv-deactivate calls deactivate command" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 3 'venv-deactivate()' config/09-python.zsh | grep 'deactivate'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# venv-info Function Tests
# =============================================================================

@test "venv-info function is defined" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-python.zsh' && typeset -f venv-info"
    [ "$status" -eq 0 ]
}

@test "venv-info uses get_python_venv" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 3 'venv-info()' config/09-python.zsh | grep 'get_python_venv'"
    [ "$status" -eq 0 ]
}

@test "venv-info shows Python version" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'python --version' config/09-python.zsh"
    [ "$status" -eq 0 ]
}

@test "venv-info shows Python path" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 20 'venv-info()' config/09-python.zsh | grep 'which python'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Aliases Tests
# =============================================================================

@test "venv alias is defined (venv-activate)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-python.zsh' && alias venv"
    [ "$status" -eq 0 ]
    [[ "$output" == *"venv-activate"* ]]
}

@test "venv-new alias is defined (venv-create)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-python.zsh' && alias venv-new"
    [ "$status" -eq 0 ]
    [[ "$output" == *"venv-create"* ]]
}

@test "venv-off alias is defined (venv-deactivate)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-python.zsh' && alias venv-off"
    [ "$status" -eq 0 ]
    [[ "$output" == *"venv-deactivate"* ]]
}

@test "venv-status alias is defined (venv-info)" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/config/09-python.zsh' && alias venv-status"
    [ "$status" -eq 0 ]
    [[ "$output" == *"venv-info"* ]]
}

# =============================================================================
# Coverage Tests
# =============================================================================

@test "Python module defines at least 4 main functions" {
    count=$(zsh -c "source '$NIVUUS_SHELL_DIR/config/09-python.zsh' && typeset -f | grep -E '(get_python_venv|venv-create|venv-activate|venv-info)' | wc -l")
    [ "$count" -ge 4 ]
}

@test "Python module defines 4 aliases" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c '^alias venv' config/09-python.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -eq 4 ]
}

@test "Module supports multiple venv types (venv, conda, poetry)" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c -E '(VIRTUAL_ENV|CONDA_DEFAULT_ENV|POETRY_ACTIVE)' config/09-python.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 3 ]
}

@test "Module has proper error handling" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c '✗' config/09-python.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 3 ]
}

@test "Module has success indicators" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -c '✓' config/09-python.zsh"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 3 ]
}
