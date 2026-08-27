#!/usr/bin/env bash
# Measure shell startup time simply and accurately

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NIVUUS_SHELL_DIR="${NIVUUS_SHELL_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

runs=10
total_ns=0

# shellcheck disable=SC2034 # loop counter used only to repeat, not read
for i in $(seq 1 $runs); do
    # Create temp script that measures its own load time
    temp=$(mktemp)
    cat > "$temp" <<'SCRIPT'
#!/usr/bin/env zsh
zmodload zsh/datetime 2>/dev/null || true
start=$EPOCHREALTIME
[[ -n "$NIVUUS_SHELL_DIR" ]] && source "$NIVUUS_SHELL_DIR/.zshrc" >/dev/null 2>&1
end=$EPOCHREALTIME
# Output in microseconds (multiply by 1000000)
printf "%.0f" $(( (end - start) * 1000000 ))
SCRIPT

    # Run and measure (suppress all output except the final number)
    result=$(NIVUUS_SHELL_DIR="$NIVUUS_SHELL_DIR" NIVUUS_NO_COMPILE=1 zsh "$temp" 2>&1 | tail -1 | grep -o '[0-9]*' || echo "0")
    rm -f "$temp"

    # Add to total (result is in microseconds)
    total_ns=$((total_ns + result))
done

# Calculate average and convert to milliseconds
average_us=$((total_ns / runs))
average_ms=$((average_us / 1000))

echo "$average_ms"
