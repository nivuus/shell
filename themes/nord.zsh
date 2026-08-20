#!/usr/bin/env zsh
# =============================================================================
# Nord Theme - Color Palette
# =============================================================================
# Official Nord color scheme for terminal
# https://www.nordtheme.com/
#
# This file implements the Nivuus Shell theme contract. Any file sourced via
# NIVUUS_THEME must define the same variables (see doc/PROMPT.md):
#   THEME_COLORS (assoc: ANSI-256 codes), THEME_HEX (assoc: hex codes),
#   THEME_PATH/THEME_SUCCESS/THEME_ERROR/THEME_SSH/THEME_ROOT/
#   THEME_GIT_PREFIX/THEME_GIT_BRANCH/THEME_ACCENT/THEME_MUTED/THEME_RESET,
#   THEME_BAT_NAME, THEME_DELTA_SYNTAX, LS_COLORS, GREP_COLORS
# =============================================================================

# Enable color support (if available)
if (( $+commands[autoload] )) || typeset -f autoload >/dev/null 2>&1; then
    autoload -U colors && colors
fi

# =============================================================================
# Hex Palette
# =============================================================================

typeset -gA THEME_HEX
THEME_HEX=(
    bg_main      "#2E3440"   # Polar Night - Background
    bg_light     "#3B4252"   # Polar Night - Lighter background
    bg_select    "#434C5E"   # Polar Night - Selection background
    comment      "#4C566A"   # Polar Night - Comments, invisibles

    fg_main      "#D8DEE9"   # Snow Storm - Default foreground
    fg_light     "#E5E9F0"   # Snow Storm - Lighter foreground
    fg_bright    "#ECEFF4"   # Snow Storm - Lightest foreground

    cyan_light   "#8FBCBB"   # Frost - Teal/Cyan light -> PATH
    cyan         "#88C0D0"   # Frost - Cyan -> GIT PREFIX
    blue_light   "#81A1C1"   # Frost - Blue light
    blue         "#5E81AC"   # Frost - Blue -> SSH HOSTNAME

    red          "#BF616A"   # Aurora - Red -> ERROR, GIT BRANCH, ROOT
    orange       "#D08770"   # Aurora - Orange
    yellow       "#EBCB8B"   # Aurora - Yellow -> FIREBASE/ACCENT
    green        "#A3BE8C"   # Aurora - Green -> SUCCESS
    magenta      "#B48EAD"   # Aurora - Purple/Magenta
)

# =============================================================================
# ZSH Color Mappings (for prompt usage)
# =============================================================================

# Convert hex to ANSI 256 colors (approximation)
typeset -gA THEME_COLORS
THEME_COLORS=(
    # Polar Night
    bg_main      "236"    # ~bg_main
    bg_light     "237"    # ~bg_light
    bg_select    "238"    # ~bg_select
    comment      "240"    # ~comment

    # Snow Storm
    fg_main      "253"    # ~fg_main
    fg_light     "254"    # ~fg_light
    fg_bright    "255"    # ~fg_bright

    # Frost
    cyan_light   "109"    # ~cyan_light (path)
    cyan         "110"    # ~cyan (git prefix)
    blue_light   "109"    # ~blue_light
    blue         "67"     # ~blue (ssh)

    # Aurora
    red          "167"    # ~red (error, branch, root)
    orange       "173"    # ~orange
    yellow       "221"    # ~yellow (firebase/accent)
    green        "143"    # ~green (success)
    magenta      "139"    # ~magenta
)

# =============================================================================
# Helper Functions
# =============================================================================

# Get theme color for ZSH prompt
theme_color() {
    echo "%F{${THEME_COLORS[$1]}}"
}

# Reset color
theme_reset() {
    echo "%f"
}

# =============================================================================
# Semantic Color Variables (for prompt usage)
# =============================================================================

export THEME_PATH=$(theme_color cyan_light)
export THEME_SUCCESS=$(theme_color green)
export THEME_ERROR=$(theme_color red)
export THEME_SSH=$(theme_color blue)
export THEME_ROOT=$(theme_color red)
export THEME_GIT_PREFIX=$(theme_color cyan)
export THEME_GIT_BRANCH=$(theme_color red)
export THEME_ACCENT=$(theme_color yellow)
export THEME_MUTED=$(theme_color comment)
export THEME_RESET=$(theme_reset)

# =============================================================================
# External Tool Theme Names
# =============================================================================

export THEME_BAT_NAME="Nord"
export THEME_DELTA_SYNTAX="Nord"

# =============================================================================
# LS_COLORS with Nord theme
# =============================================================================

export LS_COLORS='rs=0:di=01;34:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=34;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arc=01;31:*.arj=01;31:*.taz=01;31:*.lha=01;31:*.lz4=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.tzo=01;31:*.t7z=01;31:*.zip=01;31:*.z=01;31:*.dz=01;31:*.gz=01;31:*.lrz=01;31:*.lz=01;31:*.lzo=01;31:*.xz=01;31:*.zst=01;31:*.tzst=01;31:*.bz2=01;31:*.bz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.war=01;31:*.ear=01;31:*.sar=01;31:*.rar=01;31:*.alz=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:*.cab=01;31:*.wim=01;31:*.swm=01;31:*.dwm=01;31:*.esd=01;31:*.jpg=01;35:*.jpeg=01;35:*.mjpg=01;35:*.mjpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.webm=01;35:*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.ogv=01;35:*.ogx=01;35:*.aac=00;36:*.au=00;36:*.flac=00;36:*.m4a=00;36:*.mid=00;36:*.midi=00;36:*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:*.oga=00;36:*.opus=00;36:*.spx=00;36:*.xspf=00;36:'

# =============================================================================
# Grep Colors
# =============================================================================

export GREP_COLOR='1;32'    # Green for matches
export GREP_COLORS="mt=${THEME_COLORS[green]}:fn=${THEME_COLORS[cyan]}:ln=${THEME_COLORS[yellow]}:se=90"
