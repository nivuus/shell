#!/usr/bin/env zsh
# =============================================================================
# AI Command Not Found -- package lookup sources
# =============================================================================
# Part of config/24-ai-command-not-found.zsh, which sources this file: the
# native tools (command-not-found, pkgfile) and the AI backend that turn a
# missing command into a package suggestion.
# =============================================================================

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
