#!/usr/bin/env zsh
# =============================================================================
# System Monitoring
# =============================================================================
# Lightweight system health and maintenance tools
# =============================================================================

# =============================================================================
# System Information
# =============================================================================

# Show ZSH info
zsh_info() {
    cat <<EOF
Nivuus Shell Information
════════════════════════

Version:        1.0.0
Install dir:    $NIVUUS_SHELL_DIR
ZSH version:    $ZSH_VERSION
Shell:          $SHELL

Features:
  Syntax highlighting:   ${ENABLE_SYNTAX_HIGHLIGHTING:-false}
  Project detection:     ${ENABLE_PROJECT_DETECTION:-true}
  Firebase prompt:       ${ENABLE_FIREBASE_PROMPT:-true}
  Git cache TTL:         ${GIT_PROMPT_CACHE_TTL:-2}s

Load time:      ${NIVUUS_LOAD_TIME:-unknown}ms
Target:         <300ms

Files loaded:
EOF
    ls -1 "$NIVUUS_SHELL_DIR/config" | sed 's/^/  /'
}

# =============================================================================
# Health Check
# =============================================================================

# System health check (calls bin/healthcheck if available)
healthcheck() {
    if [[ -x "$NIVUUS_SHELL_DIR/bin/healthcheck" ]]; then
        "$NIVUUS_SHELL_DIR/bin/healthcheck"
    else
        # Inline simple health check
        echo "System Health Check"
        echo "═══════════════════"

        echo ""
        echo "Disk Usage:"
        df -h / | tail -1

        echo ""
        echo "Memory:"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            top -l 1 | grep PhysMem
        else
            free -h | grep Mem
        fi

        echo ""
        echo "Uptime:"
        uptime

        echo ""
        echo "ZSH:"
        echo "  Version: $ZSH_VERSION"
        echo "  Load time: ${NIVUUS_LOAD_TIME:-unknown}ms"

        echo ""
        echo "✓ Health check complete"
    fi
}

# =============================================================================
# Benchmark
# =============================================================================

# Performance benchmark (calls bin/benchmark if available)
benchmark() {
    if [[ -x "$NIVUUS_SHELL_DIR/bin/benchmark" ]]; then
        "$NIVUUS_SHELL_DIR/bin/benchmark"
    else
        # Inline simple benchmark
        echo "Performance Benchmark"
        echo "═══════════════════════"

        echo ""
        echo "Testing shell reload..."

        local start=$EPOCHREALTIME
        source "$HOME/.zshrc"
        local end=$EPOCHREALTIME
        local duration=$(( ($end - $start) * 1000 ))

        echo "Load time: ${duration}ms"

        if (( duration < 300 )); then
            echo "✓ Excellent (<300ms)"
        elif (( duration < 500 )); then
            echo "✓ Good (<500ms)"
        else
            echo "⚠  Slow (>500ms) - consider disabling features"
        fi
    fi
}

# =============================================================================
# Cleanup
# =============================================================================

# Rewrite $HISTFILE without duplicate entries; on failure REPLY says why.
# The read and the write each take zsh's history lock, but not as one
# transaction: a line another shell appends in the moment between the two is
# lost.
_nivuus_dedup_history() {
    # Outside an interactive shell zsh keeps no history list to rewrite.
    if [[ ! -o interactive ]]; then
        REPLY="history can only be rewritten from an interactive shell"
        return 1
    fi
    setopt localoptions extended_history hist_ignore_all_dups hist_save_no_dups
    local file=$HISTFILE
    local -i size=$(( ${HISTSIZE:-0} > ${SAVEHIST:-0} ? ${HISTSIZE:-0} : ${SAVEHIST:-0} ))
    # The list holds at most this many entries, and the file is rewritten
    # from the list: zero would empty it.
    if (( size <= 0 )); then
        REPLY="HISTSIZE and SAVEHIST are not set"
        return 1
    fi
    # fc -p: a fresh list read from the file, popped afterwards; the
    # session's own list is left alone.
    fc -p "$file" $size $size || { REPLY="could not read $file"; return 1; }
    if ! fc -W "$file"; then
        fc -P
        REPLY="could not write $file"
        return 1
    fi
    fc -P
}

# Clean temporary files and caches
cleanup() {
    echo "Cleaning up..."

    # ZSH cache
    if [[ -d "$HOME/.cache/zsh" ]]; then
        rm -rf "$HOME/.cache/zsh"/*
        echo "✓ Cleaned ZSH cache"
    fi

    # Completion dump
    if [[ -f "$HOME/.zcompdump" ]]; then
        rm -f "$HOME/.zcompdump"*
        echo "✓ Removed completion dumps"
    fi

    # History deduplication, by zsh itself. The file is not a list of lines:
    # with EXTENDED_HISTORY each entry carries its timestamp, a multi-line
    # command spans several lines, and non-ASCII text is stored metafied, so
    # only zsh can tell two entries apart. Read it into a separate history
    # list where HIST_IGNORE_ALL_DUPS / HIST_SAVE_NO_DUPS mark and drop each
    # older duplicate, and write it back with zsh's own writer and lock.
    if [[ -n "$HISTFILE" && -f "$HISTFILE" ]]; then
        if _nivuus_dedup_history; then
            echo "✓ Deduplicated history"
        else
            echo "✗ History left as is: $REPLY" >&2
        fi
    fi

    # Nivuus cache
    if [[ -d "$HOME/.cache/nivuus-shell" ]]; then
        rm -rf "$HOME/.cache/nivuus-shell"/*
        echo "✓ Cleaned Nivuus cache"
    fi

    echo "✓ Cleanup complete"
}

# =============================================================================
# System Update
# =============================================================================

# Update system packages
update_system() {
    echo "Updating system..."

    # Detect package manager
    if command -v apt-get &>/dev/null; then
        # Debian/Ubuntu
        sudo apt-get update && sudo apt-get upgrade -y
    elif command -v yum &>/dev/null; then
        # RHEL/CentOS
        sudo yum update -y
    elif command -v dnf &>/dev/null; then
        # Fedora
        sudo dnf update -y
    elif command -v brew &>/dev/null; then
        # macOS
        brew update && brew upgrade
    elif command -v pacman &>/dev/null; then
        # Arch Linux
        sudo pacman -Syu
    else
        echo "✗ No supported package manager found"
        return 1
    fi

    echo ""
    echo "✓ System updated"
}

# =============================================================================
# Configuration Management
# =============================================================================

# Edit configuration
config_edit() {
    local config_type="${1:-main}"

    case "$config_type" in
        main)
            $EDITOR "$HOME/.zshrc"
            ;;
        local)
            $EDITOR "$HOME/.zsh_local"
            ;;
        functions)
            $EDITOR "$NIVUUS_SHELL_DIR/config/14-functions.zsh"
            ;;
        aliases)
            $EDITOR "$NIVUUS_SHELL_DIR/config/15-aliases.zsh"
            ;;
        *)
            echo "Usage: config_edit [main|local|functions|aliases]"
            return 1
            ;;
    esac
}

# Backup configuration
config_backup() {
    local backup_dir="$HOME/.config/nivuus-shell-backup"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_path="$backup_dir/backup-$timestamp"

    mkdir -p "$backup_path"

    # Backup main files
    [[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$backup_path/"
    [[ -f "$HOME/.zsh_local" ]] && cp "$HOME/.zsh_local" "$backup_path/"
    [[ -f "$HOME/.zsh_history" ]] && cp "$HOME/.zsh_history" "$backup_path/"

    # Backup Nivuus directory
    if [[ -d "$NIVUUS_SHELL_DIR" ]]; then
        cp -r "$NIVUUS_SHELL_DIR" "$backup_path/nivuus-shell"
    fi

    echo "✓ Configuration backed up to: $backup_path"
}

# Restore configuration
config_restore() {
    local backup_dir="$HOME/.config/nivuus-shell-backup"

    if [[ ! -d "$backup_dir" ]]; then
        echo "✗ No backups found"
        return 1
    fi

    echo "Available backups:"
    ls -1t "$backup_dir"

    echo ""
    echo "To restore, manually copy from: $backup_dir/<backup-name>/"
}

# =============================================================================
# Auto-Maintenance (Weekly)
# =============================================================================

# Run auto-maintenance if needed (once per week)
_auto_maintenance() {
    local maintenance_file="$HOME/.cache/nivuus-shell/last-maintenance"
    local current_week=$(date +%Y%W)

    if [[ ! -f "$maintenance_file" ]] || [[ "$(cat "$maintenance_file" 2>/dev/null)" != "$current_week" ]]; then
        mkdir -p "$(dirname "$maintenance_file")"
        echo "$current_week" > "$maintenance_file"

        # Run cleanup silently in background
        (cleanup &>/dev/null &)
    fi
}

# Run auto-maintenance check (async, non-blocking)
(_auto_maintenance &)
