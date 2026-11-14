#!/usr/bin/env zsh
# =============================================================================
# AI Command Not Found -- package lookup sources
# =============================================================================
# Part of config/24-ai-command-not-found.zsh, which sources this file: the
# native tools (command-not-found, pkgfile) and the AI backend that turn a
# missing command into a package suggestion, and the install command built
# from that suggestion.
# =============================================================================

# =============================================================================
# Install Command (never taken from a lookup result)
# =============================================================================
# A lookup result -- the model's reply above all -- names a package manager
# and a package, nothing else. The command is built here from lib/deps.sh,
# the table the installer uses, and run as an argument list: what the box
# shows is exactly what runs, and no text from the reply is ever evaluated.

typeset -ga _AI_CNF_MANAGERS=(apt-get dnf yum pacman zypper apk brew)

# The managers of that table installed on this machine, comma-separated.
_ai_cnf_supported_managers() {
    local m
    local -a present=()
    for m in $_AI_CNF_MANAGERS; do
        (( $+commands[$m] )) && present+=("$m")
    done
    print -r -- "${(j:, :)present}"
}

# Conservative package name: ASCII letters, digits and . + _ -, not starting
# with a dash (never an option), at most 128 characters.
_ai_cnf_valid_package() {
    setopt localoptions extendedglob
    [[ ${#1} -le 128 && "$1" == [A-Za-z0-9][A-Za-z0-9.+_-]# ]]
}

# Set reply to the install command for package $2 with manager $1, as an
# argument list. Fails, leaving reply empty, unless the manager is one of
# the table above and installed here and the package name is valid.
_ai_cnf_install_argv() {
    local mgr="$1" pkg="$2" line
    reply=()
    (( ${_AI_CNF_MANAGERS[(Ie)$mgr]} )) || return 1
    (( $+commands[$mgr] )) || return 1
    _ai_cnf_valid_package "$pkg" || return 1
    (( $+functions[nivuus_is_root] )) || source "$NIVUUS_SHELL_DIR/lib/detect.sh"
    (( $+functions[nivuus_pkg_install_cmd] )) || source "$NIVUUS_SHELL_DIR/lib/deps.sh"
    line=$(nivuus_pkg_install_cmd "$mgr" "$pkg")
    reply=(${=line})
    if nivuus_pkg_needs_root "$mgr" && ! nivuus_is_root; then
        reply=(sudo "${reply[@]}")
    fi
    (( ${#reply} ))
}

# Lookup result: {"found":true,"package":$1,"manager":$2,"description":$3}.
_ai_cnf_payload() {
    if command -v jq &>/dev/null; then
        jq -cn --arg p "$1" --arg m "$2" --arg d "$3" \
            '{found: true, package: $p, manager: $m, description: $d}'
    else
        # Without jq, the values are quote-free by construction (validated
        # package names, fixed text, or [^"]* matches of the reply).
        print -r -- "{\"found\":true,\"package\":\"$1\",\"manager\":\"$2\",\"description\":\"$3\"}"
    fi
}

# =============================================================================
# Native Tool Lookup (Fast-path)
# =============================================================================

_ai_cnf_native_lookup() {
    local cmd="$1" pkg

    # Debian / Ubuntu command-not-found
    if [[ -x /usr/lib/command-not-found ]]; then
        local out
        out=$(/usr/lib/command-not-found -- "$cmd" 2>/dev/null)
        if [[ -n "$out" ]]; then
            # Package from the install line (e.g. "sudo apt install <pkg>")
            pkg=$(print -r -- "$out" | grep -E '(sudo apt install|apt install|sudo apt-get install)' | head -1 | awk '{print $NF}')
            if _ai_cnf_valid_package "$pkg"; then
                _ai_cnf_payload "$pkg" apt-get "Package $pkg via apt"
                return 0
            fi
        fi
    fi

    # Arch Linux pkgfile ("repository/package")
    if command -v pkgfile &>/dev/null; then
        pkg=$(pkgfile -b "$cmd" 2>/dev/null | head -1)
        pkg="${pkg##*/}"
        if _ai_cnf_valid_package "$pkg"; then
            _ai_cnf_payload "$pkg" pacman "Package $pkg via pacman"
            return 0
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

    # Without a manager the install command can be built for, there is
    # nothing to offer: skip the round trip.
    local managers=$(_ai_cnf_supported_managers)
    [[ -n "$managers" ]] || return 1

    local prompt="You are a command-line assistant helping a user find the right package to install for a missing shell command.
Missing command: \"$cmd\"
Full command line attempted: \"$full_cmd\"
System context: $sys_context
Package managers you may answer with: $managers

Determine if this missing command corresponds to a known software package or tool.
If it is a typo, random characters, or not a real command/package, or no listed package manager provides it, respond with ONLY:
{\"found\": false}

If it is a known tool, respond with ONLY valid JSON (no markdown fences, no explanation, just raw JSON) matching this exact format:
{
  \"found\": true,
  \"description\": \"<brief 1-sentence description of what this command does>\",
  \"package\": \"<exact package name, nothing else>\",
  \"manager\": \"<one of: $managers>\"
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
            json_response=$(_ai_cnf_payload \
                "$(_ai_cnf_json_field package "$raw_response")" \
                "$(_ai_cnf_json_field manager "$raw_response")" \
                "$(_ai_cnf_json_field description "$raw_response")")
        fi
    fi

    [[ -z "$json_response" ]] && return 1

    print -r -- "$json_response"
    return 0
}

# String field $1 of JSON text $2, for when jq is absent.
_ai_cnf_json_field() {
    print -r -- "$2" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | cut -d'"' -f4
}
