#!/usr/bin/env zsh
# =============================================================================
# Dracula Theme - Color Palette
# =============================================================================
# https://draculatheme.com/
#
# Implements the Nivuus Shell theme contract (see themes/nord.zsh for the
# full contract description, and doc/PROMPT.md for docs).
# =============================================================================

if (( $+commands[autoload] )) || typeset -f autoload >/dev/null 2>&1; then
    autoload -U colors && colors
fi

# =============================================================================
# Hex Palette
# =============================================================================

typeset -gA THEME_HEX
THEME_HEX=(
    bg_main      "#282A36"
    bg_light     "#343746"
    bg_select    "#44475A"
    comment      "#6272A4"

    fg_main      "#F8F8F2"
    fg_light     "#F8F8F2"
    fg_bright    "#FFFFFF"

    cyan_light   "#8BE9FD"
    cyan         "#8BE9FD"
    blue_light   "#6272A4"
    blue         "#6272A4"

    red          "#FF5555"
    orange       "#FFB86C"
    yellow       "#F1FA8C"
    green        "#50FA7B"
    magenta      "#FF79C6"
)

# =============================================================================
# ZSH Color Mappings (for prompt usage)
# =============================================================================

typeset -gA THEME_COLORS
THEME_COLORS=(
    bg_main      "236"
    bg_light     "237"
    bg_select    "238"
    comment      "61"

    fg_main      "253"
    fg_light     "254"
    fg_bright    "255"

    cyan_light   "117"
    cyan         "117"
    blue_light   "61"
    blue         "61"

    red          "203"
    orange       "215"
    yellow       "228"
    green        "84"
    magenta      "212"
)

# =============================================================================
# Helper Functions
# =============================================================================

theme_color() {
    echo "%F{${THEME_COLORS[$1]}}"
}

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

export THEME_BAT_NAME="Dracula"
export THEME_DELTA_SYNTAX="Dracula"

# =============================================================================
# LS_COLORS with Dracula theme
# =============================================================================

export LS_COLORS='rs=0:di=01;35:ln=01;36:mh=00:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:su=37;41:sg=30;43:ca=30;41:tw=30;42:ow=35;42:st=37;44:ex=01;32:*.tar=01;31:*.tgz=01;31:*.zip=01;31:*.gz=01;31:*.bz2=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.7z=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.png=01;35:*.svg=01;35:*.mp4=01;35:*.mkv=01;35:*.avi=01;35:*.mp3=00;36:*.flac=00;36:*.wav=00;36:*.ogg=00;36:'

# =============================================================================
# Grep Colors
# =============================================================================

export GREP_COLOR='1;32'
export GREP_COLORS="mt=${THEME_COLORS[green]}:fn=${THEME_COLORS[cyan]}:ln=${THEME_COLORS[yellow]}:se=90"
