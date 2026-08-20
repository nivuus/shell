# Journal des mutations et restauration.
# SEULE bibliothèque autorisée à écrire sur le système de fichiers.

nivuus_hash_file() {
    local path="$1"
    [ -f "$path" ] || { printf '%s\n' '-'; return 0; }
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$path" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$path" | cut -d' ' -f1
    else
        log_error "Aucun outil sha256 disponible (sha256sum ou shasum requis)"
        return 1
    fi
}

NIVUUS_TAB="$(printf '\t')"

nivuus_manifest_begin() {
    local mode="$1" install_dir="$2"
    : "${NIVUUS_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/nivuus}"
    NIVUUS_MANIFEST="$NIVUUS_STATE_DIR/manifest.tsv"
    NIVUUS_BACKUP_DIR="$NIVUUS_STATE_DIR/backups"
    NIVUUS_MANIFEST_TMP="$NIVUUS_STATE_DIR/.manifest.tsv.new"

    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        NIVUUS_MANIFEST_TMP="$(mktemp)"
    else
        mkdir -p "$NIVUUS_STATE_DIR" "$NIVUUS_BACKUP_DIR"
    fi

    printf '#nivuus-manifest v1\tinstalled_at=%s\tmode=%s\tdir=%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$mode" "$install_dir" \
        > "$NIVUUS_MANIFEST_TMP"
}

nivuus_manifest_record() {
    local action="$1" path="$2" hash="$3" ref="$4"
    case "$path" in
        *"$NIVUUS_TAB"*|*'
'*)
            log_error "Chemin non supporté (tabulation ou saut de ligne) : $path"
            return 1
            ;;
    esac
    printf '%s\t%s\t%s\t%s\n' "$action" "$path" "$hash" "$ref" >> "$NIVUUS_MANIFEST_TMP"
}

nivuus_manifest_commit() {
    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        rm -f "$NIVUUS_MANIFEST_TMP"
        return 0
    fi
    mv "$NIVUUS_MANIFEST_TMP" "$NIVUUS_MANIFEST"
}

nivuus_manifest_each() {
    local callback="$1"
    [ -f "$NIVUUS_MANIFEST" ] || return 0
    # tail -r n'existe pas partout ; on inverse avec sed.
    { grep -v '^#' "$NIVUUS_MANIFEST" || true; } | sed '1!G;h;$!d' | while IFS="$NIVUUS_TAB" read -r a p h r; do
        [ -n "$a" ] || continue
        "$callback" "$a" "$p" "$h" "$r"
    done
}

nivuus_store_backup() {
    local path="$1" hash
    hash="$(nivuus_hash_file "$path")"
    [ "$hash" = "-" ] && { printf '%s\n' '-'; return 0; }
    if [ -z "${NIVUUS_DRY_RUN:-}" ] && [ ! -f "$NIVUUS_BACKUP_DIR/$hash" ]; then
        cp -p "$path" "$NIVUUS_BACKUP_DIR/$hash"
    fi
    printf '%s\n' "$hash"
}

nivuus_mkdir_p() {
    local dir="$1" missing='' d
    d="$dir"
    # Collecte les niveaux manquants, du plus profond au plus superficiel.
    while [ ! -d "$d" ] && [ "$d" != "/" ] && [ -n "$d" ]; do
        missing="$missing$d
"
        d="$(dirname "$d")"
    done
    [ -n "$missing" ] || return 0

    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        log_dry "mkdir -p $dir"
    else
        mkdir -p "$dir"
    fi
    # Enregistrés du plus superficiel au plus profond (ordre de création),
    # afin que le rollback -- qui rejoue le journal à l'envers -- supprime
    # bien les répertoires les plus profonds avant leurs parents.
    printf '%s' "$missing" | sed '1!G;h;$!d' | while IFS= read -r level; do
        [ -n "$level" ] && nivuus_manifest_record MKDIR "$level" '-' '-'
    done
}

# Coeur partagé : $1 = source, $2 = destination.
_nivuus_place() {
    local src="$1" dst="$2" existed=0 backup='-' new_hash

    [ -f "$dst" ] && existed=1
    if [ "$existed" -eq 1 ] && [ "$(nivuus_hash_file "$src")" = "$(nivuus_hash_file "$dst")" ]; then
        return 0   # idempotent : rien à faire, rien à journaliser
    fi

    if [ "$existed" -eq 1 ]; then
        backup="$(nivuus_store_backup "$dst")" || return 1
    fi

    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        if [ "$existed" -eq 1 ]; then log_dry "modifierait $dst"; else log_dry "créerait $dst"; fi
        new_hash="$(nivuus_hash_file "$src")"
    else
        nivuus_mkdir_p "$(dirname "$dst")"
        cp -p "$src" "$dst"
        new_hash="$(nivuus_hash_file "$dst")"
    fi

    if [ "$existed" -eq 1 ]; then
        nivuus_manifest_record MODIFY "$dst" "$new_hash" "$backup"
    else
        nivuus_manifest_record CREATE "$dst" "$new_hash" '-'
    fi
}

nivuus_install_file() { _nivuus_place "$1" "$2"; }

nivuus_write_file() {
    local dst="$1" tmp result
    tmp="$(mktemp)"
    cat > "$tmp"
    _nivuus_place "$tmp" "$dst"
    result=$?
    rm -f "$tmp"
    return $result
}

nivuus_restore_entry() {
    local action="$1" path="$2" hash="$3" ref="$4" current

    case "$action" in
        CREATE)
            current="$(nivuus_hash_file "$path")"
            if [ "$current" = "-" ]; then
                return 0                      # déjà absent
            elif [ "$current" = "$hash" ]; then
                if [ -n "${NIVUUS_DRY_RUN:-}" ]; then log_dry "supprimerait $path"
                else rm -f "$path"; fi
            else
                log_warn "Conservé (modifié depuis l'installation) : $path"
            fi
            ;;
        MODIFY)
            current="$(nivuus_hash_file "$path")"
            if [ "$current" != "$hash" ]; then
                log_warn "Conservé (modifié depuis l'installation) : $path"
                log_warn "Sauvegarde d'origine disponible : $NIVUUS_BACKUP_DIR/$ref"
                return 0
            fi
            if [ ! -f "$NIVUUS_BACKUP_DIR/$ref" ]; then
                log_warn "Sauvegarde introuvable pour $path, fichier conservé"
                return 0
            fi
            if [ -n "${NIVUUS_DRY_RUN:-}" ]; then log_dry "restaurerait $path"
            else cp -p "$NIVUUS_BACKUP_DIR/$ref" "$path"; fi
            ;;
        MKDIR)
            if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
                log_dry "supprimerait le répertoire (si vide) $path"
            else
                rmdir "$path" 2>/dev/null || true   # non vide : on le laisse
            fi
            ;;
        CHSH)
            if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
                log_dry "restaurerait le shell de connexion : $ref"
            else
                log_info "Shell de connexion d'origine : $ref"
                log_info "Restaure-le avec : chsh -s $ref"
            fi
            ;;
        PKG)
            return 0    # jamais désinstallé
            ;;
    esac
    return 0
}

nivuus_manifest_rollback() {
    nivuus_manifest_each nivuus_restore_entry
}
