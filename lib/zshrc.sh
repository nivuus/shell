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
    local install_dir="$1" minimal="${2:-}"
    printf '%s\n' "$NIVUUS_BLOCK_BEGIN"
    printf '%s\n' '# Généré par Nivuus. Ne pas éditer : ce bloc est réécrit à chaque mise à jour.'
    printf '%s\n' "# Pour tes personnalisations, crée ~/.zsh_local (il n'existe pas par défaut)"
    printf 'export NIVUUS_SHELL_DIR="%s"\n' "$install_dir"
    [ -n "$minimal" ] && printf '%s\n' 'export NIVUUS_MINIMAL=1'
    # La garde est émise dans TOUS les modes, pas seulement en mode paquet.
    # Trois raisons : elle couvre aussi le « rm -rf ~/.nivuus-shell » à la
    # main ; un bloc identique dans les quatre canaux est un bloc dont le
    # comportement est prouvé une fois (une variante par canal serait une
    # variante non testée) ; et son coût est un [ -r ] par ouverture de
    # shell, sous le seuil de mesure.
    #
    # Elle MASQUE une installation cassée au lieu de la signaler : c'est
    # « nivuus doctor » qui détecte « bloc présent, arbre absent » et donne
    # la commande de réparation. Silence au démarrage, diagnostic à la demande.
    printf '%s\n' '[ -r "$NIVUUS_SHELL_DIR/.zshrc" ] && source "$NIVUUS_SHELL_DIR/.zshrc"'
    printf '%s\n' "$NIVUUS_BLOCK_END"
    return 0
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

# La v3.0.0 écrivait dans ~/.zshrc trois lignes sans le moindre marqueur
# (git show v3.0.0:install.sh, lignes 257-261). nivuus_zshrc_state les
# classe donc « absent », et une installation de HEAD par-dessus AJOUTERAIT
# son bloc sans les retirer : le .zshrc sourcerait Nivuus deux fois.
#
# La reconnaissance est volontairement étroite -- en-tête exact, aucun bloc
# délimité présent, et trois formes de ligne précises. Un .zshrc écrit à la
# main qui contiendrait par hasard l'une de ces lignes n'est pas touché tant
# que l'en-tête manque.
NIVUUS_LEGACY_HEADER='# Nivuus Shell Configuration'

nivuus_zshrc_legacy_present() {
    local file="$1"
    [ -f "$file" ] || return 1
    [ "$(nivuus_zshrc_state "$file")" = "absent" ] || return 1
    grep -qxF "$NIVUUS_LEGACY_HEADER" "$file" || return 1
    grep -q '^export NIVUUS_SHELL_DIR=' "$file" || return 1
    grep -qF 'source "$NIVUUS_SHELL_DIR/.zshrc"' "$file" || return 1
    return 0
}

nivuus_zshrc_strip_legacy() {
    local file="$1"
    [ -f "$file" ] || return 0
    # Même précaution CRLF que nivuus_zshrc_strip : un .zshrc réenregistré
    # depuis Windows (WSL) ne doit pas échapper au retrait.
    awk -v h="$NIVUUS_LEGACY_HEADER" '
        { line = $0; sub(/\r$/, "", line) }
        line == h { next }
        line ~ /^export NIVUUS_SHELL_DIR=/ { next }
        line == "source \"$NIVUUS_SHELL_DIR/.zshrc\"" { next }
        { print }
    ' "$file"
}

nivuus_zshrc_merge() {
    local file="$1" install_dir="$2" minimal="${3:-}" state
    state="$(nivuus_zshrc_state "$file")"
    case "$state" in
        corrupt)
            log_error "Marqueurs Nivuus incohérents dans $file (bloc ouvert sans fermeture)."
            log_error "Répare-le à la main ou restaure une sauvegarde ; Nivuus n'y touchera pas."
            return 1
            ;;
        missing)
            nivuus_zshrc_block "$install_dir" "$minimal"
            ;;
        present)
            # Remplace le bloc, conserve le reste tel quel.
            nivuus_zshrc_block "$install_dir" "$minimal"
            nivuus_zshrc_strip "$file"
            ;;
        absent)
            if nivuus_zshrc_legacy_present "$file"; then
                # >&2 impératif : la sortie standard de cette fonction EST
                # le contenu du futur .zshrc. Un log_info non redirigé s'y
                # retrouverait écrit, puis survivrait à toutes les
                # réinstallations suivantes.
                log_info "Configuration héritée de la v3.0.0 détectée dans $file : elle est remplacée par le bloc délimité." >&2
                { nivuus_zshrc_block "$install_dir" "$minimal"; nivuus_zshrc_strip_legacy "$file"; }
                return 0
            fi
            nivuus_zshrc_block "$install_dir" "$minimal"
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
