#!/usr/bin/env zsh
# =============================================================================
# Test Assertions - Custom helpers for Nivuus Shell tests
# =============================================================================

# Assert execution time is under threshold (in milliseconds)
# Usage: assert_performance 300 "command to test"
assert_performance() {
    local threshold_ms=$1
    local command=$2

    local start=$(date +%s%N)
    eval "$command" >/dev/null 2>&1
    local end=$(date +%s%N)

    local duration_ms=$(( (end - start) / 1000000 ))

    if (( duration_ms > threshold_ms )); then
        echo "FAIL: Performance test failed"
        echo "  Expected: < ${threshold_ms}ms"
        echo "  Got: ${duration_ms}ms"
        return 1
    fi
    return 0
}

# Assert string contains Nord color code
# Usage: assert_color "$output" 110  # cyan
assert_color() {
    local output=$1
    local color_code=$2

    if [[ "$output" =~ "38;5;${color_code}" ]] || [[ "$output" =~ "%F{${color_code}}" ]]; then
        return 0
    fi

    echo "FAIL: Color assertion failed"
    echo "  Expected color code: $color_code"
    echo "  Output: $output"
    return 1
}

# Assert function uses caching (second call faster than first)
# Usage: assert_cached "function_name arg1 arg2"
assert_cached() {
    local command=$1

    # First call (cache miss)
    local start1=$(date +%s%N)
    eval "$command" >/dev/null 2>&1
    local end1=$(date +%s%N)
    local duration1=$(( (end1 - start1) / 1000000 ))

    # Second call (cache hit)
    local start2=$(date +%s%N)
    eval "$command" >/dev/null 2>&1
    local end2=$(date +%s%N)
    local duration2=$(( (end2 - start2) / 1000000 ))

    if (( duration2 >= duration1 )); then
        echo "FAIL: Cache assertion failed"
        echo "  First call: ${duration1}ms"
        echo "  Second call: ${duration2}ms (should be faster)"
        return 1
    fi
    return 0
}

# Assert file has been compiled to .zwc
# Usage: assert_file_compiled "config/05-prompt.zsh"
assert_file_compiled() {
    local file=$1
    local zwc_file="${file}.zwc"

    if [[ ! -f "$zwc_file" ]]; then
        echo "FAIL: Compilation assertion failed"
        echo "  Expected: $zwc_file"
        echo "  File not found"
        return 1
    fi

    # Check if .zwc is newer than .zsh
    if [[ "$file" -nt "$zwc_file" ]]; then
        echo "FAIL: Compilation assertion failed"
        echo "  $zwc_file is older than $file"
        return 1
    fi

    return 0
}

# Assert environment variable is set
# Usage: assert_env_set "THEME_PATH"
assert_env_set() {
    local var_name=$1

    if [[ -z "${(P)var_name}" ]]; then
        echo "FAIL: Environment variable not set: $var_name"
        return 1
    fi
    return 0
}

# Assert function exists
# Usage: assert_function_exists "git_prompt_info"
assert_function_exists() {
    local func_name=$1

    if ! typeset -f "$func_name" >/dev/null; then
        echo "FAIL: Function does not exist: $func_name"
        return 1
    fi
    return 0
}

# Assert alias exists
# Usage: assert_alias_exists "gs"
assert_alias_exists() {
    local alias_name=$1

    if ! alias "$alias_name" >/dev/null 2>&1; then
        echo "FAIL: Alias does not exist: $alias_name"
        return 1
    fi
    return 0
}

# Assert string matches regex pattern
# Usage: assert_matches "$output" "^error:"
assert_matches() {
    local string=$1
    local pattern=$2

    if [[ ! "$string" =~ $pattern ]]; then
        echo "FAIL: Pattern match failed"
        echo "  String: $string"
        echo "  Pattern: $pattern"
        return 1
    fi
    return 0
}

# Assert file contains string
# Usage: assert_file_contains ".zshrc" "source ~/.nivuus-shell"
assert_file_contains() {
    local file=$1
    local search=$2

    if ! grep -q "$search" "$file" 2>/dev/null; then
        echo "FAIL: File does not contain string"
        echo "  File: $file"
        echo "  Search: $search"
        return 1
    fi
    return 0
}

# Assert command succeeds
# Usage: assert_success "ls /tmp"
assert_success() {
    local command=$1

    if ! eval "$command" >/dev/null 2>&1; then
        echo "FAIL: Command failed: $command"
        return 1
    fi
    return 0
}

# Assert command fails
# Usage: assert_failure "ls /nonexistent"
assert_failure() {
    local command=$1

    if eval "$command" >/dev/null 2>&1; then
        echo "FAIL: Command succeeded (expected failure): $command"
        return 1
    fi
    return 0
}

# Assert startup time under 300ms (CRITICAL)
# Usage: assert_startup_time
assert_startup_time() {
    local max_ms=300
    local runs=10
    local total=0

    for i in {1..$runs}; do
        local start=$(date +%s%N)
        NIVUUS_SHELL_DIR="$(pwd)" zsh -i -c exit 2>/dev/null
        local end=$(date +%s%N)
        local duration=$(( (end - start) / 1000000 ))
        total=$((total + duration))
    done

    local average=$((total / runs))

    if (( average > max_ms )); then
        echo "FAIL: Startup time exceeds 300ms limit"
        echo "  Average: ${average}ms (${runs} runs)"
        echo "  Maximum allowed: ${max_ms}ms"
        return 1
    fi

    echo "✓ Startup time: ${average}ms (${runs} runs average)"
    return 0
}
