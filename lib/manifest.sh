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

# Collecte les niveaux manquants pour atteindre $1, du plus profond au plus
# superficiel (un chemin par ligne). Ne crée rien : pure lecture, partagée
# entre nivuus_mkdir_p et nivuus_manifest_begin pour ne pas dupliquer la
# logique de détection.
_nivuus_missing_levels() {
    local d="$1" missing=''
    while [ ! -d "$d" ] && [ "$d" != "/" ] && [ -n "$d" ]; do
        missing="$missing$d
"
        d="$(dirname "$d")"
    done
    printf '%s' "$missing"
}

nivuus_manifest_begin() {
    local mode="$1" install_dir="$2" missing=''
    : "${NIVUUS_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/nivuus}"
    NIVUUS_MANIFEST="$NIVUUS_STATE_DIR/manifest.tsv"
    NIVUUS_BACKUP_DIR="$NIVUUS_STATE_DIR/backups"
    NIVUUS_MANIFEST_TMP="$NIVUUS_STATE_DIR/.manifest.tsv.new"

    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        NIVUUS_MANIFEST_TMP="$(mktemp)"
    else
        # $NIVUUS_BACKUP_DIR est un enfant de $NIVUUS_STATE_DIR : relever ses
        # niveaux manquants couvre aussi ceux de $NIVUUS_STATE_DIR et de ses
        # parents XDG (~/.local/state, ~/.local). C'est la SEULE mutation du
        # projet qui doit précéder l'ouverture du manifeste ; on journalise
        # donc ces niveaux nous-mêmes juste après, comme nivuus_mkdir_p le
        # ferait, pour qu'un uninstall --purge ne supprime jamais un
        # répertoire XDG préexistant.
        missing="$(_nivuus_missing_levels "$NIVUUS_BACKUP_DIR")"
        mkdir -p "$NIVUUS_BACKUP_DIR"
    fi

    printf '#nivuus-manifest v1\tinstalled_at=%s\tmode=%s\tdir=%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$mode" "$install_dir" \
        > "$NIVUUS_MANIFEST_TMP"

    if [ -n "$missing" ]; then
        # Du plus superficiel au plus profond (ordre de création), pour que
        # le rollback -- qui rejoue le journal à l'envers -- supprime bien
        # les répertoires les plus profonds avant leurs parents.
        # $(...) a tronqué le(s) saut(s) de ligne finaux de $missing : si un
        # seul niveau manquait, la chaîne capturée n'en contient plus aucun et
        # le "while read" ci-dessous perdrait cette unique ligne (son premier
        # read renverrait un statut non nul sans exécuter le corps). On
        # rajoute donc un saut de ligne terminal avant de dépiler.
        printf '%s\n' "$missing" | sed '1!G;h;$!d' | while IFS= read -r level; do
            [ -n "$level" ] && nivuus_manifest_record MKDIR "$level" '-' '-'
        done
    fi
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

nivuus_manifest_inherit() {
    # Reprend les entrées d'un manifeste existant dans le manifeste en cours,
    # pour qu'une réinstallation (idempotente sur les fichiers déjà en place)
    # ne perde pas la trace de la première installation.
    [ -f "$NIVUUS_MANIFEST" ] || return 0
    grep -v '^#' "$NIVUUS_MANIFEST" >> "$NIVUUS_MANIFEST_TMP" || true
}

nivuus_manifest_commit() {
    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        rm -f "$NIVUUS_MANIFEST_TMP"
        return 0
    fi
    mv "$NIVUUS_MANIFEST_TMP" "$NIVUUS_MANIFEST"
}

nivuus_manifest_each() {
    local callback="$1" seen
    [ -f "$NIVUUS_MANIFEST" ] || return 0
    seen="$(mktemp)"
    # tail -r n'existe pas partout ; on inverse avec sed.
    # Un chemin peut apparaître plusieurs fois (installations répétées héritées
    # via nivuus_manifest_inherit) : on ne rejoue que l'entrée la plus récente
    # (la première rencontrée une fois le fichier inversé) pour chaque chemin.
    { grep -v '^#' "$NIVUUS_MANIFEST" || true; } | sed '1!G;h;$!d' | while IFS="$NIVUUS_TAB" read -r a p h r; do
        [ -n "$a" ] || continue
        if grep -qxF "$p" "$seen" 2>/dev/null; then continue; fi
        printf '%s\n' "$p" >> "$seen"
        "$callback" "$a" "$p" "$h" "$r"
    done
    rm -f "$seen"
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
    local dir="$1" missing
    missing="$(_nivuus_missing_levels "$dir")"
    [ -n "$missing" ] || return 0

    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        log_dry "mkdir -p $dir"
    else
        mkdir -p "$dir"
    fi
    # Enregistrés du plus superficiel au plus profond (ordre de création),
    # afin que le rollback -- qui rejoue le journal à l'envers -- supprime
    # bien les répertoires les plus profonds avant leurs parents. $(...) a
    # tronqué le saut de ligne final (voir nivuus_manifest_begin) : on le
    # rajoute pour ne jamais perdre le cas d'un seul niveau manquant.
    printf '%s\n' "$missing" | sed '1!G;h;$!d' | while IFS= read -r level; do
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
                if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
                    log_dry "supprimerait $path"
                else
                    rm -f "$path"
                    # zsh peut avoir compilé ce fichier pendant la session
                    # (config/99-cleanup.zsh, config/03-completion.zsh) sans
                    # jamais passer par le manifeste : un .zwc orphelin ne
                    # doit pas survivre au fichier source qu'il compile. On
                    # ne le supprime que parce que le fichier source lui-même
                    # vient d'être traité (jamais à l'aveugle).
                    [ -f "$path.zwc" ] && rm -f "$path.zwc"
                fi
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
            if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
                log_dry "restaurerait $path"
            else
                cp -p "$NIVUUS_BACKUP_DIR/$ref" "$path"
                # cp -p préserve l'horodatage d'origine (antérieur à
                # l'installation), qui peut être plus vieux que le .zwc écrit
                # pendant la session : zsh préférerait alors le bytecode
                # compilé -- qui source encore un répertoire que l'uninstall
                # vient de supprimer -- au fichier texte restauré. On force
                # donc le fichier restauré à être strictement plus récent que
                # tout .zwc frère, et on supprime ce dernier : son contenu ne
                # correspond de toute façon plus au fichier restauré.
                touch "$path"
                [ -f "$path.zwc" ] && rm -f "$path.zwc"
            fi
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
        *)
            log_warn "Action de manifeste inconnue, ignorée : $action ($path)"
            ;;
    esac
    return 0
}

nivuus_manifest_rollback() {
    nivuus_manifest_each nivuus_restore_entry
}
