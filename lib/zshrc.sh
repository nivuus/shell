# shellcheck shell=bash
# lib/zshrc.sh
# Lecture, fusion et retrait du bloc Nivuus dans un .zshrc.
# Toutes les fonctions sont pures : elles écrivent sur stdout.

NIVUUS_BLOCK_BEGIN='# >>> nivuus shell >>>'
NIVUUS_BLOCK_END='# <<< nivuus shell <<<'

nivuus_zshrc_state() {
    local file="$1" has_begin=0 has_end=0
    [ -f "$file" ] || { printf 'missing\n'; return 0; }
    grep -qF "$NIVUUS_BLOCK_BEGIN" "$file" && has_begin=1
    grep -qF "$NIVUUS_BLOCK_END" "$file" && has_end=1
    if [ "$has_begin" -eq 1 ] && [ "$has_end" -eq 1 ]; then
        printf 'present\n'
    elif [ "$has_begin" -eq 0 ] && [ "$has_end" -eq 0 ]; then
        printf 'absent\n'
    else
        printf 'corrupt\n'
    fi
}

nivuus_zshrc_block() {
    local install_dir="$1"
    cat <<EOF
$NIVUUS_BLOCK_BEGIN
# Généré par Nivuus. Ne pas éditer : ce bloc est réécrit à chaque mise à jour.
# Pour tes personnalisations, crée ~/.zsh_local (il n'existe pas par défaut)
export NIVUUS_SHELL_DIR="$install_dir"
source "\$NIVUUS_SHELL_DIR/.zshrc"
$NIVUUS_BLOCK_END
EOF
}

nivuus_zshrc_strip() {
    local file="$1"
    [ -f "$file" ] || return 0
    # Un éditeur côté Windows (WSL) peut ré-enregistrer tout le fichier en
    # CRLF, marqueurs Nivuus compris. awk ne coupe les enregistrements que
    # sur \n : un \r de fin traînerait alors dans $0 et l'égalité stricte
    # avec les marqueurs (générés en LF) ne matcherait plus jamais -- le
    # bloc ne serait alors plus jamais retiré, dupliqué à chaque réinstall.
    # On compare donc une version de la ligne débarrassée de son \r final,
    # sans toucher au \r effectivement imprimé pour les lignes hors bloc.
    awk -v b="$NIVUUS_BLOCK_BEGIN" -v e="$NIVUUS_BLOCK_END" '
        { line = $0; sub(/\r$/, "", line) }
        line == b { skip = 1; next }
        line == e { skip = 0; next }
        !skip   { print }
    ' "$file"
}

# $3 (optional): where the block goes in a file that does not have one yet.
#   top    (default): at the head -- what follows wins, so the user's own
#                     config always overrides Nivuus (user mode, ~/.zshrc).
#   bottom          : at the tail -- after the distro defaults (system mode,
#                     /etc/zsh/zshrc), which Nivuus must override; every
#                     user's ~/.zshrc comes after it anyway.
nivuus_zshrc_merge() {
    local file="$1" install_dir="$2" position="${3:-top}" state
    state="$(nivuus_zshrc_state "$file")"
    case "$state" in
        corrupt)
            log_error "Marqueurs Nivuus incohérents dans $file (bloc ouvert sans fermeture)."
            log_error "Répare-le à la main ou restaure une sauvegarde ; Nivuus n'y touchera pas."
            return 1
            ;;
        missing)
            nivuus_zshrc_block "$install_dir"
            ;;
        present)
            # Replace the block, keep the rest as is -- at the requested
            # position, so a reinstall never moves the block.
            if [ "$position" = "bottom" ]; then
                nivuus_zshrc_strip "$file"
                nivuus_zshrc_block "$install_dir"
            else
                nivuus_zshrc_block "$install_dir"
                nivuus_zshrc_strip "$file"
            fi
            ;;
        absent)
            if [ "$position" = "bottom" ]; then
                cat "$file"
                # Guarantee a final newline if the file had none.
                [ -n "$(tail -c 1 "$file")" ] && printf '\n' || true
                nivuus_zshrc_block "$install_dir"
            else
                nivuus_zshrc_block "$install_dir"
                cat "$file"
                [ -n "$(tail -c 1 "$file")" ] && printf '\n' || true
            fi
            ;;
    esac
}

nivuus_zshrc_detect_framework() {
    local file="$1"
    [ -f "$file" ] || return 0
    grep -qF 'oh-my-zsh' "$file" && printf 'oh-my-zsh\n'
    grep -qF 'prezto' "$file" && printf 'prezto\n'
    grep -qF 'zinit' "$file" && printf 'zinit\n'
    grep -qF 'starship init' "$file" && printf 'starship\n'
    grep -qF 'powerlevel10k' "$file" && printf 'powerlevel10k\n'
    return 0
}
