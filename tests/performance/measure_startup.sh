#!/usr/bin/env bash
# Measure shell startup time simply and accurately.
#
# La mesure est prise DANS zsh, entre deux lectures de $EPOCHREALTIME qui
# encadrent le `source .zshrc` : ni bats, ni le fork de zsh, ni le runner
# n'entrent dans le nombre. C'est pourquoi ce chiffre est utilisable en CI.
#
# On imprime la MÉDIANE et non la moyenne : sur un runner partagé, une seule
# mesure aberrante due à un voisin bruyant ruine une moyenne, pas une médiane.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NIVUUS_SHELL_DIR="${NIVUUS_SHELL_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

runs="${NIVUUS_STARTUP_RUNS:-10}"
samples=""

for i in $(seq 1 "$runs"); do
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

    samples="$samples$result
"
done

# `sort -n` suffit : aucune option GNU-only ici.
median_us=$(printf '%s' "$samples" | grep -v '^$' | sort -n | awk '
    { v[NR] = $1 }
    END { print (NR % 2) ? v[(NR + 1) / 2] : int((v[NR / 2] + v[NR / 2 + 1]) / 2) }')

echo "$((median_us / 1000))"
