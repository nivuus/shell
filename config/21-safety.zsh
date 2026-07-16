#!/usr/bin/env zsh
# =============================================================================
# Command Safety Checks
# =============================================================================
# Warns before executing dangerous commands
# Helps prevent accidental data loss or system damage
# =============================================================================

# Skip if explicitly disabled
[[ "${ENABLE_SAFETY_CHECKS:-true}" != "true" ]] && return

# =============================================================================
# Dangerous Command Patterns
# =============================================================================

# Critical patterns that should always warn.
# Keys are POSIX ERE (matched with [[ =~ ]]) and are anchored on path
# boundaries so that, e.g., "rm -rf /home/project" does NOT match "rm -rf /".
# The recursive-flag fragment [-][a-z]*[rf][a-z]* matches -r, -f, -rf, -fr, ...
typeset -gA DANGEROUS_PATTERNS=(
    # Recursive deletion of a critical top-level target
    'rm[[:space:]]+-[a-z]*[rf][a-z]*[[:space:]]+(/\*|/|~/|~|\$HOME)([[:space:]]|$)'  "Deleting a critical top-level directory - EXTREMELY DANGEROUS!"
    'rm[[:space:]]+-[a-z]*[rf][a-z]*[[:space:]]+\.([[:space:]]|$)'                   "Deleting the current directory recursively - DANGEROUS!"

    # Recursive deletion of a system directory
    'rm[[:space:]]+-[a-z]*[rf][a-z]*[[:space:]]+/(boot|etc|usr|var|lib|bin|sbin)([[:space:]/]|$)'  "Deleting a system directory - SYSTEM FAILURE!"

    # Dangerous permissions
    'chmod[[:space:]]+-R[[:space:]]+777'          "Making everything world-writable - SECURITY RISK!"
    'chmod[[:space:]]+777[[:space:]]+/([[:space:]]|$)'  "Changing root permissions - EXTREMELY DANGEROUS!"

    # Disk operations
    'dd[[:space:]].*of=/dev/(sd|nvme|vd|hd)'      "Writing to raw disk device - DATA LOSS RISK!"
    'mkfs'                                        "Creating filesystem - WILL DESTROY DATA!"
    '(^|[[:space:]])fdisk([[:space:]]|$)'         "Disk partitioning - DATA LOSS RISK!"

    # Package management
    '(apt-get|apt|yum|dnf)[[:space:]]+(remove|purge).*[[:space:]]sudo([[:space:]]|$)'  "Removing sudo - YOU'LL LOSE ADMIN ACCESS!"

    # Network
    'iptables[[:space:]]+-[FX]([[:space:]]|$)'    "Flushing/deleting firewall rules - SECURITY RISK!"
)

# Warnings for potentially dangerous but common operations
typeset -gA WARNING_PATTERNS=(
    # Force flags
    'rm[[:space:]]+-[a-z]*[rf][a-z]*[rf][a-z]*'   "Recursive force deletion"
    'git[[:space:]]+push.*(--force|[[:space:]]-f)([[:space:]]|$)'  "Force push - can overwrite remote history"

    # Sensitive operations
    'sudo[[:space:]]+rm([[:space:]]|$)'           "Removing files as root"
    'chown[[:space:]]+-R'                          "Recursive ownership change - verify paths!"
    'chmod[[:space:]]+777'                          "Making file world-writable"

    # Mass operations
    'find[[:space:]].*-delete'                     "Mass file deletion"
    'xargs[[:space:]].*[[:space:]]rm([[:space:]]|$)'  "Mass file deletion via xargs"
)

# =============================================================================
# Safety Check Function
# =============================================================================

# Pure predicate: echo the danger message for $1, or nothing.
# No I/O beyond the echo, so it is easy to unit-test.
_nivuus_match_danger() {
    local cmd="$1" pattern danger_msg
    [[ -z "$cmd" ]] && return 1
    for pattern danger_msg in ${(kv)DANGEROUS_PATTERNS}; do
        if [[ "$cmd" =~ $pattern ]]; then
            print -r -- "$danger_msg"
            return 0
        fi
    done
    return 1
}

# Pure predicate: echo the warning message for $1, or nothing.
_nivuus_match_warning() {
    local cmd="$1" pattern warning_msg
    [[ -z "$cmd" ]] && return 1
    for pattern warning_msg in ${(kv)WARNING_PATTERNS}; do
        if [[ "$cmd" =~ $pattern ]]; then
            print -r -- "$warning_msg"
            return 0
        fi
    done
    return 1
}

# Interactive check. Returns 0 to allow the command, 1 to block it.
# Reads confirmation from the terminal, so it works from within a ZLE widget.
_nivuus_safety_confirm() {
    local cmd="$1" msg

    if msg=$(_nivuus_match_danger "$cmd"); then
        print -r ""
        print -rP "⚠️  ${NORD_ERROR}DANGER:${NORD_RESET} $msg"
        print -rP "Command: ${NORD_PATH}$cmd${NORD_RESET}"
        print -rn "Type 'yes' to run this command (anything else cancels): "
        local response
        read -r response </dev/tty 2>/dev/null || read -r response
        [[ "$response" == "yes" ]]
        return
    fi

    if msg=$(_nivuus_match_warning "$cmd"); then
        print -r ""
        print -rP "⚠️  ${NORD_FIREBASE}WARNING:${NORD_RESET} $msg"
        print -rP "Command: ${NORD_PATH}$cmd${NORD_RESET}"
        print -rn "Press Enter to run, or Ctrl-C to cancel... "
        read -r </dev/tty 2>/dev/null || read -r
        return 0
    fi

    return 0
}

# =============================================================================
# Hook into Command Execution (via accept-line ZLE widget)
# =============================================================================
# Unlike a preexec hook, an accept-line widget runs BEFORE the line is
# submitted, so it can truly prevent execution by clearing the buffer.

_nivuus_safety_accept_line() {
    if _nivuus_match_danger "$BUFFER" >/dev/null || \
       _nivuus_match_warning "$BUFFER" >/dev/null; then
        # Take over the display to prompt interactively.
        zle -I
        if ! _nivuus_safety_confirm "$BUFFER"; then
            print -rP "${NORD_ERROR}✗ Command cancelled${NORD_RESET}"
            BUFFER=""
            zle reset-prompt
            return 0
        fi
    fi

    # Delegate to the previous accept-line (preserves plugin behaviour such
    # as zsh-autosuggestions), falling back to the builtin.
    if [[ -n "${widgets[_nivuus_orig_accept_line]}" ]]; then
        zle _nivuus_orig_accept_line
    else
        zle .accept-line
    fi
}

# Only wrap accept-line in an interactive shell with ZLE available.
if [[ -o interactive ]] && zle -l >/dev/null 2>&1; then
    # Preserve any existing accept-line widget under a new name, then wrap it.
    if [[ "${widgets[accept-line]}" == user:* ]]; then
        zle -A accept-line _nivuus_orig_accept_line
    fi
    zle -N accept-line _nivuus_safety_accept_line
fi

# =============================================================================
# Safe Alternatives
# =============================================================================

# Safe rm with confirmation for important files
safe-rm() {
    local files=("$@")
    local important_files=()

    # Check for important files
    for file in "${files[@]}"; do
        # Skip flags
        [[ "$file" =~ ^- ]] && continue

        # Check if file is important (hidden files, config files, etc.)
        if [[ "$file" =~ ^\. ]] || \
           [[ "$file" =~ (config|rc|profile|bashrc|zshrc)$ ]] || \
           [[ -d "$file" ]]; then
            important_files+=("$file")
        fi
    done

    # Warn about important files
    if [[ ${#important_files[@]} -gt 0 ]]; then
        echo "⚠️  About to delete important files:"
        for file in "${important_files[@]}"; do
            echo "  - $file"
        done
        echo -n "Continue? (y/N): "
        read -r response

        if [[ "$response" != "y" ]] && [[ "$response" != "Y" ]]; then
            echo "Cancelled"
            return 1
        fi
    fi

    # Execute rm
    command rm "$@"
}

# Safe chmod - warns about 777
safe-chmod() {
    local mode="$1"
    shift
    local files=("$@")

    # Warn about 777
    if [[ "$mode" == "777" ]] || [[ "$mode" == "a+rwx" ]]; then
        echo "⚠️  WARNING: Setting permissions to 777 (world-writable)"
        echo "This is a security risk. Consider using 755 or 775 instead."
        echo -n "Continue with 777? (y/N): "
        read -r response

        if [[ "$response" != "y" ]] && [[ "$response" != "Y" ]]; then
            echo "Cancelled. Suggested alternatives:"
            echo "  chmod 755 (rwxr-xr-x) - owner full, others read/execute"
            echo "  chmod 775 (rwxrwxr-x) - owner+group full, others read/execute"
            echo "  chmod 700 (rwx------) - owner only"
            return 1
        fi
    fi

    # Execute chmod
    command chmod "$mode" "${files[@]}"
}

# =============================================================================
# Configuration Help
# =============================================================================

safety-help() {
    cat <<EOF
Command Safety Checks - Protection Against Dangerous Commands

This module warns you before executing potentially dangerous commands.

Configuration:
  export ENABLE_SAFETY_CHECKS=false    # Disable all safety checks

Critical Checks (require 'yes' confirmation):
  • rm -rf / or ~                      # Deleting critical directories
  • chmod 777 /                        # Dangerous permissions on root
  • dd to /dev/sd*                     # Raw disk writes
  • mkfs, fdisk                        # Filesystem operations
  • Removing /boot, /etc, /usr, /var   # System directories
  • Removing sudo package              # Loss of admin access

Warning Checks (press Enter to continue):
  • rm -rf                             # Recursive force deletion
  • git push --force                   # Force push
  • sudo rm                            # Root deletion
  • chmod 777                          # World-writable permissions
  • find ... -delete                   # Mass deletion

Safe Alternatives:
  safe-rm <files>      # Warns before deleting important files
  safe-chmod <mode>    # Warns about dangerous permissions

Examples:
  # This will require confirmation:
  rm -rf /

  # This will show a warning:
  rm -rf node_modules

  # Safe alternative:
  safe-rm .env .npmrc

Bypass (for scripts):
  # Add comment to bypass checks in automated scripts
  # NIVUUS_SAFETY_BYPASS
  rm -rf /tmp/safe-to-delete

EOF
}

# =============================================================================
# Aliases
# =============================================================================

# Optionally override rm and chmod with safe versions
if [[ "${ENABLE_SAFE_ALIASES:-false}" == "true" ]]; then
    alias rm='safe-rm'
    alias chmod='safe-chmod'
fi
