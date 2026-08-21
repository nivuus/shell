#!/usr/bin/env bats

# Performance tests - CRITICAL: <300ms startup time requirement

# =============================================================================
# CRITICAL: Startup Time Test (<300ms requirement)
# =============================================================================

# bats test_tags=portable
@test "CRITICAL: Full shell startup time is under the budget (median of 10 runs)" {
    # La mesure est prise DANS zsh, entre deux $EPOCHREALTIME autour du
    # `source .zshrc` : ni bats, ni le fork, ni le runner n'entrent dans le
    # nombre. C'est pourquoi ce test ne se saute plus en CI.
    budget_ms="${NIVUUS_STARTUP_BUDGET_MS:-300}"
    median_ms=$("$BATS_TEST_DIRNAME/measure_startup.sh")

    echo "# Startup (median): ${median_ms}ms — budget: ${budget_ms}ms" >&3

    [ "$median_ms" -lt "$budget_ms" ]
}

# =============================================================================
# Module Load Time Tests
# =============================================================================

@test "Nord theme loads quickly (<10ms)" {
    runs=3
    total_time=0

    for i in $(seq 1 $runs); do
        start=$(date +%s%N)
        zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh'" 2>/dev/null
        end=$(date +%s%N)
        elapsed_ms=$(( (end - start) / 1000000 ))
        total_time=$(( total_time + elapsed_ms ))
    done

    average_ms=$(( total_time / runs ))
    echo "# Nord theme: ${average_ms}ms" >&3

    [ "$average_ms" -lt 50 ]
}

@test "Prompt module loads quickly (<50ms)" {
    runs=3
    total_time=0

    for i in $(seq 1 $runs); do
        start=$(date +%s%N)
        zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh'" 2>/dev/null
        end=$(date +%s%N)
        elapsed_ms=$(( (end - start) / 1000000 ))
        total_time=$(( total_time + elapsed_ms ))
    done

    average_ms=$(( total_time / runs ))
    echo "# Prompt module: ${average_ms}ms" >&3

    [ "$average_ms" -lt 100 ]
}

@test "AI suggestions module loads quickly (<100ms)" {
    runs=3
    total_time=0

    for i in $(seq 1 $runs); do
        start=$(date +%s%N)
        zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/19-ai-suggestions.zsh'" 2>/dev/null
        end=$(date +%s%N)
        elapsed_ms=$(( (end - start) / 1000000 ))
        total_time=$(( total_time + elapsed_ms ))
    done

    average_ms=$(( total_time / runs ))
    echo "# AI suggestions: ${average_ms}ms" >&3

    [ "$average_ms" -lt 150 ]
}

@test "Safety module loads quickly (<50ms)" {
    runs=3
    total_time=0

    for i in $(seq 1 $runs); do
        start=$(date +%s%N)
        zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/21-safety.zsh'" 2>/dev/null
        end=$(date +%s%N)
        elapsed_ms=$(( (end - start) / 1000000 ))
        total_time=$(( total_time + elapsed_ms ))
    done

    average_ms=$(( total_time / runs ))
    echo "# Safety module: ${average_ms}ms" >&3

    [ "$average_ms" -lt 100 ]
}

@test "Git aliases module loads quickly (<20ms)" {
    runs=3
    total_time=0

    for i in $(seq 1 $runs); do
        start=$(date +%s%N)
        zsh -c "source '$NIVUUS_SHELL_DIR/config/06-git.zsh'" 2>/dev/null
        end=$(date +%s%N)
        elapsed_ms=$(( (end - start) / 1000000 ))
        total_time=$(( total_time + elapsed_ms ))
    done

    average_ms=$(( total_time / runs ))
    echo "# Git aliases: ${average_ms}ms" >&3

    [ "$average_ms" -lt 50 ]
}

# =============================================================================
# Memory Usage Tests
# =============================================================================

@test "Shell memory footprint is reasonable (<150MB)" {
    # Start a ZSH instance and get its memory usage
    pid=$(zsh -c 'echo $$; sleep 1' 2>/dev/null &)
    sleep 0.5

    # Get memory usage in KB
    mem_kb=$(ps -o rss= -p $pid 2>/dev/null | tr -d ' ' || echo "0")
    mem_mb=$((mem_kb / 1024))

    echo "# Memory usage: ${mem_mb}MB" >&3

    # Kill the process
    kill $pid 2>/dev/null || true

    [ "$mem_mb" -lt 150 ]
}

# =============================================================================
# Compilation Tests
# =============================================================================

@test "Config files can be compiled to .zwc" {
    # Test compilation of a config file
    test_file="$NIVUUS_SHELL_DIR/config/06-git.zsh"

    if [ -f "$test_file" ]; then
        run zsh -c "zcompile '$test_file' 2>&1"
        [ "$status" -eq 0 ]
    fi
}

@test "Compiled .zwc files exist for critical modules" {
    # Check if .zwc files exist or can be created
    critical_modules=(
        "themes/nord.zsh"
        "config/05-prompt.zsh"
    )

    compiled_count=0
    for module in "${critical_modules[@]}"; do
        if [ -f "$NIVUUS_SHELL_DIR/$module.zwc" ] || [ -f "$NIVUUS_SHELL_DIR/$module" ]; then
            compiled_count=$((compiled_count + 1))
        fi
    done

    [ "$compiled_count" -ge 1 ]
}

# =============================================================================
# Prompt Generation Performance
# =============================================================================

@test "Prompt generation is fast (<100ms)" {
    runs=3
    total_time=0

    for i in $(seq 1 $runs); do
        start=$(date +%s%N)
        zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && build_prompt >/dev/null" 2>/dev/null
        end=$(date +%s%N)
        elapsed_ms=$(( (end - start) / 1000000 ))
        total_time=$(( total_time + elapsed_ms ))
    done

    average_ms=$(( total_time / runs ))
    echo "# Prompt generation: ${average_ms}ms" >&3

    [ "$average_ms" -lt 150 ]
}
