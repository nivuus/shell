# shellcheck shell=bash
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

    # Marque la fin des entrées propres à CETTE installation posées avant
    # tout héritage (le bootstrap MKDIR ci-dessus, écrit avant que l'appelant
    # ait pu invoquer nivuus_manifest_inherit) -- distinct de la marque
    # post-inherit posée par nivuus_manifest_inherit elle-même, plus bas.
    # Entre les deux se trouvent, le cas échéant, les entrées HÉRITÉES d'une
    # installation précédente déjà committée : nivuus_manifest_abort doit les
    # laisser intactes. Voir le commentaire de nivuus_manifest_inherit pour
    # le schéma complet.
    NIVUUS_MANIFEST_WATERMARK_PRE_INHERIT="$(wc -l < "$NIVUUS_MANIFEST_TMP" 2>/dev/null | tr -d ' ')"
    : "${NIVUUS_MANIFEST_WATERMARK_PRE_INHERIT:=0}"
    # Valeur de repli SÛRE pour la marque post-inherit tant que
    # nivuus_manifest_inherit n'a pas (encore, ou jamais) tourné : identique
    # à PRE_INHERIT, donc "rien n'a été hérité" -- nivuus_manifest_abort
    # rejouera alors tout ce qui suit, ce qui est correct puisqu'il n'y a
    # justement rien d'hérité à protéger. Sans cette ligne, un appelant qui
    # oublierait d'invoquer l'héritage (ou l'inverse : qui hérite sans que la
    # marque n'ait jamais été (re)posée) laisserait
    # NIVUUS_MANIFEST_WATERMARK_POST_INHERIT à une valeur non définie ou
    # périmée d'un cycle begin précédent dans le même processus (les tests
    # unitaires sourcent la bibliothèque directement et peuvent appeler
    # nivuus_manifest_begin plusieurs fois) -- avec 0 comme secours le plus
    # probable, exactement la valeur qui fait rejouer tout l'historique :
    # le bug CRITICAL qu'on vient de fermer, en silence.
    NIVUUS_MANIFEST_WATERMARK_POST_INHERIT="$NIVUUS_MANIFEST_WATERMARK_PRE_INHERIT"
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

# Reprend les entrées d'un manifeste existant dans le manifeste en cours,
# pour qu'une réinstallation (idempotente sur les fichiers déjà en place) ne
# perde pas la trace de la première installation. Pose elle-même, à la fin
# et INCONDITIONNELLEMENT (même si $NIVUUS_MANIFEST n'existe pas -- rien à
# hériter, la marque reste simplement égale à PRE_INHERIT), la marque
# post-inherit : c'est l'unique fonction qui écrit des entrées héritées,
# donc l'unique endroit où "l'héritage vient de se terminer" peut être
# affirmé sans dépendre d'un appelant qui penserait à le signaler à part
# (une fonction séparée, nivuus_manifest_watermark_capture, existait ici et
# a été supprimée : un appelant qui oubliait de l'invoquer laissait la
# marque à sa valeur par défaut -- 0, ou une valeur périmée d'un cycle
# begin précédent dans le même processus -- qui fait justement tout
# rejouer sur abort, silencieusement).
#
# Avec la marque jumelle posée par nivuus_manifest_begin
# (NIVUUS_MANIFEST_WATERMARK_PRE_INHERIT), elle délimite la plage HÉRITÉE
# (donc à ne jamais rejouer sur abort) :
#
#   1..PRE_INHERIT        entrées propres à CETTE installation (bootstrap
#                          MKDIR de nivuus_manifest_begin), écrites AVANT que
#                          l'appelant n'ait pu invoquer l'héritage
#   PRE_INHERIT+1..POST    entrées héritées d'une installation précédente
#                          déjà committée (copiées verbatim ci-dessous) --
#                          À NE JAMAIS REJOUER
#   POST+1..fin            entrées propres à CETTE installation, écrites par
#                          les étapes qui suivent
#
# nivuus_manifest_abort ne rejoue que les deux zones "propres à cette
# installation" -- sans quoi annuler une réinstallation qui échoue
# rejouerait aussi tout ce qu'une précédente installation, déjà réussie et
# committée, avait posé.
nivuus_manifest_inherit() {
    if [ -f "$NIVUUS_MANIFEST" ]; then
        grep -v '^#' "$NIVUUS_MANIFEST" >> "$NIVUUS_MANIFEST_TMP" || true
    fi
    NIVUUS_MANIFEST_WATERMARK_POST_INHERIT="$(wc -l < "$NIVUUS_MANIFEST_TMP" 2>/dev/null | tr -d ' ')"
    : "${NIVUUS_MANIFEST_WATERMARK_POST_INHERIT:=0}"
}

nivuus_manifest_commit() {
    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        rm -f "$NIVUUS_MANIFEST_TMP"
        return 0
    fi
    mv "$NIVUUS_MANIFEST_TMP" "$NIVUUS_MANIFEST"
}

nivuus_manifest_each() {
    local callback="$1" manifest="${2:-$NIVUUS_MANIFEST}" seen
    [ -f "$manifest" ] || return 0
    # Exposé pour _nivuus_zwc_preserved, appelée depuis nivuus_restore_entry
    # (le callback ci-dessous) : elle doit consulter EXACTEMENT le fichier
    # en cours de rejeu, pas un autre manifeste qui traînerait en variable
    # globale.
    _NIVUUS_ACTIVE_MANIFEST="$manifest"
    seen="$(mktemp)"
    # tail -r n'existe pas partout ; on inverse avec sed.
    # Un chemin peut apparaître plusieurs fois (installations répétées héritées
    # via nivuus_manifest_inherit) : on ne rejoue que l'entrée la plus récente
    # (la première rencontrée une fois le fichier inversé) pour chaque chemin.
    { grep -v '^#' "$manifest" || true; } | sed '1!G;h;$!d' | while IFS="$NIVUUS_TAB" read -r a p h r; do
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

# Cherche, dans le manifeste en cours de construction (déjà peuplé par
# nivuus_manifest_inherit avec les entrées d'une installation précédente),
# la première entrée MODIFY pour ce chemin -- la plus ancienne, donc celle
# qui pointe vers la sauvegarde d'origine de l'utilisateur, avant que
# Nivuus n'y touche jamais. Vide si aucune.
# Un .zwc est-il journalisé comme PRESERVE (préexistant à Nivuus, jamais à
# supprimer) pour ce chemin exact ? Consulte $_NIVUUS_ACTIVE_MANIFEST posé
# par nivuus_manifest_each pendant un rollback/abort, ou $NIVUUS_MANIFEST_TMP
# pendant une installation (où _nivuus_place écrit ces marqueurs). Rien de
# trouvable ne veut jamais dire "préservé" par défaut : seule une entrée
# PRESERVE explicite protège.
_nivuus_zwc_preserved() {
    local zwc="$1" file="${_NIVUUS_ACTIVE_MANIFEST:-$NIVUUS_MANIFEST_TMP}"
    [ -n "$file" ] && [ -f "$file" ] || return 1
    awk -F"$NIVUUS_TAB" -v p="$zwc" \
        '$1 == "PRESERVE" && $2 == p { found=1 } END { exit !found }' \
        "$file" 2>/dev/null
}

_nivuus_prior_modify_ref() {
    local path="$1"
    [ -f "$NIVUUS_MANIFEST_TMP" ] || return 0
    awk -F"$NIVUUS_TAB" -v p="$path" \
        '$1 == "MODIFY" && $2 == p { print $4; exit }' \
        "$NIVUUS_MANIFEST_TMP" 2>/dev/null
}

# Nivuus a-t-il DÉJÀ touché ce chemin -- CREATE ou MODIFY, à cette
# installation ou à une précédente héritée -- avant l'écriture en cours ?
# Sert à distinguer un .zwc réellement préexistant à Nivuus (aucune entrée
# antérieure : premier contact) d'un .zwc compilé par une session Nivuus
# après un CREATE/MODIFY précédent (une entrée existe déjà : ce n'est pas
# notre première visite, donc le .zwc trouvé maintenant est forcément le
# nôtre, jamais celui de l'utilisateur).
_nivuus_prior_entry_exists() {
    local path="$1"
    [ -f "$NIVUUS_MANIFEST_TMP" ] || return 1
    awk -F"$NIVUUS_TAB" -v p="$path" \
        '($1 == "CREATE" || $1 == "MODIFY") && $2 == p { found=1 } END { exit !found }' \
        "$NIVUUS_MANIFEST_TMP" 2>/dev/null
}

# Coeur partagé : $1 = source, $2 = destination.
_nivuus_place() {
    local src="$1" dst="$2" existed=0 backup='-' new_hash prior_ref

    [ -f "$dst" ] && existed=1
    if [ "$existed" -eq 1 ] && [ "$(nivuus_hash_file "$src")" = "$(nivuus_hash_file "$dst")" ]; then
        return 0   # idempotent : rien à faire, rien à journaliser
    fi

    # [ -f "$dst" ] suit les liens : un utilisateur stow/chezmoi dont
    # ~/.zshrc est un symlink verrait sa cible réécrite en place, hors
    # $HOME et hors de toute empreinte -- sans jamais le savoir. Le contenu
    # reste restauré à la désinstallation (ce n'est pas une perte de
    # données), mais c'est une mutation non annoncée d'un fichier
    # potentiellement versionné : au minimum, prévenir en nommant la vraie
    # cible.
    if [ -L "$dst" ]; then
        log_warn "$dst est un lien symbolique vers $(readlink "$dst") : Nivuus écrit à travers, dans ce fichier réel."
    fi

    # zsh peut compiler n'importe quel fichier qu'il source en un .zwc à
    # côté. Si un .zwc est DÉJÀ là AU TOUT PREMIER contact de Nivuus avec
    # $dst (aucune entrée CREATE/MODIFY antérieure, cette installation ou
    # une précédente héritée), il préexistait à Nivuus (l'utilisateur avait
    # zcompilé son propre fichier, par exemple) : ce n'est pas à nous de le
    # supprimer un jour. On le journalise comme PRESERVE avant d'écrire quoi
    # que ce soit, pour que nivuus_restore_entry (CREATE/MODIFY) sache plus
    # tard ne jamais y toucher.
    #
    # Si Nivuus a DÉJÀ touché $dst avant (CREATE ou MODIFY antérieur), un
    # .zwc trouvé maintenant ne peut être QUE le nôtre -- compilé par une
    # session zsh entre-temps (config/99-cleanup.zsh, config/03-completion.zsh)
    # -- jamais celui de l'utilisateur : sans ce garde-fou, une réinstallation
    # qui change le contenu (upgrade, nouveau --prefix, etc.) marquerait à
    # tort ce .zwc Nivuus comme intouchable pour toujours, exactement
    # l'inverse de ce que "ne supprime que ce que Nivuus a créé" demande.
    if [ -f "$dst.zwc" ] && ! _nivuus_zwc_preserved "$dst.zwc" \
        && ! _nivuus_prior_entry_exists "$dst"; then
        nivuus_manifest_record PRESERVE "$dst.zwc" '-' '-'
    fi

    if [ "$existed" -eq 1 ]; then
        # Une réinstallation ne doit JAMAIS écraser la sauvegarde d'origine :
        # si une entrée MODIFY existe déjà pour ce chemin, $dst est une
        # version déjà "nivuusée" (potentiellement éditée par l'utilisateur
        # depuis), pas le fichier pristine. En sauvegarder une nouvelle copie
        # perdrait la seule trace du contenu d'avant Nivuus.
        prior_ref="$(_nivuus_prior_modify_ref "$dst")"
        if [ -n "$prior_ref" ] && [ "$prior_ref" != "-" ]; then
            backup="$prior_ref"
        else
            backup="$(nivuus_store_backup "$dst")" || return 1
        fi
    fi

    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
        if [ "$existed" -eq 1 ]; then log_dry "modifierait $dst"; else log_dry "créerait $dst"; fi
        new_hash="$(nivuus_hash_file "$src")"
    else
        nivuus_mkdir_p "$(dirname "$dst")"
        cp -p "$src" "$dst" || return 1
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

# Trace une entrée que le rollback n'a PAS pu appliquer (fichier divergé,
# sauvegarde manquante...) pour que l'appelant (bin/nivuus) puisse :
#   - garder le manifeste (le rejouer plus tard reste possible) plutôt que
#     le supprimer alors qu'il décrit encore un état non résolu ;
#   - épargner, lors d'un --purge, toute sauvegarde encore référencée par
#     une entrée non appliquée (sinon le pointeur qu'on vient d'afficher à
#     l'utilisateur devient un mensonge quelques lignes plus loin).
# Sans effet si l'appelant n'a pas préparé NIVUUS_ROLLBACK_SURVIVORS.
_nivuus_record_survivor() {
    [ -n "${NIVUUS_ROLLBACK_SURVIVORS:-}" ] || return 0
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$NIVUUS_ROLLBACK_SURVIVORS"
}

# Épargne une sauvegarde d'un --purge sans pour autant garder toute son
# entrée MODIFY comme "survivante" (voir _nivuus_record_survivor) : utilisé
# quand l'entrée a été résolue autrement (ex : bloc Nivuus retiré
# chirurgicalement d'un fichier divergé) mais que le message qu'on vient
# d'afficher pointe encore vers cette sauvegarde -- elle doit donc rester
# vraie. Sans effet si l'appelant n'a pas préparé NIVUUS_KEPT_BACKUP_REFS.
_nivuus_keep_backup_ref() {
    [ -n "${NIVUUS_KEPT_BACKUP_REFS:-}" ] || return 0
    [ -n "$1" ] && [ "$1" != "-" ] && printf '%s\n' "$1" >> "$NIVUUS_KEPT_BACKUP_REFS"
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
                    # doit pas survivre au fichier source qu'il compile. Mais
                    # s'il préexistait à Nivuus (_nivuus_zwc_preserved,
                    # journalisé par _nivuus_place à l'installation), ce
                    # n'est PAS le nôtre : on ne le supprime que s'il n'est
                    # pas marqué préservé.
                    [ -f "$path.zwc" ] && ! _nivuus_zwc_preserved "$path.zwc" && rm -f "$path.zwc"
                fi
            else
                log_warn "Conservé (modifié depuis l'installation) : $path"
                _nivuus_record_survivor "$action" "$path" "$hash" "$ref"
            fi
            ;;
        MODIFY)
            current="$(nivuus_hash_file "$path")"
            if [ "$current" != "$hash" ]; then
                # Le fichier a divergé depuis l'installation (l'utilisateur
                # l'a édité) : on ne veut ni écraser son édition avec une
                # restauration complète, ni le laisser tel quel si c'est
                # $HOME/.zshrc -- le bloc Nivuus qu'il contient encore
                # sourcerait un répertoire qu'on est en train de supprimer,
                # cassant le prochain démarrage du shell. S'il s'agit d'un
                # fichier à bloc délimité (ex : .zshrc) et que ce bloc est
                # proprement présent, on le retire chirurgicalement --
                # nivuus_zshrc_strip existe précisément pour ça -- et on
                # laisse le reste, y compris les lignes ajoutées par
                # l'utilisateur, strictement intact. Dépendance douce (via
                # command -v) : lib/manifest.sh reste utilisable seule (voir
                # les tests unitaires qui la sourcent sans lib/zshrc.sh) et
                # ne connaît rien du format .zshrc au-delà de ce cas précis.
                if command -v nivuus_zshrc_state >/dev/null 2>&1 \
                    && [ "$(nivuus_zshrc_state "$path")" = "present" ]; then
                    if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
                        log_dry "retirerait le bloc Nivuus de $path (contenu divergé, le reste est conservé)"
                    else
                        local stripped
                        stripped="$(mktemp)"
                        nivuus_zshrc_strip "$path" > "$stripped"
                        # Écrit le contenu réduit DANS le fichier existant
                        # (redirection, pas mv) pour préserver ses
                        # permissions et son inode -- exactement ce que ferait
                        # une édition normale de ce fichier par l'utilisateur.
                        cat "$stripped" > "$path"
                        rm -f "$stripped"
                        touch "$path"
                        [ -f "$path.zwc" ] && ! _nivuus_zwc_preserved "$path.zwc" && rm -f "$path.zwc"
                    fi
                    log_warn "$path a été modifié depuis l'installation : seul le bloc Nivuus en a été retiré, tes propres lignes sont intactes."
                    if [ -f "$NIVUUS_BACKUP_DIR/$ref" ] && [ "$ref" != "-" ]; then
                        _nivuus_keep_backup_ref "$ref"
                        log_warn "Sauvegarde d'origine (avant Nivuus) toujours disponible : $NIVUUS_BACKUP_DIR/$ref"
                    fi
                    return 0    # résolu : ce n'est pas un survivant
                fi
                log_warn "Conservé (modifié depuis l'installation) : $path"
                log_warn "Sauvegarde d'origine disponible : $NIVUUS_BACKUP_DIR/$ref"
                _nivuus_record_survivor "$action" "$path" "$hash" "$ref"
                return 0
            fi
            if [ ! -f "$NIVUUS_BACKUP_DIR/$ref" ]; then
                log_warn "Sauvegarde introuvable pour $path, fichier conservé"
                _nivuus_record_survivor "$action" "$path" "$hash" "$ref"
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
                [ -f "$path.zwc" ] && ! _nivuus_zwc_preserved "$path.zwc" && rm -f "$path.zwc"
            fi
            ;;
        MKDIR)
            if [ -n "${NIVUUS_DRY_RUN:-}" ]; then
                log_dry "supprimerait le répertoire (si vide) $path"
            else
                # Non vide : on le laisse. $NIVUUS_STATE_DIR (et ses parents)
                # échouent systématiquement ici -- le manifeste et les
                # sauvegardes qu'on est en train de lire y vivent encore --
                # ce n'est pas une divergence à tracer : bin/nivuus rejoue
                # ces niveaux une seconde fois une fois l'état supprimé.
                rmdir "$path" 2>/dev/null || true
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
        PRESERVE)
            return 0    # marqueur pur : un .zwc préexistant, jamais touché
            ;;
        *)
            log_warn "Action de manifeste inconnue, ignorée : $action ($path)"
            ;;
    esac
    return 0
}

# Rejoue le manifeste à l'envers. Si l'appelant a défini
# NIVUUS_ROLLBACK_SURVIVORS (chemin d'un fichier existant, vide ou non), les
# entrées que le rollback n'a pas pu appliquer y sont écrites au format TSV
# du manifeste -- l'appelant peut alors les rejouer dans un nouveau manifeste
# plutôt que de perdre leur trace (voir _nivuus_record_survivor).
nivuus_manifest_rollback() {
    nivuus_manifest_each nivuus_restore_entry "$NIVUUS_MANIFEST"
}

# Annule une installation interrompue entre begin et commit (dépendance
# manquante, .zshrc corrompu, disque plein...). $NIVUUS_MANIFEST_TMP décrit
# tout ce que les étapes qui ont réussi ont écrit sur le disque avant
# l'échec -- MAIS aussi, si nivuus_manifest_inherit a tourné (réinstallation),
# tout ce qu'une précédente installation RÉUSSIE et déjà committée avait
# posé. Rejouer le fichier en entier annulerait donc cette installation
# précédente, saine, simplement parce que la nouvelle a échoué -- un
# utilisateur qui relance `install` après avoir cassé son .zshrc perdrait
# l'installation qui marchait.
#
# On ne rejoue donc que les deux zones qui appartiennent à CETTE
# installation (voir le schéma dans nivuus_manifest_inherit) : les entrées
# 1..PRE_INHERIT (bootstrap MKDIR posé par nivuus_manifest_begin avant que
# l'appelant n'ait pu hériter) et POST_INHERIT+1..fin (tout ce que les
# étapes ont écrit ensuite). La plage du milieu -- ce que
# nivuus_manifest_inherit a copié verbatim -- décrit une installation
# antérieure déjà réussie et n'est jamais rejouée. Les deux marques ont un
# repli par défaut sûr (0, ou PRE_INHERIT pour POST -- posé par
# nivuus_manifest_begin ET par nivuus_manifest_inherit, jamais laissé à la
# charge d'un appelant qui pourrait l'oublier) : sans elles, tout est
# rejoué, le cas d'une première installation sans manifeste préexistant à
# hériter.
nivuus_manifest_abort() {
    [ -f "$NIVUUS_MANIFEST_TMP" ] || return 0
    local pre="${NIVUUS_MANIFEST_WATERMARK_PRE_INHERIT:-0}" \
          post="${NIVUUS_MANIFEST_WATERMARK_POST_INHERIT:-0}" \
          new_entries
    new_entries="$(mktemp)"
    {
        [ "$pre" -gt 0 ] && sed -n "1,${pre}p" "$NIVUUS_MANIFEST_TMP"
        tail -n "+$((post + 1))" "$NIVUUS_MANIFEST_TMP"
    } > "$new_entries"
    # $NIVUUS_MANIFEST_TMP lui-même vit sous un des répertoires MKDIR qu'il
    # décrit (typiquement $NIVUUS_STATE_DIR) : tant qu'il existe, un rmdir
    # sur ce niveau échoue "non vide". On capture donc les niveaux (parmi les
    # seules entrées nouvelles) avant de rejouer, on le supprime, puis on
    # retente ces niveaux -- exactement le même contournement que
    # cmd_uninstall --purge applique au manifeste committé et à ses
    # sauvegardes.
    local levels
    levels="$(awk -F"$NIVUUS_TAB" '$1=="MKDIR"{print $2}' "$new_entries" 2>/dev/null || true)"
    nivuus_manifest_each nivuus_restore_entry "$new_entries"
    rm -f "$new_entries" "$NIVUUS_MANIFEST_TMP"
    if [ -n "$levels" ]; then
        printf '%s\n' "$levels" | sed '1!G;h;$!d' | while IFS= read -r level; do
            [ -z "$level" ] && continue
            rmdir "$level" 2>/dev/null || true
        done
    fi
}
