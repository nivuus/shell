#!/usr/bin/env zsh
# ============================================================================
# Nivuus Shell - Auto-Update System (Release-Based)
# ============================================================================
# Manages automatic updates from GitHub Releases
# - Weekly automatic update checks (configurable)
# - Automatic installation with backup
# - Manual update via 'nivuus-update' command
# - Checksum and build-provenance verification, atomic swap, one update at a
#   time: see config/20-autoupdate-release.zsh
# ============================================================================

# Configuration variables (can be overridden in .zsh_local)
: ${ENABLE_AUTOUPDATE:=true}
: ${AUTOUPDATE_CHECK_FREQUENCY_DAYS:=7}
: ${NIVUUS_GITHUB_REPO:=nivuus/shell}
: ${NIVUUS_GITHUB_API:=https://api.github.com}

# Last update check timestamp file
NIVUUS_UPDATE_CHECK_FILE="$HOME/.nivuus-shell-last-update-check"

# Version file to track installed version
NIVUUS_VERSION_FILE="$NIVUUS_SHELL_DIR/.version"

# Outcome of the last automatic update, read at the next terminal start: an
# update runs in the background, where nobody would see it fail.
NIVUUS_UPDATE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nivuus-shell"
NIVUUS_UPDATE_LOG="$NIVUUS_UPDATE_STATE_DIR/update.log"
NIVUUS_UPDATE_STATUS="$NIVUUS_UPDATE_STATE_DIR/update.status"

# Download, verification, staging and swap of a release.
source "${${(%):-%x}:A:h}/20-autoupdate-release.zsh"

# ============================================================================
# Helper Functions
# ============================================================================

# Detect a development checkout (git working copy).
# The release-based updater is destructive (it wipes $NIVUUS_SHELL_DIR),
# so it must NEVER run against a git checkout or it would delete .git and
# any uncommitted work.
_nivuus_is_dev_checkout() {
    [[ -d "$NIVUUS_SHELL_DIR/.git" ]] || [[ -f "$NIVUUS_SHELL_DIR/.git" ]]
}

# A system-wide install (see `nivuus install --system`) lives in a root-owned
# directory: a user shell can neither replace it nor should it try. Updating it
# is `sudo nivuus install --system` from a fresh checkout. The update swaps
# the whole directory, so its parent must be writable as well.
_nivuus_install_writable() {
    [[ -w "$NIVUUS_SHELL_DIR" && -w "${NIVUUS_SHELL_DIR:h}" ]]
}

# Get current installed version
_nivuus_current_version() {
    if [[ -f "$NIVUUS_VERSION_FILE" ]]; then
        cat "$NIVUUS_VERSION_FILE" 2>/dev/null
    elif [[ -f "$NIVUUS_SHELL_DIR/package.json" ]]; then
        # Fallback to package.json
        grep '"version"' "$NIVUUS_SHELL_DIR/package.json" | sed 's/.*"version": "\(.*\)".*/\1/'
    else
        echo "unknown"
    fi
}

# Get latest release version from GitHub
_nivuus_latest_version() {
    local response=$(curl -fsSL \
        -H "Accept: application/vnd.github.v3+json" \
        "$NIVUUS_GITHUB_API/repos/$NIVUUS_GITHUB_REPO/releases/latest" 2>/dev/null)

    [[ $? -eq 0 && -n "$response" ]] || return 1
    local version
    version=$(print -r -- "$response" | grep '"tag_name"' | sed 's/.*"tag_name": "v\?\(.*\)".*/\1/')
    # The tag ends up in URLs and paths: only a plain X.Y.Z is accepted.
    _nivuus_valid_version "$version" || return 1
    print -r -- "$version"
}

# Compare versions (returns 0 if v2 > v1, 1 otherwise)
_nivuus_version_greater() {
    local v1=$1
    local v2=$2

    # Remove 'v' prefix if present
    v1=${v1#v}
    v2=${v2#v}

    # Handle "unknown" version
    [[ "$v1" == "unknown" ]] && return 0

    # Split versions into arrays
    local -a v1_parts=(${(s:.:)v1})
    local -a v2_parts=(${(s:.:)v2})

    # Compare each part
    for i in {1..3}; do
        local p1=${v1_parts[$i]:-0}
        local p2=${v2_parts[$i]:-0}

        # Strip any pre-release/build suffix (e.g. "1-rc2" -> "1") and
        # fall back to 0 for non-numeric parts so (( )) never errors.
        p1=${p1%%[-+]*}; [[ "$p1" == <-> ]] || p1=0
        p2=${p2%%[-+]*}; [[ "$p2" == <-> ]] || p2=0

        if (( p2 > p1 )); then
            return 0
        elif (( p1 > p2 )); then
            return 1
        fi
    done

    # Versions are equal
    return 1
}

# Check if update is available
_nivuus_update_available() {
    local current=$(_nivuus_current_version)
    local latest=$(_nivuus_latest_version)

    [[ -n "$latest" ]] && _nivuus_version_greater "$current" "$latest"
}

# Get days since last check
_nivuus_days_since_check() {
    if [[ ! -f "$NIVUUS_UPDATE_CHECK_FILE" ]]; then
        echo 999
        return
    fi

    local last_check=$(cat "$NIVUUS_UPDATE_CHECK_FILE" 2>/dev/null || echo 0)
    local now=$(date +%s)
    local diff=$((now - last_check))
    echo $((diff / 86400))
}

# Update the last check timestamp
_nivuus_update_check_timestamp() {
    date +%s > "$NIVUUS_UPDATE_CHECK_FILE"
}

# Clean up old backups (keep only last 5)
_nivuus_cleanup_old_backups() {
    local backup_base="$HOME/.config/nivuus-shell-backup"

    # Check if backup directory exists
    [[ ! -d "$backup_base" ]] && return

    # Newest first: the names carry a YYYYMMDD-HHMMSS stamp, so descending
    # name order (the On qualifier) is newest first. A bare glob sorts
    # ascending, which put the OLDEST first and pruned the newest backups,
    # the one just made included.
    local backups=("$backup_base"/pre-update-*(NOn))

    # If we have more than 5 backups, remove the oldest ones
    if (( ${#backups[@]} > 5 )); then
        local old_backup
        for old_backup in "${(@)backups[6,-1]}"; do
            rm -rf "$old_backup" || echo "⚠️  Could not remove old backup $old_backup" >&2
        done
    fi
}

# Create backup before update
_nivuus_create_update_backup() {
    local backup_dir="$HOME/.config/nivuus-shell-backup/pre-update-$(date +%Y%m%d-%H%M%S)"

    # An update without a complete backup could not be undone: any failure
    # here fails the backup, and the caller does not update.
    mkdir -p "$backup_dir" || return 1

    # Backup entire installation directory
    if [[ -d "$NIVUUS_SHELL_DIR" ]]; then
        cp -r "$NIVUUS_SHELL_DIR" "$backup_dir/nivuus-shell" || return 1
    fi

    # Backup user files
    if [[ -f "$HOME/.zshrc" ]]; then cp "$HOME/.zshrc" "$backup_dir/.zshrc" || return 1; fi
    if [[ -f "$HOME/.zsh_local" ]]; then cp "$HOME/.zsh_local" "$backup_dir/.zsh_local" || return 1; fi

    # Clean up old backups after creating new one
    _nivuus_cleanup_old_backups

    echo "$backup_dir"
}

# Perform the update to <version>. The caller holds the update lock.
_nivuus_perform_update() {
    local target_version=$1

    if [[ -z "$target_version" ]]; then
        echo "❌ Could not determine target version"
        return 1
    fi

    # Under the lock, re-read the installed version: another shell may have
    # installed this release while this one waited for its turn.
    if ! _nivuus_version_greater "$(_nivuus_current_version)" "$target_version"; then
        echo "✅ v$(_nivuus_current_version) is already installed"
        return 0
    fi

    local backup_dir
    if ! backup_dir=$(_nivuus_create_update_backup); then
        echo "❌ Could not back up the current installation, update aborted"
        return 1
    fi
    echo "📦 Backup created: $backup_dir"

    if ! _nivuus_install_release "$target_version"; then
        echo "❌ Update to v${target_version} failed; v$(_nivuus_current_version) is still installed"
        return 1
    fi
    echo "♻️  Restart your shell to apply changes: exec zsh"
}

# Record the outcome of an update for the next terminal start.
_nivuus_record_update_status() {
    mkdir -p "$NIVUUS_UPDATE_STATE_DIR" || return 1
    print -r -- "$1 $2" > "$NIVUUS_UPDATE_STATUS"
}

# Unattended update: check, and install if a newer release exists. Exactly one
# shell does this at a time; the others leave at once.
_nivuus_auto_update() {
    _nivuus_update_lock || return 0
    _nivuus_update_check_timestamp

    local latest
    latest=$(_nivuus_latest_version) || return 0   # offline: try next period
    _nivuus_version_greater "$(_nivuus_current_version)" "$latest" || return 0

    mkdir -p "$NIVUUS_UPDATE_STATE_DIR" || return 1
    if _nivuus_perform_update "$latest" > "$NIVUUS_UPDATE_LOG" 2>&1; then
        _nivuus_record_update_status ok "$latest"
    else
        _nivuus_record_update_status failed "$latest"
    fi
}

# Background update check (async, no performance impact)
_nivuus_check_update_async() {
    ( _nivuus_auto_update ) &!
}

# Say so when the last unattended update failed, until an update succeeds.
_nivuus_report_failed_update() {
    [[ -r "$NIVUUS_UPDATE_STATUS" ]] || return 0
    local -a outcome
    outcome=(${=$(<"$NIVUUS_UPDATE_STATUS")})
    [[ "${outcome[1]}" == failed ]] || return 0
    # Installed since by other means (or by hand): nothing left to report.
    _nivuus_version_greater "$(_nivuus_current_version)" "${outcome[2]}" || return 0
    print -u2 -r -- "⚠️  Nivuus Shell: the automatic update to v${outcome[2]} failed; v$(_nivuus_current_version) is still installed."
    print -u2 -r -- "   Details: $NIVUUS_UPDATE_LOG — retry with: nivuus-update"
}

# ============================================================================
# Main Auto-Update Logic
# ============================================================================

# Only run if enabled — and never against a git checkout (dev mode), where a
# destructive release install would delete .git and any uncommitted work.
#
# Terminal only as well: the check spends a GitHub round-trip and reports to
# someone, and a self-replacing install is not something to start underneath a
# script or an agent that is mid-task.
if [[ -r "$NIVUUS_UPDATE_STATUS" ]] && nivuus_has_terminal && ! _nivuus_is_dev_checkout; then
    _nivuus_report_failed_update
fi

if [[ "$ENABLE_AUTOUPDATE" == "true" ]] && nivuus_has_terminal && ! _nivuus_is_dev_checkout && _nivuus_install_writable; then
    # Check if it's time for an update check
    days_since_check=$(_nivuus_days_since_check)

    if (( days_since_check >= AUTOUPDATE_CHECK_FREQUENCY_DAYS )); then
        _nivuus_check_update_async
    fi
    unset days_since_check
elif [[ "$ENABLE_AUTOUPDATE" == "true" ]] && nivuus_has_terminal && _nivuus_is_dev_checkout; then
    # Say why nothing updates, once per check period, instead of skipping
    # silently: an older install made with `git clone` is such a checkout.
    days_since_check=$(_nivuus_days_since_check)
    if (( days_since_check >= AUTOUPDATE_CHECK_FREQUENCY_DAYS )); then
        print -u2 -r -- "ℹ️  Nivuus Shell: $NIVUUS_SHELL_DIR is a development checkout, release auto-update skipped (use git pull)."
        _nivuus_update_check_timestamp
    fi
    unset days_since_check
fi

# ============================================================================
# Manual Update Command
# ============================================================================

nivuus-update() {
    # Never run the destructive release updater on a git checkout.
    if _nivuus_is_dev_checkout; then
        echo "ℹ️  Development checkout detected at $NIVUUS_SHELL_DIR"
        echo "   Use 'git pull' here instead of the release updater."
        return 0
    fi
    if ! _nivuus_install_writable; then
        echo "ℹ️  System-wide install at $NIVUUS_SHELL_DIR (not writable by $USER)"
        echo "   Update it for everyone with:"
        echo "   git clone https://github.com/nivuus/shell.git /tmp/nivuus-shell && sudo /tmp/nivuus-shell/install.sh --system --non-interactive && rm -rf /tmp/nivuus-shell"
        return 0
    fi

    echo "🔍 Checking for updates..."

    # Update check timestamp
    _nivuus_update_check_timestamp

    # Check versions
    local current=$(_nivuus_current_version)
    local latest=$(_nivuus_latest_version)

    if [[ -z "$latest" ]]; then
        echo "❌ Could not fetch latest version from GitHub"
        echo "   Please check your internet connection"
        return 1
    fi

    echo "📍 Current version: v${current}"
    echo "📍 Latest version:  v${latest}"

    if _nivuus_version_greater "$current" "$latest"; then
        echo ""
        echo "🆕 Update available!"
        echo ""
        if ! _nivuus_update_lock; then
            echo "⏳ Another update of $NIVUUS_SHELL_DIR is already running; try again when it has finished"
            return 1
        fi
        local -i rc=0
        _nivuus_perform_update "$latest" || rc=$?
        _nivuus_update_unlock
        if (( rc == 0 )); then
            _nivuus_record_update_status ok "$latest"
        else
            _nivuus_record_update_status failed "$latest"
        fi
        return rc
    else
        echo ""
        echo "✅ Already up to date!"
    fi
}

# Command to check current version
nivuus-version() {
    local version=$(_nivuus_current_version)
    echo "Nivuus Shell v${version}"

    if [[ "$1" == "--check" ]] || [[ "$1" == "-c" ]]; then
        local latest=$(_nivuus_latest_version)
        if [[ -n "$latest" ]]; then
            echo "Latest release: v${latest}"

            if _nivuus_update_available; then
                echo "⚠️  Update available! Run 'nivuus-update' to upgrade"
            else
                echo "✅ You're running the latest version"
            fi
        fi
    fi
}
