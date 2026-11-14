#!/usr/bin/env zsh
# =============================================================================
# AI Command Not Found & Package Suggestion System
# =============================================================================
# Intercepts unknown commands, identifies matching packages using native tools
# and multi-backend AI, and provides an interactive one-key install & rerun UX.
# =============================================================================

# Skip if explicitly disabled
[[ "${ENABLE_AI_COMMAND_NOT_FOUND:-true}" != "true" ]] && return

# =============================================================================
# Configuration
# =============================================================================

: ${AI_COMMAND_NOT_FOUND_CACHE_DIR:="$HOME/.cache/nivuus-shell/ai-cnf"}
: ${AI_COMMAND_NOT_FOUND_CACHE_TTL:=86400}  # 24 hours
: ${AI_COMMAND_NOT_FOUND_MODEL:="$(_ai_resolve_model)"}
: ${AI_CNF_AUTO_PROMPT:=true}
: ${AI_CNF_RE_EXECUTE:=true}
: ${AI_CNF_TIMEOUT:=8}

# Create cache directory
mkdir -p "$AI_COMMAND_NOT_FOUND_CACHE_DIR" 2>/dev/null

# =============================================================================
# System & Environment Context Detection
# =============================================================================

_ai_cnf_get_sys_context() {
    local os="Linux"
    local distro=""
    local arch=$(uname -m 2>/dev/null || echo "unknown")

    if [[ "$OSTYPE" == "darwin"* ]]; then
        os="macOS"
        distro=$(sw_vers -productVersion 2>/dev/null || echo "")
    elif [[ -f /etc/os-release ]]; then
        distro=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
        [[ -z "$distro" ]] && distro=$(grep -E '^NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
    fi

    local -a pkg_managers=()
    command -v apt-get &>/dev/null && pkg_managers+=("apt")
    command -v brew &>/dev/null && pkg_managers+=("brew")
    command -v dnf &>/dev/null && pkg_managers+=("dnf")
    command -v pacman &>/dev/null && pkg_managers+=("pacman")
    command -v zypper &>/dev/null && pkg_managers+=("zypper")
    command -v apk &>/dev/null && pkg_managers+=("apk")
    command -v nix-env &>/dev/null && pkg_managers+=("nix")
    command -v snap &>/dev/null && pkg_managers+=("snap")
    command -v flatpak &>/dev/null && pkg_managers+=("flatpak")
    command -v pipx &>/dev/null && pkg_managers+=("pipx")
    command -v pip3 &>/dev/null && pkg_managers+=("pip")
    command -v npm &>/dev/null && pkg_managers+=("npm")
    command -v pnpm &>/dev/null && pkg_managers+=("pnpm")
    command -v bun &>/dev/null && pkg_managers+=("bun")
    command -v cargo &>/dev/null && pkg_managers+=("cargo")
    command -v go &>/dev/null && pkg_managers+=("go")

    local pm_list="${(j:, :)pkg_managers}"
    print -r -- "OS: ${distro:-$os} ($arch), Available package managers: ${pm_list:-none}"
}

# =============================================================================
# Cache Management
# =============================================================================

_ai_cnf_cache_key() {
    local cmd="$1"
    local context="$2"
    if command -v md5sum &>/dev/null; then
        echo -n "${cmd}|${context}" | md5sum | cut -d' ' -f1
    elif command -v md5 &>/dev/null; then
        echo -n "${cmd}|${context}" | md5
    else
        echo -n "${cmd}" | tr '/:' '__'
    fi
}

_ai_cnf_cache_get() {
    local cache_key="$1"
    local cache_file="$AI_COMMAND_NOT_FOUND_CACHE_DIR/$cache_key"

    if [[ -f "$cache_file" ]]; then
        local file_time=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
        local current_time=$(date +%s)

        if (( current_time - file_time < AI_COMMAND_NOT_FOUND_CACHE_TTL )); then
            cat "$cache_file"
            return 0
        fi
    fi

    return 1
}

_ai_cnf_cache_set() {
    local cache_key="$1"
    local content="$2"
    local cache_file="$AI_COMMAND_NOT_FOUND_CACHE_DIR/$cache_key"

    mkdir -p "$AI_COMMAND_NOT_FOUND_CACHE_DIR" 2>/dev/null
    print -r -- "$content" > "$cache_file" 2>/dev/null
}

# =============================================================================
# Package Lookup Sources
# =============================================================================

# The module is split across files to keep each one readable; the lookup
# sources are sourced here rather than listed in .zshrc, so the module keeps
# a single entry point.
source "${${(%):-%x}:A:h}/24-ai-command-not-found-lookup.zsh"

# =============================================================================
# UI Box Rendering — charte Nivuus (doc/CHARTE.md)
# =============================================================================

# Every string but the install command comes from the typed command line or
# a lookup result: control characters are made visible (${(V)...}), so an
# escape sequence in a reply cannot redraw the screen or hide text.
_ai_cnf_render_box() {
    local cmd="${(V)1}"
    local desc="${(V)2}"
    local pkg="${(V)3}"
    local install_cmd="$4"

    _ai_charte_load

    print -u2 ""
    print -u2 -r -- "╭─ 🤖 Nivuus AI Package Assistant ────────────────────────────────────"
    if [[ -n "$desc" ]]; then
        print -u2 -r -- "│  ${NIVUUS_C_STRONG:-}Command:${NIVUUS_C_OFF:-}  ${cmd} — ${desc}"
    else
        print -u2 -r -- "│  ${NIVUUS_C_STRONG:-}Command:${NIVUUS_C_OFF:-}  ${cmd}"
    fi
    if [[ -n "$pkg" ]]; then
        print -u2 -r -- "│  ${NIVUUS_C_STRONG:-}Package:${NIVUUS_C_OFF:-}  ${pkg}"
    fi
    print -u2 -r -- "│  ${NIVUUS_C_STRONG:-}Install:${NIVUUS_C_OFF:-}  ${install_cmd}"
    print -u2 -r -- "╰─────────────────────────────────────────────────────────────────────"
    print -u2 ""
}

# =============================================================================
# Main Lookup Resolver
# =============================================================================

_ai_cnf_lookup() {
    local cmd="$1"
    local full_cmd="$2"

    local sys_context=$(_ai_cnf_get_sys_context)
    local cache_key=$(_ai_cnf_cache_key "$cmd" "$sys_context")

    # 1. Check cache
    local payload
    if payload=$(_ai_cnf_cache_get "$cache_key"); then
        print -r -- "$payload"
        return 0
    fi

    # 2. Check native tool (fast-path)
    if payload=$(_ai_cnf_native_lookup "$cmd"); then
        _ai_cnf_cache_set "$cache_key" "$payload"
        print -r -- "$payload"
        return 0
    fi

    # 3. Check AI
    if payload=$(_ai_cnf_ai_lookup "$cmd" "$full_cmd" "$sys_context"); then
        _ai_cnf_cache_set "$cache_key" "$payload"
        print -r -- "$payload"
        return 0
    fi

    return 1
}

# =============================================================================
# Interactive Confirmation & Auto-execution
# =============================================================================

_ai_cnf_handle_suggestion() {
    local json_data="$1"
    local cmd="$2"
    shift 2
    local -a original_args=("$@")

    local found="" desc="" pkg="" mgr=""

    if command -v jq &>/dev/null; then
        found=$(print -r -- "$json_data" | jq -r '.found // empty' 2>/dev/null)
        desc=$(print -r -- "$json_data" | jq -r '.description // empty' 2>/dev/null)
        pkg=$(print -r -- "$json_data" | jq -r '.package // empty' 2>/dev/null)
        mgr=$(print -r -- "$json_data" | jq -r '.manager // empty' 2>/dev/null)
    else
        found=$(print -r -- "$json_data" | grep -o '"found"[[:space:]]*:[[:space:]]*true' | head -1)
        [[ -n "$found" ]] && found="true"
        desc=$(_ai_cnf_json_field description "$json_data")
        pkg=$(_ai_cnf_json_field package "$json_data")
        mgr=$(_ai_cnf_json_field manager "$json_data")
    fi

    [[ "$found" == "true" ]] || return 127

    # A result that does not validate offers no install at all.
    local -a install_argv
    _ai_cnf_install_argv "$mgr" "$pkg" || return 127
    install_argv=("${reply[@]}")
    local install_cmd="${(j: :)install_argv}"

    _ai_cnf_render_box "$cmd" "$desc" "$pkg" "$install_cmd"

    # Only offer interactive confirmation if stdin is a terminal and shell is interactive
    if [[ -t 0 && -o interactive && "${AI_CNF_AUTO_PROMPT:-true}" == "true" ]]; then
        local user_choice
        print -u2 -n -r -- "${NIVUUS_C_STRONG:-}Install package now with '${install_cmd}'? [y/N] ${NIVUUS_C_OFF:-}"
        read -r user_choice
        print -u2 ""

        if [[ "$user_choice" =~ ^[yY]([eE][sS])?$ ]]; then
            print -u2 -r -- "${NIVUUS_C_BUSY:-}⚙ Installing ${pkg}...${NIVUUS_C_OFF:-}"
            "${install_argv[@]}"
            local install_status=$?

            if (( install_status == 0 )); then
                print -u2 -r -- "${NIVUUS_C_OK:-}✓ Successfully installed ${pkg}!${NIVUUS_C_OFF:-}"
                if [[ "${AI_CNF_RE_EXECUTE:-true}" == "true" ]]; then
                    print -u2 -r -- "${NIVUUS_C_BUSY:-}▶ Running: ${(V)cmd} ${(V)original_args[*]}${NIVUUS_C_OFF:-}"
                    print -u2 ""
                    "$cmd" "${original_args[@]}"
                    return $?
                fi
                return 0
            else
                print -u2 -r -- "${NIVUUS_C_DANGER:-}✗ Installation failed with exit code $install_status${NIVUUS_C_OFF:-}"
                return 127
            fi
        fi
    fi

    return 127
}

# =============================================================================
# Zsh command_not_found_handler
# =============================================================================

# Install the hook only for a terminal. This feature is a prompt-and-install
# dialogue: off a terminal it can only spend an AI_CNF_TIMEOUT round-trip on a
# typo and offer an install nobody can accept. Leaving the handler undefined
# gives back zsh's own `command not found` on stderr, which is what a script
# or an agent expects. The helpers above stay defined either way — they are
# inert until called, and `ai-cnf-lookup` remains available on demand.
if nivuus_has_terminal; then

command_not_found_handler() {
    # Recursion protection
    if [[ -n "$_AI_CNF_ACTIVE" ]]; then
        print -u2 "zsh: command not found: $1"
        return 127
    fi
    local _AI_CNF_ACTIVE=1

    local cmd="$1"
    shift
    local -a args=("$@")
    local full_cmd="$cmd ${(j: :)args}"

    # Print default not found message to stderr first
    print -u2 "zsh: command not found: $cmd"

    # Skip AI suggestion if disabled
    if [[ "${ENABLE_AI_COMMAND_NOT_FOUND:-true}" != "true" ]]; then
        return 127
    fi

    local json_result
    if json_result=$(_ai_cnf_lookup "$cmd" "$full_cmd"); then
        _ai_cnf_handle_suggestion "$json_result" "$cmd" "${args[@]}"
        return $?
    fi

    return 127
}

fi  # nivuus_has_terminal

# =============================================================================
# User Commands & Cache Management
# =============================================================================

ai-cnf-lookup() {
    local cmd="$1"
    if [[ -z "$cmd" ]]; then
        echo "Usage: ai-cnf-lookup <command>"
        return 1
    fi

    echo "Looking up package for '$cmd'..."
    local res=$(_ai_cnf_lookup "$cmd" "$cmd")
    if [[ -n "$res" ]]; then
        _ai_cnf_handle_suggestion "$res" "$cmd"
    else
        echo "No package suggestion found for '$cmd'."
    fi
}

ai-cnf-clear-cache() {
    local count=$(ls -1 "$AI_COMMAND_NOT_FOUND_CACHE_DIR" 2>/dev/null | wc -l)
    rm -rf "$AI_COMMAND_NOT_FOUND_CACHE_DIR"/*
    mkdir -p "$AI_COMMAND_NOT_FOUND_CACHE_DIR"
    echo "✓ Cleared $count cached package suggestions"
}

ai-cnf-stats() {
    local cache_count=$(ls -1 "$AI_COMMAND_NOT_FOUND_CACHE_DIR" 2>/dev/null | wc -l)
    local cache_size=$(du -sh "$AI_COMMAND_NOT_FOUND_CACHE_DIR" 2>/dev/null | awk '{print $1}')
    [[ -z "$cache_size" ]] && cache_size="0B"

    echo "AI Command Not Found Statistics"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Cached suggestions: $cache_count"
    echo "Cache size: $cache_size"
    echo "Cache TTL: ${AI_COMMAND_NOT_FOUND_CACHE_TTL}s ($(( AI_COMMAND_NOT_FOUND_CACHE_TTL / 3600 )) hours)"
    echo "Model: $AI_COMMAND_NOT_FOUND_MODEL"
    echo "Auto prompt: ${AI_CNF_AUTO_PROMPT:-true}"
    echo "Auto re-execute: ${AI_CNF_RE_EXECUTE:-true}"
    echo "Timeout: ${AI_CNF_TIMEOUT:-8}s"
    echo ""
    echo "System context:"
    echo "  $(_ai_cnf_get_sys_context)"
}

ai-cnf-help() {
    cat <<'EOF'
AI Command Not Found System
━━━━━━━━━━━━━━━━━━━━━━━━━━━

Intercepts unknown shell commands, identifies the matching software package
via native system tools or AI, and offers an interactive prompt to install
the package and re-run your original command.

FEATURES:
  • Fast-path native lookup (0ms) when system tools exist (Ubuntu/Debian/Arch)
  • Multi-backend AI resolution (Gemini / Anthropic / OpenAI)
  • Installs with the system package manager (apt-get, dnf, yum, pacman, zypper, apk, brew);
    the command is built locally, never taken from the AI reply
  • Interactive [y/N] install confirmation with zero friction
  • Automatic re-execution of the initial command upon successful installation
  • 24h caching to prevent redundant API calls

USAGE:
  Simply run any command. If not found:
    $ cowsay coucou
    zsh: command not found: cowsay

    ╭─ 🤖 Nivuus AI Package Assistant ────────────────────────────────────
    │  Command:  cowsay — Configurable talking cow in ASCII art
    │  Package:  cowsay
    │  Install:  sudo apt-get install -y --no-install-recommends cowsay
    ╰─────────────────────────────────────────────────────────────────────

    Install package now with 'sudo apt-get install -y --no-install-recommends cowsay'? [y/N]

COMMANDS:
  ai-cnf-lookup <cmd>    Manually look up the package for a command
  ai-cnf-clear-cache     Clear cached package suggestions
  ai-cnf-stats           Display statistics and detected system context
  ai-cnf-help            Show this help message

CONFIGURATION:
  export ENABLE_AI_COMMAND_NOT_FOUND=false  # Disable feature
  export AI_CNF_AUTO_PROMPT=false          # Show suggestion box only, don't prompt
  export AI_CNF_RE_EXECUTE=false           # Don't auto re-run after install
  export AI_COMMAND_NOT_FOUND_CACHE_TTL=86400 # Cache duration in seconds
  export AI_CNF_TIMEOUT=8                  # AI API call timeout in seconds

EOF
}
