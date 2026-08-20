#!/usr/bin/env zsh
# =============================================================================
# Command Output Colorization - Nord Theme
# =============================================================================
# Modern tools + grc for colorized command outputs
# =============================================================================

# Only load once
[[ -n "${NIVUUS_COLORIZATION_LOADED}" ]] && return
export NIVUUS_COLORIZATION_LOADED=1

# Skip only if terminal is dumb (not if non-interactive)
[[ "$TERM" == "dumb" ]] && return

# =============================================================================
# Modern Tools - eza (ls replacement)
# =============================================================================

if command -v eza &>/dev/null; then
    # Nord-inspired colors for eza
    # Format: file_type=color_code
    export EZA_COLORS="reset:di=1;36:ln=1;35:so=1;32:pi=1;33:ex=1;31:bd=1;34:cd=1;34:su=37;41:sg=30;43:tw=30;42:ow=30;43"

    # Basic aliases (icons disabled for compatibility)
    alias ls='eza --color=always --group-directories-first'
    alias ll='eza -l --color=always --group-directories-first --git'
    alias la='eza -la --color=always --group-directories-first --git'
    alias tree='eza --tree --color=always'

    # Extended aliases
    alias l='eza -lbF --color=always --git'
    alias lt='eza --tree --level=2 --color=always'
fi

# =============================================================================
# bat (cat replacement with syntax highlighting)
# =============================================================================

if command -v bat &>/dev/null; then
    # Use bat with Nord theme
    export BAT_THEME="Nord"

    # Style options: plain (no decorations), auto (all decorations), numbers, grid, header
    # Customize with: export BAT_STYLE="numbers,grid"
    local bat_style="${BAT_STYLE:-plain}"

    alias cat="bat --theme=Nord --style=${bat_style}"
    alias less="bat --theme=Nord --style=${bat_style} --paging=always"

    # Set bat as default pager
    export PAGER="bat --theme=Nord --style=${bat_style} --paging=always"
    export MANPAGER="sh -c 'col -bx | bat --theme=Nord -l man -p'"

elif command -v batcat &>/dev/null; then
    # Debian/Ubuntu uses batcat (conflict with bacula)
    export BAT_THEME="Nord"

    local bat_style="${BAT_STYLE:-plain}"

    alias bat='batcat'
    alias cat="batcat --theme=Nord --style=${bat_style}"
    alias less="batcat --theme=Nord --style=${bat_style} --paging=always"

    export PAGER="batcat --theme=Nord --style=${bat_style} --paging=always"
    export MANPAGER="sh -c 'col -bx | batcat --theme=Nord -l man -p'"
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
    # Configure git to use delta with Nord theme
    _configure_delta_git() {
        git config --global core.pager delta
        git config --global interactive.diffFilter 'delta --color-only'
        git config --global delta.syntax-theme Nord
        git config --global delta.navigate true
        git config --global delta.line-numbers true
        git config --global delta.side-by-side false

        # Nord-specific colors for diffs
        git config --global delta.plus-style "syntax #2E3440"
        git config --global delta.plus-emph-style "syntax #A3BE8C"
        git config --global delta.minus-style "syntax #2E3440"
        git config --global delta.minus-emph-style "syntax #BF616A"
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
--color=bg+:#3B4252,bg:#2E3440,spinner:#81A1C1,hl:#88C0D0 \
--color=fg:#D8DEE9,header:#616E88,info:#81A1C1,pointer:#81A1C1 \
--color=marker:#A3BE8C,fg+:#ECEFF4,prompt:#81A1C1,hl+:#88C0D0 \
--color=border:#4C566A,gutter:#2E3440 \
--layout=reverse --border=rounded"}"
fi

# =============================================================================
# ripgrep with Nord colors
# =============================================================================

if command -v rg &>/dev/null; then
    # Nord colors: match=green, path=cyan, line=yellow
    alias rg="rg --colors 'match:fg:143' --colors 'match:style:bold' --colors 'path:fg:110' --colors 'line:fg:221'"
fi

# =============================================================================
# grep with Nord colors (fallback)
# =============================================================================

alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# Nord theme for grep
# mt=match, fn=filename, ln=line number, se=separator
export GREP_COLORS="mt=01;32:fn=36:ln=33:se=90"

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
# LS_COLORS for traditional ls (fallback)
# =============================================================================

# Nord-inspired LS_COLORS
export LS_COLORS='rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arc=01;31:*.arj=01;31:*.taz=01;31:*.lha=01;31:*.lz4=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.tzo=01;31:*.t7z=01;31:*.zip=01;31:*.z=01;31:*.dz=01;31:*.gz=01;31:*.lrz=01;31:*.lz=01;31:*.lzo=01;31:*.xz=01;31:*.zst=01;31:*.tzst=01;31:*.bz2=01;31:*.bz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.war=01;31:*.ear=01;31:*.sar=01;31:*.rar=01;31:*.alz=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:*.cab=01;31:*.wim=01;31:*.swm=01;31:*.dwm=01;31:*.esd=01;31:*.jpg=01;35:*.jpeg=01;35:*.mjpg=01;35:*.mjpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.webm=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.ogv=01;35:*.ogx=01;35:*.aac=00;36:*.au=00;36:*.flac=00;36:*.m4a=00;36:*.mid=00;36:*.midi=00;36:*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:*.oga=00;36:*.opus=00;36:*.spx=00;36:*.xspf=00;36:'

# =============================================================================
# Help Function
# =============================================================================

colorhelp() {
    /bin/cat <<'EOF'
Nivuus Shell - Command Colorization (Nord Theme)

Modern Tools:
  ls, ll, la        - eza with icons and git status
  tree              - eza tree view
  cat               - bat with syntax highlighting
  less              - bat as pager
  git diff          - delta with Nord theme
  img, showimg      - timg for terminal image display
  TAB completion    - fzf-tab popup with Nord theme (see fzf below)

Colorized Commands (via grc):
  tail, ping, ps, df, du, netstat, dig
  systemctl, journalctl, traceroute

Configuration:
  eza:     $EZA_COLORS
  bat:     $BAT_THEME (Nord)
  grep:    $GREP_COLORS
  delta:   Git config (Nord theme)
  fzf:     $FZF_DEFAULT_OPTS (override before this file loads to customize)

Install missing tools:
  cargo install eza bat git-delta ripgrep
  sudo apt install grc timg
EOF
}
