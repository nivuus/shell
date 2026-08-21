#!/usr/bin/env zsh
# =============================================================================
# Nivuus Prompt
# =============================================================================
# Default format: [SSH] [ROOT] STATUS PATH (VENV) CLOUD [FIREBASE] GIT [JOBS]
# Synchronous with Git caching (2s TTL). Layout is driven by the
# NIVUUS_PROMPT_FORMAT / NIVUUS_RPROMPT_FORMAT template strings (see
# doc/PROMPT.md); colors come from the loaded theme ($THEME_*).
# =============================================================================

# Enable prompt substitution
setopt PROMPT_SUBST

# =============================================================================
# Prompt glyphs
# =============================================================================
# Glyphes du prompt. Aucun n'est une nerd font ; en mode minimal (serveur,
# container, console sans police riche) on retombe malgré tout sur de l'ASCII
# pur. Surchargeables individuellement par l'utilisateur.
if [[ -n "${NIVUUS_MINIMAL:-}" ]]; then
    : ${NIVUUS_GLYPH_GIT_DIRTY:=o}
    : ${NIVUUS_GLYPH_GIT_CLEAN:=+}
    : ${NIVUUS_GLYPH_JOB_RUNNING:=>}
    : ${NIVUUS_GLYPH_JOB_STOPPED:=_}
else
    : ${NIVUUS_GLYPH_GIT_DIRTY:=○}
    : ${NIVUUS_GLYPH_GIT_CLEAN:=●}
    : ${NIVUUS_GLYPH_JOB_RUNNING:=▶}
    : ${NIVUUS_GLYPH_JOB_STOPPED:=⏸}
fi

# =============================================================================
# Git Prompt Cache
# =============================================================================

typeset -g _GIT_PROMPT_CACHE_DIR=""
typeset -g _GIT_PROMPT_CACHE_TIME=0
typeset -g _GIT_PROMPT_CACHE_VALUE=""

# =============================================================================
# Firebase Prompt Cache
# =============================================================================

typeset -g _FIREBASE_PROMPT_CACHE_DIR=""
typeset -g _FIREBASE_PROMPT_CACHE_TIME=0
typeset -g _FIREBASE_PROMPT_CACHE_VALUE=""

# =============================================================================
# Azure Cloud Context Cache
# =============================================================================

typeset -g _AZURE_PROMPT_CACHE_TIME=0
typeset -g _AZURE_PROMPT_CACHE_VALUE=""

# =============================================================================
# Helper Functions
# =============================================================================

# Check if running in SSH session
is_ssh() {
    [[ -n "$SSH_CLIENT" || -n "$SSH_TTY" || "$SESSION_TYPE" == "remote" ]]
}

# Check if running as root
is_root() {
    [[ "$EUID" -eq 0 || "$(whoami)" == "root" ]]
}

# =============================================================================
# Git Prompt with Cache
# =============================================================================

git_prompt_info() {
    # Check if in a git repository
    git rev-parse --git-dir &>/dev/null || return 0

    local current_dir="$PWD"
    local current_time="$EPOCHSECONDS"
    local cache_ttl="${GIT_PROMPT_CACHE_TTL:-2}"

    # Use cache if valid
    if [[ "$_GIT_PROMPT_CACHE_DIR" == "$current_dir" ]] && \
       (( current_time - _GIT_PROMPT_CACHE_TIME < cache_ttl )); then
        echo "$_GIT_PROMPT_CACHE_VALUE"
        return
    fi

    # Get git branch
    local branch
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git describe --tags --exact-match 2>/dev/null || echo "detached")

    # Check for modifications (using porcelain for reliability)
    local status_icon=""
    if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
        status_icon="%{${THEME_ERROR}%}${NIVUUS_GLYPH_GIT_DIRTY}%{%f%}"  # empty circle when dirty
    else
        status_icon="%{${THEME_SUCCESS}%}${NIVUUS_GLYPH_GIT_CLEAN}%{%f%}"  # filled circle when clean
    fi

    # Build git prompt with theme colors
    # git:( in prefix color bold, branch in branch color, ) in prefix color bold, space, status icon
    local git_prompt=" %{%B${THEME_GIT_PREFIX}%}git:(%{${THEME_GIT_BRANCH}%}${branch}%{%B${THEME_GIT_PREFIX}%})%{%f%b%} ${status_icon}"

    # Update cache
    _GIT_PROMPT_CACHE_DIR="$current_dir"
    _GIT_PROMPT_CACHE_TIME="$current_time"
    _GIT_PROMPT_CACHE_VALUE="$git_prompt"

    echo "$git_prompt"
}

# =============================================================================
# Firebase Prompt (Optional)
# =============================================================================

prompt_firebase() {
    [[ "${ENABLE_FIREBASE_PROMPT:-true}" != "true" ]] && return

    local current_dir="$PWD"
    local current_time="$EPOCHSECONDS"
    local cache_ttl="${FIREBASE_PROMPT_CACHE_TTL:-10}"

    # Use cache if valid and we're in the same directory
    if [[ "$_FIREBASE_PROMPT_CACHE_DIR" == "$current_dir" ]] && \
       (( current_time - _FIREBASE_PROMPT_CACHE_TIME < cache_ttl )); then
        echo "$_FIREBASE_PROMPT_CACHE_VALUE"
        return
    fi

    # Check if we're in a Firebase project (look for .firebaserc or firebase.json)
    local dir="$PWD"
    local firebase_dir=""

    # Search up the directory tree for .firebaserc or firebase.json
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.firebaserc" ]] || [[ -f "$dir/firebase.json" ]]; then
            firebase_dir="$dir"
            break
        fi
        dir="${dir:h}"
    done

    # If not in a Firebase project, cache empty result and return
    if [[ -z "$firebase_dir" ]]; then
        _FIREBASE_PROMPT_CACHE_DIR="$current_dir"
        _FIREBASE_PROMPT_CACHE_TIME="$current_time"
        _FIREBASE_PROMPT_CACHE_VALUE=""
        return
    fi

    local project=""

    # Try to get active project from global config first
    local firebase_config="$HOME/.config/configstore/firebase-tools.json"
    if [[ -f "$firebase_config" ]] && command -v jq &>/dev/null; then
        # Try to get active project for this directory
        project=$(jq -r --arg dir "$firebase_dir" '.activeProjects[$dir] // empty' "$firebase_config" 2>/dev/null)
    fi

    # If no active project found, try .firebaserc
    if [[ -z "$project" ]] && [[ -f "$firebase_dir/.firebaserc" ]]; then
        if command -v jq &>/dev/null; then
            # Try default first, then first available project
            project=$(jq -r '.projects.default // .projects | to_entries[0].value // empty' "$firebase_dir/.firebaserc" 2>/dev/null)
        else
            # Fallback: pure ZSH parsing (no external commands)
            local content=$(<"$firebase_dir/.firebaserc")
            # Try to extract default project first
            if [[ "$content" =~ '"default"[[:space:]]*:[[:space:]]*"([^"]+)"' ]]; then
                project="${match[1]}"
            else
                # Get first project if no default
                if [[ "$content" =~ '"[^"]+"[[:space:]]*:[[:space:]]*"([^"]+)"' ]]; then
                    project="${match[1]}"
                fi
            fi
        fi
    fi

    # Build Firebase prompt (or empty if no project)
    local firebase_prompt=""
    [[ -n "$project" ]] && firebase_prompt=" %{%F{${THEME_COLORS[orange]}}%}[${project}]%{%f%}"

    # Update cache
    _FIREBASE_PROMPT_CACHE_DIR="$current_dir"
    _FIREBASE_PROMPT_CACHE_TIME="$current_time"
    _FIREBASE_PROMPT_CACHE_VALUE="$firebase_prompt"

    echo "$firebase_prompt"
}

# =============================================================================
# Python Virtual Environment Prompt (Optional)
# =============================================================================

prompt_python_venv() {
    [[ "${ENABLE_PYTHON_VENV:-true}" != "true" ]] && return

    local venv_name=""

    # Check for Conda environment
    if [[ -n "$CONDA_DEFAULT_ENV" ]]; then
        # Don't show 'base' unless explicitly activated
        if [[ "$CONDA_DEFAULT_ENV" != "base" ]] || [[ -n "$CONDA_PREFIX" ]]; then
            venv_name="conda:$CONDA_DEFAULT_ENV"
        fi
    # Check for standard virtual environment (venv/virtualenv)
    elif [[ -n "$VIRTUAL_ENV" ]]; then
        # Get just the directory name, not full path
        venv_name=$(basename "$VIRTUAL_ENV")
    # Check for Poetry environment
    elif [[ -n "$POETRY_ACTIVE" ]]; then
        venv_name="poetry"
    fi

    # Python venv in purple/magenta brackets
    [[ -n "$venv_name" ]] && echo " %{%F{${THEME_COLORS[magenta]}}%}(${venv_name})%{%f%}"
}

# =============================================================================
# Cloud Provider Context (Optional)
# =============================================================================

prompt_cloud_context() {
    [[ "${ENABLE_CLOUD_PROMPT:-true}" != "true" ]] && return

    local cloud_info=""

    # AWS Profile
    if [[ -n "$AWS_PROFILE" ]] && [[ "$AWS_PROFILE" != "default" ]]; then
        cloud_info+=" %{%F{${THEME_COLORS[orange]}}%}aws:${AWS_PROFILE}%{%f%}"
    fi

    # GCP Project (if not already shown by Firebase)
    if [[ -n "$CLOUDSDK_CORE_PROJECT" ]] && [[ "${ENABLE_FIREBASE_PROMPT:-true}" != "true" ]]; then
        [[ -n "$cloud_info" ]] && cloud_info+=" "
        cloud_info+="%{${THEME_GIT_PREFIX}%}gcp:${CLOUDSDK_CORE_PROJECT}%{%f%}"
    fi

    # Azure Subscription (with caching to avoid blocking prompt)
    if [[ -n "$AZURE_SUBSCRIPTION_ID" ]]; then
        local current_time="$EPOCHSECONDS"
        local cache_ttl="${AZURE_PROMPT_CACHE_TTL:-60}"
        local az_sub_name="$AZURE_SUBSCRIPTION_ID"

        # Use cache if valid
        if (( current_time - _AZURE_PROMPT_CACHE_TIME < cache_ttl )) && [[ -n "$_AZURE_PROMPT_CACHE_VALUE" ]]; then
            az_sub_name="$_AZURE_PROMPT_CACHE_VALUE"
        elif command -v az &>/dev/null; then
            # Try to get subscription name (with timeout protection)
            local az_name=$(az account show --query name -o tsv 2>/dev/null)
            if [[ -n "$az_name" ]]; then
                az_sub_name="$az_name"
                # Update cache
                _AZURE_PROMPT_CACHE_TIME="$current_time"
                _AZURE_PROMPT_CACHE_VALUE="$az_name"
            fi
        fi

        [[ -n "$cloud_info" ]] && cloud_info+=" "
        cloud_info+="%{${THEME_SSH}%}az:${az_sub_name}%{%f%}"
    fi

    echo "$cloud_info"
}

# =============================================================================
# Prompt Segments (used by build_prompt via NIVUUS_PROMPT_FORMAT tokens)
# =============================================================================

prompt_segment_ssh() {
    is_ssh && echo "%{%B%F{${THEME_COLORS[comment]}}%}[%{%B${THEME_SSH}%}\$(hostname)%{%B%F{${THEME_COLORS[comment]}}%}]%{%f%b%} "
}

prompt_segment_root() {
    is_root && echo "%{${THEME_ROOT}%}#%{%f%} "
}

prompt_segment_status() {
    echo "%(?:%{%B${THEME_SUCCESS}%}>:%{%B${THEME_ERROR}%}>) "
}

prompt_segment_path() {
    echo "%{${THEME_PATH}%}%~%{%f%}"
}

# =============================================================================
# Build Complete Prompt
# =============================================================================

# Maps {token} placeholders in a NIVUUS_PROMPT_FORMAT-style template to the
# segment function that renders them. Add an entry here to expose a new
# token to user-defined templates.
typeset -gA _NIVUUS_PROMPT_TOKENS
_NIVUUS_PROMPT_TOKENS=(
    ssh      prompt_segment_ssh
    root     prompt_segment_root
    status   prompt_segment_status
    path     prompt_segment_path
    venv     prompt_python_venv
    cloud    prompt_cloud_context
    firebase prompt_firebase
    git      git_prompt_info
    jobs     background_jobs_info
)

# Expand a NIVUUS_PROMPT_FORMAT/NIVUUS_RPROMPT_FORMAT template: {token} is
# replaced with a literal \$(function) call so evaluation stays lazy (each
# prompt render, via PROMPT_SUBST) instead of happening once at build time.
# Unknown tokens are left as-is.
_nivuus_expand_prompt_template() {
    local template="$1"
    local token func
    for token func in ${(kv)_NIVUUS_PROMPT_TOKENS}; do
        template="${template//\{${token}\}/\$(${func})}"
    done
    echo "$template"
}

# Synchronous prompt building
build_prompt() {
    local template="$NIVUUS_PROMPT_FORMAT"
    [[ -z "$template" ]] && template='{ssh}{root}{status} {path}{venv}{cloud}{firebase}{git} '
    _nivuus_expand_prompt_template "$template"
}

build_rprompt() {
    local template="$NIVUUS_RPROMPT_FORMAT"
    [[ -z "$template" ]] && template='{jobs}'
    _nivuus_expand_prompt_template "$template"
}

# =============================================================================
# Background Jobs Info (Right Prompt)
# =============================================================================

background_jobs_info() {
    local output=""

    # Error indicator (from 22-ai-errors.zsh if loaded)
    if [[ "${ENABLE_AI_ERROR_INDICATOR:-true}" == "true" ]] && [[ "$_AI_ERROR_AVAILABLE" == "true" ]]; then
        output+="%{${THEME_ERROR}%}⚠%{%f%}"
    fi

    # Use ZSH native job tracking (more reliable than jobs command)
    local running=0
    local stopped=0
    local running_names=()
    local stopped_names=()

    # Iterate over job states
    for job_id state in ${(kv)jobstates}; do
        # Parse state: jobstates format is "state:pid=status"
        # State can be: running, suspended, done
        local job_state="${state%%:*}"

        case "$job_state" in
            running)
                ((running++))
                # Get job text (command name)
                local job_text="${jobtexts[$job_id]}"
                # Truncate to first word (command name)
                running_names+=(${job_text%% *})
                ;;
            suspended)
                ((stopped++))
                local job_text="${jobtexts[$job_id]}"
                stopped_names+=(${job_text%% *})
                ;;
        esac
    done

    local total=$((running + stopped))

    # Add jobs info if there are any
    if (( total > 0 )); then
        [[ -n "$output" ]] && output+=" "

        # If 2 jobs or less, show names
        if (( total <= 2 )); then
            if (( running > 0 )); then
                local names="${(j: :)running_names}"
                # Truncate if too long
                [[ ${#names} -gt 20 ]] && names="${names:0:17}..."
                output+="%{${THEME_SUCCESS}%}${NIVUUS_GLYPH_JOB_RUNNING} %{%f%}%{${THEME_MUTED}%}${names}%{%f%}"
            fi

            if (( stopped > 0 )); then
                [[ -n "$output" ]] && output+=" "
                local names="${(j: :)stopped_names}"
                [[ ${#names} -gt 20 ]] && names="${names:0:17}..."
                output+="%{${THEME_ERROR}%}${NIVUUS_GLYPH_JOB_STOPPED} %{%f%}%{${THEME_MUTED}%}${names}%{%f%}"
            fi
        else
            # Show counts
            if (( running > 0 )); then
                output+="%{${THEME_SUCCESS}%}${NIVUUS_GLYPH_JOB_RUNNING} ${running}%{%f%}"
            fi

            if (( stopped > 0 )); then
                [[ -n "$output" ]] && output+=" "
                output+="%{${THEME_ERROR}%}${NIVUUS_GLYPH_JOB_STOPPED} ${stopped}%{%f%}"
            fi
        fi
    fi

    echo "$output"
}

# =============================================================================
# Set Prompt
# =============================================================================

# Main prompt: template is expanded once at shell startup into a string
# containing literal \$(...) segment calls, which PROMPT_SUBST re-evaluates
# on every render (same lazy-evaluation model as before this was configurable).
PROMPT=$(build_prompt)

# Right prompt with background jobs (and any other RPROMPT_FORMAT tokens)
RPROMPT=$(build_rprompt)

# Continuation prompt
PROMPT2="${THEME_PATH}%_>${THEME_RESET} "

# Selection prompt
PROMPT3="${THEME_PATH}?#${THEME_RESET} "

# Execution trace prompt
PROMPT4="${THEME_PATH}+%N:%i>${THEME_RESET} "
