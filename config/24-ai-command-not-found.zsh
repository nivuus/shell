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
# Native Tool Lookup (Fast-path)
# =============================================================================

_ai_cnf_native_lookup() {
    local cmd="$1"

    # Debian / Ubuntu command-not-found
    if [[ -x /usr/lib/command-not-found ]]; then
        local out
        out=$(/usr/lib/command-not-found -- "$cmd" 2>/dev/null)
        if [[ -n "$out" ]]; then
            # Extract install line (e.g. "sudo apt install <pkg>")
            local install_line=$(print -r -- "$out" | grep -E '(sudo apt install|apt install|sudo apt-get install)' | head -1 | sed 's/^[[:space:]]*//')
            if [[ -n "$install_line" ]]; then
                local pkg=$(print -r -- "$install_line" | awk '{print $NF}')
                if command -v jq &>/dev/null; then
                    jq -n \
                        --arg cmd "$cmd" \
                        --arg pkg "$pkg" \
                        --arg inst "$install_line" \
                        '{found: true, command: $cmd, description: ("Package " + $pkg + " via apt"), package: $pkg, install_command: $inst, alternative_install: ""}'
                    return 0
                else
                    print -r -- "{\"found\":true,\"command\":\"$cmd\",\"description\":\"Package $pkg via apt\",\"package\":\"$pkg\",\"install_command\":\"$install_line\",\"alternative_install\":\"\"}"
                    return 0
                fi
            fi
        fi
    fi

    # Arch Linux pkgfile
    if command -v pkgfile &>/dev/null; then
        local arch_pkg=$(pkgfile -b "$cmd" 2>/dev/null | head -1)
        if [[ -n "$arch_pkg" ]]; then
            local inst="sudo pacman -S $arch_pkg"
            if command -v jq &>/dev/null; then
                jq -n \
                    --arg cmd "$cmd" \
                    --arg pkg "$arch_pkg" \
                    --arg inst "$inst" \
                    '{found: true, command: $cmd, description: ("Package " + $pkg + " via pacman"), package: $pkg, install_command: $inst, alternative_install: ""}'
                return 0
            else
                print -r -- "{\"found\":true,\"command\":\"$cmd\",\"description\":\"Package $arch_pkg via pacman\",\"package\":\"$arch_pkg\",\"install_command\":\"$inst\",\"alternative_install\":\"\"}"
                return 0
            fi
        fi
    fi

    return 1
}

# =============================================================================
# AI Package Lookup
# =============================================================================

_ai_cnf_ai_lookup() {
    local cmd="$1"
    local full_cmd="$2"
    local sys_context="$3"

    _ai_credentials_ok || return 1

    local prompt="You are a command-line assistant helping a user find the right package to install for a missing shell command.
Missing command: \"$cmd\"
Full command line attempted: \"$full_cmd\"
System context: $sys_context

Determine if this missing command corresponds to a known software package or tool.
If it is a typo, random characters, or not a real command/package, respond with ONLY:
{\"found\": false}

If it is a known tool, respond with ONLY valid JSON (no markdown fences, no explanation, just raw JSON) matching this exact format:
{
  \"found\": true,
  \"command\": \"$cmd\",
  \"description\": \"<brief 1-sentence description of what this command does>\",
  \"package\": \"<exact package name>\",
  \"install_command\": \"<exact installation command for the active OS and package manager, e.g. sudo apt install speech-dispatcher or brew install cowsay or pipx install ruff>\",
  \"alternative_install\": \"<optional secondary install command, or empty string>\"
}"

    local raw_response
    raw_response=$(_ai_api_call "$prompt" "$AI_COMMAND_NOT_FOUND_MODEL" 200 0.1 "$AI_CNF_TIMEOUT" 2>/dev/null)

    [[ -z "$raw_response" ]] && return 1

    # Extract JSON object (in case the model output wraps with backticks or text)
    local json_response=""
    if command -v jq &>/dev/null; then
        json_response=$(print -r -- "$raw_response" | jq -c '.' 2>/dev/null)
        if [[ -z "$json_response" ]]; then
            # Attempt to extract json block
            json_response=$(print -r -- "$raw_response" | sed -n '/{/,/}/p' | jq -c '.' 2>/dev/null)
        fi
    fi

    if [[ -z "$json_response" ]]; then
        # Fallback regex extraction if jq failed or is absent
        if [[ "$raw_response" == *"\"found\": false"* || "$raw_response" == *"\"found\":false"* ]]; then
            json_response='{"found":false}'
        elif [[ "$raw_response" == *"\"found\": true"* || "$raw_response" == *"\"found\":true"* ]]; then
            local p_desc=$(print -r -- "$raw_response" | grep -o '"description"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
            local p_pkg=$(print -r -- "$raw_response" | grep -o '"package"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
            local p_inst=$(print -r -- "$raw_response" | grep -o '"install_command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
            local p_alt=$(print -r -- "$raw_response" | grep -o '"alternative_install"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
            json_response="{\"found\":true,\"command\":\"$cmd\",\"description\":\"$p_desc\",\"package\":\"$p_pkg\",\"install_command\":\"$p_inst\",\"alternative_install\":\"$p_alt\"}"
        fi
    fi

    [[ -z "$json_response" ]] && return 1

    print -r -- "$json_response"
    return 0
}

# =============================================================================
# UI Box Rendering (Nord Palette)
# =============================================================================

_ai_cnf_render_box() {
    local cmd="$1"
    local desc="$2"
    local pkg="$3"
    local install_cmd="$4"
    local alt_cmd="$5"

    print -u2 ""
    print -u2 -P "%F{110}╭─ 🤖 Nivuus AI Package Assistant ────────────────────────────────────%f"
    if [[ -n "$desc" ]]; then
        print -u2 -P "%F{110}│%f  %F{254}Command:%f  %F{143}${cmd}%f %F{244}— ${desc}%f"
    else
        print -u2 -P "%F{110}│%f  %F{254}Command:%f  %F{143}${cmd}%f"
    fi
    if [[ -n "$pkg" ]]; then
        print -u2 -P "%F{110}│%f  %F{254}Package:%f  %F{221}${pkg}%f"
    fi
    print -u2 -P "%F{110}│%f  %F{254}Install:%f  %F{109}${install_cmd}%f"
    if [[ -n "$alt_cmd" ]]; then
        print -u2 -P "%F{110}│%f  %F{244}Alternative: ${alt_cmd}%f"
    fi
    print -u2 -P "%F{110}╰─────────────────────────────────────────────────────────────────────%f"
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

    local found=""
    local desc=""
    local pkg=""
    local install_cmd=""
    local alt_cmd=""

    if command -v jq &>/dev/null; then
        found=$(print -r -- "$json_data" | jq -r '.found // empty' 2>/dev/null)
        desc=$(print -r -- "$json_data" | jq -r '.description // empty' 2>/dev/null)
        pkg=$(print -r -- "$json_data" | jq -r '.package // empty' 2>/dev/null)
        install_cmd=$(print -r -- "$json_data" | jq -r '.install_command // empty' 2>/dev/null)
        alt_cmd=$(print -r -- "$json_data" | jq -r '.alternative_install // empty' 2>/dev/null)
    else
        found=$(print -r -- "$json_data" | grep -o '"found"[[:space:]]*:[[:space:]]*true' | head -1)
        [[ -n "$found" ]] && found="true"
        desc=$(print -r -- "$json_data" | grep -o '"description"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
        pkg=$(print -r -- "$json_data" | grep -o '"package"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
        install_cmd=$(print -r -- "$json_data" | grep -o '"install_command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
        alt_cmd=$(print -r -- "$json_data" | grep -o '"alternative_install"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
    fi

    if [[ "$found" != "true" || -z "$install_cmd" ]]; then
        return 127
    fi

    _ai_cnf_render_box "$cmd" "$desc" "$pkg" "$install_cmd" "$alt_cmd"

    # Only offer interactive confirmation if stdin is a terminal and shell is interactive
    if [[ -t 0 && -o interactive && "${AI_CNF_AUTO_PROMPT:-true}" == "true" ]]; then
        local user_choice
        print -u2 -n -P "%F{221}Install package now with '%F{109}${install_cmd}%F{221}'? [y/N] %f"
        read -r user_choice
        print -u2 ""

        if [[ "$user_choice" =~ ^[yY]([eE][sS])?$ ]]; then
            print -u2 -P "%F{110}⚙ Installing ${pkg:-$cmd}...%f"
            eval "$install_cmd"
            local install_status=$?

            if (( install_status == 0 )); then
                print -u2 -P "%F{143}✓ Successfully installed ${pkg:-$cmd}!%f"
                if [[ "${AI_CNF_RE_EXECUTE:-true}" == "true" ]]; then
                    print -u2 -P "%F{110}▶ Running: ${cmd} ${original_args[*]}%f"
                    print -u2 ""
                    "$cmd" "${original_args[@]}"
                    return $?
                fi
                return 0
            else
                print -u2 -P "%F{167}✗ Installation failed with exit code $install_status%f"
                return 127
            fi
        fi
    fi

    return 127
}

# =============================================================================
# Zsh command_not_found_handler
# =============================================================================

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
  • Automatically adapts to OS & installed package managers (apt, brew, dnf, pipx, npm, cargo...)
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
    │  Install:  sudo apt install -y cowsay
    ╰─────────────────────────────────────────────────────────────────────

    Install package now with 'sudo apt install -y cowsay'? [y/N]

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
