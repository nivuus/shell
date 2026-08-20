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
# Mets tes personnalisations dans ~/.zsh_local
export NIVUUS_SHELL_DIR="$install_dir"
source "\$NIVUUS_SHELL_DIR/.zshrc"
$NIVUUS_BLOCK_END
EOF
}

nivuus_zshrc_strip() {
    local file="$1"
    [ -f "$file" ] || return 0
    awk -v b="$NIVUUS_BLOCK_BEGIN" -v e="$NIVUUS_BLOCK_END" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        !skip   { print }
    ' "$file"
}

nivuus_zshrc_merge() {
    local file="$1" install_dir="$2" state
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
            # Remplace le bloc, conserve le reste tel quel.
            nivuus_zshrc_block "$install_dir"
            nivuus_zshrc_strip "$file"
            ;;
        absent)
            nivuus_zshrc_block "$install_dir"
            cat "$file"
            # Garantit une newline finale si le fichier n'en avait pas.
            [ -n "$(tail -c 1 "$file")" ] && printf '\n' || true
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
