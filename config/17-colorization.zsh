#!/usr/bin/env zsh
# =============================================================================
# Command Output Colorization
# =============================================================================
# Modern tools + grc for colorized command outputs, themed via $THEME_HEX /
# $THEME_BAT_NAME / $THEME_DELTA_SYNTAX (set by the loaded themes/*.zsh)
# =============================================================================

# Only load once
[[ -n "${NIVUUS_COLORIZATION_LOADED}" ]] && return
typeset -g NIVUUS_COLORIZATION_LOADED=1

# Skip only if terminal is dumb (not if non-interactive)
[[ "$TERM" == "dumb" ]] && return

# =============================================================================
# Modern Tools - eza (ls replacement)
# =============================================================================

if command -v eza &>/dev/null; then
    # Nord-inspired colors for eza
    # Format: file_type=color_code
    export EZA_COLORS="reset:di=1;36:ln=1;35:so=1;32:pi=1;33:ex=1;31:bd=1;34:cd=1;34:su=37;41:sg=30;43:tw=30;42:ow=30;43"

    # These alias standard command names onto eza, whose options are NOT those
    # of coreutils (`ls -t` means `--time <FIELD>` here, and errors out without
    # an argument). That trade is only worth making for a human at a terminal;
    # a script or an agent shell gets the real binaries.
    #
    # --color=auto, never always: the decision belongs to each invocation, so
    # `ls | grep` stops emitting escape sequences into a pipe that cannot
    # render them. Note that zsh bakes aliases into function bodies at parse
    # time, so `always` here also leaked into the chpwd hook below.
    if nivuus_has_terminal; then
        # Basic aliases (icons disabled for compatibility)
        alias ls='eza --color=auto --group-directories-first'
        alias ll='eza -l --color=auto --group-directories-first --git'
        alias la='eza -la --color=auto --group-directories-first --git'
        alias tree='eza --tree --color=auto'

        # Extended aliases
        alias l='eza -lbF --color=auto --git'
        alias lt='eza --tree --level=2 --color=auto'
    fi
fi

# =============================================================================
# bat (cat replacement with syntax highlighting)
# =============================================================================

local _bat_theme="${THEME_BAT_NAME:-Nord}"

if command -v bat &>/dev/null; then
    # Use bat with the active theme
    export BAT_THEME="$_bat_theme"

    # Style options: plain (no decorations), auto (all decorations), numbers, grid, header
    # Customize with: export BAT_STYLE="numbers,grid"
    local bat_style="${BAT_STYLE:-plain}"

    # Terminal only, same reason as eza: bat rejects POSIX cat options
    # (`cat -v`, `-e`, `-b`, `-T`), and a pager set to --paging=always is a
    # display choice that makes no sense where nothing is displayed.
    if nivuus_has_terminal; then
        alias cat="bat --theme=${_bat_theme} --style=${bat_style}"
        alias less="bat --theme=${_bat_theme} --style=${bat_style} --paging=always"

        # Set bat as default pager
        export PAGER="bat --theme=${_bat_theme} --style=${bat_style} --paging=always"
        export MANPAGER="sh -c 'col -bx | bat --theme=${_bat_theme} -l man -p'"
    fi

elif command -v batcat &>/dev/null; then
    # Debian/Ubuntu uses batcat (conflict with bacula)
    export BAT_THEME="$_bat_theme"

    local bat_style="${BAT_STYLE:-plain}"

    alias bat='batcat'

    if nivuus_has_terminal; then
        alias cat="batcat --theme=${_bat_theme} --style=${bat_style}"
        alias less="batcat --theme=${_bat_theme} --style=${bat_style} --paging=always"

        export PAGER="batcat --theme=${_bat_theme} --style=${bat_style} --paging=always"
        export MANPAGER="sh -c 'col -bx | batcat --theme=${_bat_theme} -l man -p'"
    fi
fi

# =============================================================================
# timg (terminal image viewer)
# =============================================================================

if command -v timg &>/dev/null; then
    # Wrapper function pour afficher des images dans le terminal
    img() {
        timg "$@"
    }

    # Alias alternatif
    alias showimg='img'
fi

# =============================================================================
# delta (git diff with syntax highlighting)
# =============================================================================

if command -v delta &>/dev/null; then
    # Configure git to use delta with the active theme
    _configure_delta_git() {
        local delta_theme="${THEME_DELTA_SYNTAX:-Nord}"
        local delta_bg="${THEME_HEX[bg_main]:-#2E3440}"
        local delta_green="${THEME_HEX[green]:-#A3BE8C}"
        local delta_red="${THEME_HEX[red]:-#BF616A}"

        git config --global core.pager delta
        git config --global interactive.diffFilter 'delta --color-only'
        git config --global delta.syntax-theme "$delta_theme"
        git config --global delta.navigate true
        git config --global delta.line-numbers true
        git config --global delta.side-by-side false

        # Theme-specific colors for diffs
        git config --global delta.plus-style "syntax ${delta_bg}"
        git config --global delta.plus-emph-style "syntax ${delta_green}"
        git config --global delta.minus-style "syntax ${delta_bg}"
        git config --global delta.minus-emph-style "syntax ${delta_red}"
        git config --global delta.file-style "bold yellow"
        git config --global delta.file-decoration-style "yellow ul"
        git config --global delta.hunk-header-style "bold cyan"
    }

    # Run in background to avoid blocking shell startup
    (_configure_delta_git &)
fi

# =============================================================================
# fzf with Nord colors (also styles the fzf-tab completion popup)
# =============================================================================

if command -v fzf &>/dev/null; then
    export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:-"\
--color=bg+:${THEME_HEX[bg_light]:-#3B4252},bg:${THEME_HEX[bg_main]:-#2E3440},spinner:${THEME_HEX[blue_light]:-#81A1C1},hl:${THEME_HEX[cyan]:-#88C0D0} \
--color=fg:${THEME_HEX[fg_main]:-#D8DEE9},header:${THEME_HEX[comment]:-#616E88},info:${THEME_HEX[blue_light]:-#81A1C1},pointer:${THEME_HEX[blue_light]:-#81A1C1} \
--color=marker:${THEME_HEX[green]:-#A3BE8C},fg+:${THEME_HEX[fg_bright]:-#ECEFF4},prompt:${THEME_HEX[blue_light]:-#81A1C1},hl+:${THEME_HEX[cyan]:-#88C0D0} \
--color=border:${THEME_HEX[comment]:-#4C566A},gutter:${THEME_HEX[bg_main]:-#2E3440} \
--layout=reverse --border=rounded"}"
fi

# =============================================================================
# ripgrep with Nord colors
# =============================================================================

if command -v rg &>/dev/null; then
    # Themed colors: match=green, path=cyan, line=yellow
    alias rg="rg --colors 'match:fg:${THEME_COLORS[green]:-143}' --colors 'match:style:bold' --colors 'path:fg:${THEME_COLORS[cyan]:-110}' --colors 'line:fg:${THEME_COLORS[yellow]:-221}'"
fi

# =============================================================================
# grep colors (fallback)
# =============================================================================

alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# GREP_COLORS/LS_COLORS come from the loaded theme (themes/*.zsh); only
# fall back here if no theme happened to set them.
# mt=match, fn=filename, ln=line number, se=separator
export GREP_COLORS="${GREP_COLORS:-mt=01;32:fn=36:ln=33:se=90}"

# =============================================================================
# grc (Generic Colouriser)
# =============================================================================

if [[ "$TERM" != dumb ]] && command -v grc &>/dev/null; then
    # Try to source grc's ZSH integration
    if [[ -f "/etc/grc.zsh" ]]; then
        source /etc/grc.zsh
    elif [[ -f "/usr/share/grc/grc.zsh" ]]; then
        source /usr/share/grc/grc.zsh
    else
        # Manually create aliases for common commands
        alias diff='grc --colour=auto diff'
        alias netstat='grc --colour=auto netstat'
        alias ping='grc --colour=auto ping'
        alias tail='grc --colour=auto tail'
        alias ps='grc --colour=auto ps'
        alias dig='grc --colour=auto dig'
        alias mount='grc --colour=auto mount'
        alias df='grc --colour=auto df'
        alias du='grc --colour=auto du'
        alias traceroute='grc --colour=auto traceroute'
        alias systemctl='grc --colour=auto systemctl'
        alias journalctl='grc --colour=auto journalctl'
    fi
fi

# =============================================================================
# LS_COLORS for traditional ls
# =============================================================================

# Comes from the loaded theme (themes/*.zsh); themed fallback only if unset.
export LS_COLORS="${LS_COLORS:-rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.gz=01;31:*.zip=01;31:*.jpg=01;35:*.png=01;35:*.mp4=01;35:*.mp3=00;36:*.flac=00;36}"

# =============================================================================
# Markdown Rendering (glow / mdcat / python-rich / bat fallback)
# =============================================================================

# Define fallback _render_markdown if config/09-ai-core.zsh was not loaded
if ! typeset -f _render_markdown &>/dev/null; then
    _nivuus_get_markdown_renderer() {
        if [[ -n "$NIVUUS_MARKDOWN_RENDERER" ]]; then
            print -r -- "$NIVUUS_MARKDOWN_RENDERER"
            return 0
        fi
        if [[ -n "$_NIVUUS_CACHED_MD_RENDERER" ]]; then
            print -r -- "$_NIVUUS_CACHED_MD_RENDERER"
            return 0
        fi
        local renderer="cat"
        if command -v glow &>/dev/null; then
            renderer="glow"
        elif command -v mdcat &>/dev/null; then
            renderer="mdcat"
        elif command -v python3 &>/dev/null && python3 -c 'import rich.markdown' &>/dev/null; then
            renderer="rich"
        elif command -v bat &>/dev/null; then
            renderer="bat"
        elif command -v batcat &>/dev/null; then
            renderer="batcat"
        fi
        typeset -g _NIVUUS_CACHED_MD_RENDERER="$renderer"
        print -r -- "$renderer"
    }

    _render_markdown() {
        if [[ "${ENABLE_MARKDOWN_RENDERING:-true}" == "false" || "$TERM" == "dumb" || ( ! -t 1 && "${FORCE_MARKDOWN_COLOR:-false}" != "true" ) ]]; then
            if [[ $# -gt 0 ]]; then
                if [[ -f "$1" && $# -eq 1 ]]; then
                    /bin/cat "$1"
                else
                    print -r -- "$*"
                fi
            else
                /bin/cat
            fi
            return $?
        fi

        local renderer=$(_nivuus_get_markdown_renderer)
        local bat_theme="${THEME_BAT_NAME:-Nord}"

        _pipe_to_renderer() {
            case "$renderer" in
                glow)
                    glow -s auto --pager=false - 2>/dev/null || glow - 2>/dev/null || /bin/cat
                    ;;
                mdcat)
                    mdcat - 2>/dev/null || /bin/cat
                    ;;
                rich)
                    python3 -m rich.markdown -c -y - 2>/dev/null || /bin/cat
                    ;;
                bat)
                    bat -l markdown --style="${BAT_STYLE:-plain}" --theme="$bat_theme" --paging=never --color=always 2>/dev/null || /bin/cat
                    ;;
                batcat)
                    batcat -l markdown --style="${BAT_STYLE:-plain}" --theme="$bat_theme" --paging=never --color=always 2>/dev/null || /bin/cat
                    ;;
                *)
                    /bin/cat
                    ;;
            esac
        }

        if [[ $# -gt 0 ]]; then
            if [[ -f "$1" && $# -eq 1 ]]; then
                case "$renderer" in
                    glow)
                        glow -s auto --pager=false "$1" 2>/dev/null || glow "$1" 2>/dev/null || /bin/cat "$1"
                        ;;
                    mdcat)
                        mdcat "$1" 2>/dev/null || /bin/cat "$1"
                        ;;
                    rich)
                        python3 -m rich.markdown -c -y "$1" 2>/dev/null || /bin/cat "$1"
                        ;;
                    bat)
                        bat -l markdown --style="${BAT_STYLE:-plain}" --theme="$bat_theme" --paging=never --color=always "$1" 2>/dev/null || /bin/cat "$1"
                        ;;
                    batcat)
                        batcat -l markdown --style="${BAT_STYLE:-plain}" --theme="$bat_theme" --paging=never --color=always "$1" 2>/dev/null || /bin/cat "$1"
                        ;;
                    *)
                        /bin/cat "$1"
                        ;;
                esac
            else
                print -r -- "$*" | _pipe_to_renderer
            fi
        else
            _pipe_to_renderer
        fi
    }
fi

# View markdown file or string in terminal
mdview() {
    _render_markdown "$@"
}
alias markdown='mdview'

# =============================================================================
# Help Function
# =============================================================================

colorhelp() {
    /bin/cat <<EOF
Nivuus Shell - Command Colorization (theme: ${NIVUUS_THEME:-nord})

Modern Tools:
  ls, ll, la        - eza with icons and git status
  tree              - eza tree view
  cat               - bat with syntax highlighting
  less              - bat as pager
  git diff          - delta with themed syntax
  mdview, markdown  - Terminal markdown rendering (glow/mdcat/rich/bat)
  img, showimg      - timg for terminal image display
  TAB completion    - fzf-tab popup, themed (see fzf below)

Colorized Commands (via grc):
  tail, ping, ps, df, du, netstat, dig
  systemctl, journalctl, traceroute

Configuration:
  eza:      \$EZA_COLORS
  bat:      \$BAT_THEME (${THEME_BAT_NAME:-Nord})
  grep:     \$GREP_COLORS
  delta:    Git config (\$THEME_DELTA_SYNTAX)
  markdown: \$ENABLE_MARKDOWN_RENDERING (true/false), \$NIVUUS_MARKDOWN_RENDERER (glow/mdcat/rich/bat/cat)
  fzf:      \$FZF_DEFAULT_OPTS (override before this file loads to customize)

Install missing tools:
  cargo install eza bat git-delta ripgrep
  sudo apt install grc timg glow
EOF
}
