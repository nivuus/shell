#!/usr/bin/env zsh
# ============================================================================
# Nivuus Shell - Auto-Update System (Release-Based)
# ============================================================================
# Manages automatic updates from GitHub Releases
# - Weekly automatic update checks (configurable)
# - Automatic installation with backup
# - Manual update via 'nivuus-update' command
# - Checksum verification for security
# ============================================================================

# Configuration variables (can be overridden in .zsh_local)
: ${ENABLE_AUTOUPDATE:=true}
: ${AUTOUPDATE_CHECK_FREQUENCY_DAYS:=7}
: ${NIVUUS_GITHUB_REPO:=maximeallanic/nivuus-shell}
: ${NIVUUS_GITHUB_API:=https://api.github.com}
: ${NIVUUS_VERIFY_CHECKSUMS:=true}

# Last update check timestamp file
NIVUUS_UPDATE_CHECK_FILE="$HOME/.nivuus-shell-last-update-check"

# Version file to track installed version
NIVUUS_VERSION_FILE="$NIVUUS_SHELL_DIR/.version"

# ============================================================================
# Helper Functions
# ============================================================================

# Detect a development checkout (git working copy).
# The release-based updater is destructive (it wipes $NIVUUS_SHELL_DIR),
# so it must NEVER run against a git checkout or it would delete .git and
# any uncommitted work.
_nivuus_is_dev_checkout() {
    [[ -d "$NIVUUS_SHELL_DIR/.git" ]] || [[ -f "$NIVUUS_SHELL_DIR/.git" ]]
}

# Detect a package-manager install (spec § 1.2).
#
# Source de vérité : $NIVUUS_SHELL_DIR/.nivuus-origin, posé par la recette de
# paquet. Son ABSENCE vaut « source » : c'est le comportement d'aujourd'hui,
# mot pour mot, donc une régression ici ne peut pas atteindre le canal
# principal.
#
# Volontairement réimplémenté ici plutôt que sourcé depuis lib/origin.sh :
# aucun module de config/ ne source lib/*.sh sur le chemin de démarrage, et
# le budget de 300 ms est un test qui bloque les PR. Coût ajouté quand le
# marqueur est absent : un [[ -r ]], et rien d'autre -- pas de fork.
_nivuus_origin() {
    local f="$NIVUUS_SHELL_DIR/.nivuus-origin" v
    [[ -r "$f" ]] || { print -r -- source; return 0 }
    v="${$(sed -n 's/^origin=//p' "$f" 2>/dev/null | head -n1):-source}"
    [[ "$v" == "package" ]] && { print -r -- package; return 0 }
    print -r -- source
}

_nivuus_origin_channel() {
    local f="$NIVUUS_SHELL_DIR/.nivuus-origin" v
    [[ -r "$f" ]] || { print -r -- unknown; return 0 }
    v="${$(sed -n 's/^channel=//p' "$f" 2>/dev/null | head -n1):-unknown}"
    print -r -- "$v"
}

_nivuus_origin_package_name() {
    local f="$NIVUUS_SHELL_DIR/.nivuus-origin" v
    [[ -r "$f" ]] || { print -r -- nivuus-shell; return 0 }
    v="${$(sed -n 's/^package=//p' "$f" 2>/dev/null | head -n1):-nivuus-shell}"
    print -r -- "$v"
}

_nivuus_origin_package_version() {
    local f="$NIVUUS_SHELL_DIR/.nivuus-origin" v
    [[ -r "$f" ]] || return 1
    v="$(sed -n 's/^version=//p' "$f" 2>/dev/null | head -n1)"
    [[ -n "$v" ]] || return 1
    print -r -- "$v"
}

# Jumelle de _nivuus_is_dev_checkout : deux gardes de même nature, au même
# endroit, pour la même raison -- l'updater est destructif, il ne doit pas
# s'exécuter là où il détruirait autre chose que lui-même. La symétrie
# garantit qu'on ne peut pas corriger l'une en oubliant l'autre.
_nivuus_is_package_install() { [[ "$(_nivuus_origin)" == "package" ]] }

# Get current installed version
_nivuus_current_version() {
    if [[ -f "$NIVUUS_VERSION_FILE" ]]; then
        cat "$NIVUUS_VERSION_FILE" 2>/dev/null
    elif [[ -f "$NIVUUS_SHELL_DIR/package.json" ]]; then
        # Fallback to package.json
        grep '"version"' "$NIVUUS_SHELL_DIR/package.json" | sed 's/.*"version": "\(.*\)".*/\1/'
    else
        echo "unknown"
    fi
}

# Get latest release version from GitHub
_nivuus_latest_version() {
    local response=$(curl -sS -f \
        -H "Accept: application/vnd.github.v3+json" \
        "$NIVUUS_GITHUB_API/repos/$NIVUUS_GITHUB_REPO/releases/latest" 2>/dev/null)

    if [[ $? -eq 0 ]] && [[ -n "$response" ]]; then
        echo "$response" | grep '"tag_name"' | sed 's/.*"tag_name": "v\?\(.*\)".*/\1/'
    else
        return 1
    fi
}

# Compare versions (returns 0 if v2 > v1, 1 otherwise)
_nivuus_version_greater() {
    local v1=$1
    local v2=$2

    # Remove 'v' prefix if present
    v1=${v1#v}
    v2=${v2#v}

    # Handle "unknown" version
    [[ "$v1" == "unknown" ]] && return 0

    # Split versions into arrays
    local -a v1_parts=(${(s:.:)v1})
    local -a v2_parts=(${(s:.:)v2})

    # Compare each part
    for i in {1..3}; do
        local p1=${v1_parts[$i]:-0}
        local p2=${v2_parts[$i]:-0}

        # Strip any pre-release/build suffix (e.g. "1-rc2" -> "1") and
        # fall back to 0 for non-numeric parts so (( )) never errors.
        p1=${p1%%[-+]*}; [[ "$p1" == <-> ]] || p1=0
        p2=${p2%%[-+]*}; [[ "$p2" == <-> ]] || p2=0

        if (( p2 > p1 )); then
            return 0
        elif (( p1 > p2 )); then
            return 1
        fi
    done

    # Versions are equal
    return 1
}

# Check if update is available
_nivuus_update_available() {
    local current=$(_nivuus_current_version)
    local latest=$(_nivuus_latest_version)

    [[ -n "$latest" ]] && _nivuus_version_greater "$current" "$latest"
}

# Get days since last check
_nivuus_days_since_check() {
    if [[ ! -f "$NIVUUS_UPDATE_CHECK_FILE" ]]; then
        echo 999
        return
    fi

    local last_check=$(cat "$NIVUUS_UPDATE_CHECK_FILE" 2>/dev/null || echo 0)
    local now=$(date +%s)
    local diff=$((now - last_check))
    echo $((diff / 86400))
}

# Update the last check timestamp
_nivuus_update_check_timestamp() {
    date +%s > "$NIVUUS_UPDATE_CHECK_FILE"
}

# Clean up old backups (keep only last 5)
_nivuus_cleanup_old_backups() {
    local backup_base="$HOME/.config/nivuus-shell-backup"

    # Check if backup directory exists
    [[ ! -d "$backup_base" ]] && return

    # Find all pre-update backups, sort by date (newest first), keep only first 5
    local backups=("$backup_base"/pre-update-*(N))

    # If we have more than 5 backups, remove the oldest ones
    if (( ${#backups[@]} > 5 )); then
        # Sort by modification time (newest first) and get all except first 5
        local to_remove=("${(@)backups[6,-1]}")

        for old_backup in "${to_remove[@]}"; do
            rm -rf "$old_backup"
        done
    fi
}

# Create backup before update
_nivuus_create_update_backup() {
    local backup_dir="$HOME/.config/nivuus-shell-backup/pre-update-$(date +%Y%m%d-%H%M%S)"

    mkdir -p "$backup_dir"

    # Backup entire installation directory
    if [[ -d "$NIVUUS_SHELL_DIR" ]]; then
        cp -r "$NIVUUS_SHELL_DIR" "$backup_dir/nivuus-shell"
    fi

    # Backup user files
    [[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$backup_dir/.zshrc"
    [[ -f "$HOME/.zsh_local" ]] && cp "$HOME/.zsh_local" "$backup_dir/.zsh_local"

    # Clean up old backups after creating new one
    _nivuus_cleanup_old_backups

    echo "$backup_dir"
}

# Empreinte SHA-256 portable. Fonction pure : ne télécharge rien, ne
# dépend d'aucun état global.
#
# Historique : cette fonction existe parce que _nivuus_download_release
# appelait `sha256sum` sans repli. `sha256sum` n'existe pas par défaut sur
# macOS (`shasum` y est l'outil livré) : `actual_sum` y était vide, la
# comparaison échouait toujours, et TOUTE mise à jour était cassée sur
# macOS. lib/manifest.sh gérait déjà les deux cas ; l'updater non.
#
# Retourne 1 sans rien imprimer si aucun outil n'est disponible. Le
# « sans rien imprimer » est la partie importante : une chaîne vide
# comparée à une empreinte attendue est un faux négatif silencieux.
_nivuus_sha256_of() {
    local file=$1
    [[ -r "$file" ]] || return 1

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        # Dernier recours : openssl est de toute façon requis par le
        # chemin de signature sur la plupart des machines.
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    else
        return 1
    fi
}

# Empreinte d'un fichier de clé publique PEM, telle qu'inscrite dans
# keys/revoked. Format : « sha256:<hex> ».
_nivuus_key_fingerprint() {
    local pem=$1 digest
    digest=$(_nivuus_sha256_of "$pem") || return 1
    printf 'sha256:%s\n' "$digest"
}

_nivuus_key_is_revoked() {
    local pem=$1 keys_dir=$2 fp
    [[ -r "$keys_dir/revoked" ]] || return 1
    fp=$(_nivuus_key_fingerprint "$pem") || return 1
    grep -qxF "$fp" "$keys_dir/revoked" 2>/dev/null
}

# Recopie allowed_signers en retirant les lignes dont la clé publique est
# listée dans keys/revoked. ssh-keygen n'ayant pas de notion de
# révocation utilisable ici, on la matérialise en amont.
# Empreinte utilisée : celle de `ssh-keygen -lf` (« SHA256:… »).
#
# Écart assumé au plan : le plan écrivait les fichiers intermédiaires avec
# `mktemp`. Impossible ici — le cas « openssl absent » du spec (case 8) est
# testé avec un PATH réduit qui ne contient PAS mktemp, et la vérification
# doit fonctionner sur une machine minimale. On utilise donc la
# substitution de processus zsh `=(...)`, qui crée un fichier temporaire
# par les moyens internes de zsh, sans aucun binaire externe, et le nettoie
# elle-même.
_nivuus_filter_revoked_signers() {
    local allowed=$1 keys_dir=$2 line fp
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        # Format : « <principal> <type> <base64> [commentaire] »
        fp=$(ssh-keygen -lf =(printf '%s\n' "${line#* }") 2>/dev/null | awk '{print $2}')
        if [[ -n "$fp" ]] && [[ -r "$keys_dir/revoked" ]] && \
           grep -qxF "$fp" "$keys_dir/revoked" 2>/dev/null; then
            continue
        fi
        printf '%s\n' "$line"
    done < "$allowed"
}

# Vérifie la signature de SHA256SUMS contre le trousseau de confiance.
#
# Fonction PURE : ne télécharge rien, n'écrit rien, ne lit aucun état
# global autre que le défaut de keys_dir. C'est ce qui la rend testable
# sans réseau — la raison pour laquelle il n'existait aucun test de cette
# logique jusqu'ici.
#
# keys_dir est un PARAMÈTRE et non une variable d'environnement : les
# tests injectent un jeu éphémère sans qu'aucune porte de contournement
# n'existe en production.
#
#   $1  chemin du fichier SHA256SUMS à authentifier
#   $2  répertoire contenant SHA256SUMS.sig et/ou SHA256SUMS.sshsig
#   $3  répertoire du trousseau (défaut : $NIVUUS_SHELL_DIR/keys)
#
# Retour : 0 = signature valide contre une clé de confiance
#          1 = signature invalide, absente ou illisible
#          2 = aucun outil de vérification disponible sur cette machine
_nivuus_verify_signature() {
    local sums=$1 sig_dir=$2 keys_dir=${3:-$NIVUUS_SHELL_DIR/keys}
    local have_tool=0 key

    [[ -r "$sums" ]] || return 1

    # --- Chemin primaire : openssl / ECDSA P-256 -----------------------
    if command -v openssl >/dev/null 2>&1; then
        have_tool=1
        local sig="$sig_dir/SHA256SUMS.sig"
        if [[ -s "$sig" ]]; then
            for key in "$keys_dir"/*.pem(N); do
                _nivuus_key_is_revoked "$key" "$keys_dir" && continue
                if openssl dgst -sha256 -verify "$key" \
                        -signature "$sig" "$sums" >/dev/null 2>&1; then
                    return 0
                fi
            done
        fi
    fi

    # --- Chemin de repli : ssh-keygen / SSHSIG -------------------------
    # Sur les machines sans openssl (fréquent sur les serveurs et
    # certaines images minimales), OpenSSH est presque toujours là.
    # Mesuré : sur Fedora 40 + zsh/git/curl, openssl est ABSENT et
    # ssh-keygen présent — ce repli y porte 100 % du trafic de
    # vérification (voir doc/SIGNING.md). Sans lui, le refus dur du § 4
    # supprimerait définitivement l'auto-update sur toute une classe de
    # machines.
    if command -v ssh-keygen >/dev/null 2>&1; then
        have_tool=1
        local sshsig="$sig_dir/SHA256SUMS.sshsig"
        local allowed="$keys_dir/allowed_signers"
        if [[ -s "$sshsig" && -s "$allowed" ]]; then
            local filtered
            filtered=$(_nivuus_filter_revoked_signers "$allowed" "$keys_dir")
            if [[ -n "$filtered" ]] && \
               ssh-keygen -Y verify -f =(printf '%s\n' "$filtered") \
                   -I nivuus-release -n nivuus-release -s "$sshsig" \
                   < "$sums" >/dev/null 2>&1; then
                return 0
            fi
        fi
    fi

    (( have_tool )) || return 2
    return 1
}

# Base des URL d'assets. Surchargeable UNIQUEMENT pour les tests e2e,
# qui servent une fausse release via file:// (curl sait le faire, ce qui
# évite un serveur HTTP dans la suite). Jamais documentée pour les
# utilisateurs.
: ${NIVUUS_RELEASE_BASE_URL:=https://github.com/$NIVUUS_GITHUB_REPO/releases/download}

# Décide si une release téléchargée est acceptable. Fonction pure : aucun
# réseau, aucune écriture. Toute la politique de sécurité tient ici.
#
# Ordre non négociable : SIGNATURE d'abord, EMPREINTE ensuite. Vérifier
# une empreinte contre un SHA256SUMS non authentifié ne démontre rien.
#
# Retour : 0 acceptable / 1 refus / 2 aucun outil de vérification
_nivuus_verify_release() {
    local temp_dir=$1 version=$2 keys_dir=${3:-$NIVUUS_SHELL_DIR/keys}
    local archive="$temp_dir/nivuus-shell.tar.gz"
    local sums="$temp_dir/SHA256SUMS"

    _nivuus_verify_signature "$sums" "$temp_dir" "$keys_dir"
    local rc=$?
    if (( rc != 0 )); then
        return $rc
    fi

    # NIVUUS_VERIFY_CHECKSUMS ne porte QUE sur l'étape ci-dessous. Elle ne
    # peut pas, et ne doit jamais pouvoir, désactiver la signature.
    [[ "$NIVUUS_VERIFY_CHECKSUMS" == "true" ]] || return 0

    # Le nom versionné fait partie du contenu signé : c'est ce qui bloque
    # le rejeu inter-versions. Ne JAMAIS remplacer ce grep par head -n1.
    local expected_sum
    expected_sum=$(grep "nivuus-shell-v${version}.tar.gz" "$sums" | awk '{print $1}')
    [[ -n "$expected_sum" ]] || return 1

    local actual_sum
    actual_sum=$(_nivuus_sha256_of "$archive") || return 2
    [[ "$expected_sum" == "$actual_sum" ]] || return 1
    return 0
}

# Télécharge une release et décide si elle est installable.
#
#   $1  version cible
#   $2  « interactive » si l'appel vient de nivuus-update tapé par un
#       humain. Vide sur le chemin automatique — et c'est structurel :
#       l'échappatoire NIVUUS_ALLOW_UNVERIFIED_UPDATE ne peut pas exister
#       pour un processus d'arrière-plan.
#
# Imprime le chemin du répertoire temporaire sur stdout en cas de succès,
# et RIEN en cas de refus (l'appelant teste ce chemin).
#
# ATTENTION : les messages d'information partent sur STDERR, parce que la
# sortie standard porte le chemin du répertoire temporaire. L'ancien code
# mélangeait les deux.
_nivuus_download_release() {
    local version=$1 interactive=${2:-}
    local temp_dir=$(mktemp -d)
    local base="$NIVUUS_RELEASE_BASE_URL/v${version}"

    echo "📥 Downloading release v${version}..." >&2
    if ! curl -fsSL -o "$temp_dir/nivuus-shell.tar.gz" \
            "$base/nivuus-shell-v${version}.tar.gz"; then
        echo "❌ Failed to download release archive" >&2
        rm -rf "$temp_dir"
        return 1
    fi

    if ! curl -fsSL -o "$temp_dir/SHA256SUMS" "$base/SHA256SUMS"; then
        echo "❌ Could not download SHA256SUMS (verification required, aborting)" >&2
        rm -rf "$temp_dir"
        return 1
    fi

    # Les deux formats de signature sont téléchargés sans condition :
    # on ne sait pas encore lequel cette machine peut vérifier. Un 404
    # sur l'un des deux n'est pas fatal ; l'absence des DEUX le sera au
    # moment de la vérification.
    curl -fsSL -o "$temp_dir/SHA256SUMS.sig"    "$base/SHA256SUMS.sig"    2>/dev/null
    curl -fsSL -o "$temp_dir/SHA256SUMS.sshsig" "$base/SHA256SUMS.sshsig" 2>/dev/null

    echo "🔐 Verifying release signature..." >&2
    _nivuus_verify_release "$temp_dir" "$version"
    local rc=$?

    if (( rc == 2 )); then
        echo "❌ Aucun outil de vérification disponible sur cette machine." >&2
        echo "   Nivuus a besoin de « openssl » ou de « ssh-keygen » pour" >&2
        echo "   authentifier une mise à jour. Sans l'un des deux, la mise à" >&2
        echo "   jour automatique reste inactive." >&2
        echo "   Diagnostic : nivuus doctor" >&2
    elif (( rc != 0 )); then
        echo "❌ Signature ou empreinte invalide pour la release v${version}." >&2
        echo "   L'archive est potentiellement altérée. NE PAS contourner." >&2
        echo "   Vérifie la page de release :" >&2
        echo "   https://github.com/$NIVUUS_GITHUB_REPO/releases/tag/v${version}" >&2
    fi

    if (( rc != 0 )); then
        # Unique échappatoire (§ 4 du spec) : une décision consciente
        # d'un humain devant son terminal. Trois gardes conjointes, et
        # une confirmation explicite. Le chemin automatique ne passe
        # jamais ici, faute du drapeau « interactive ».
        if [[ "$interactive" == "interactive" ]] \
            && [[ "$NIVUUS_ALLOW_UNVERIFIED_UPDATE" == "1" ]] && [[ -t 0 ]]; then
            echo "" >&2
            echo "⚠️  NIVUUS_ALLOW_UNVERIFIED_UPDATE=1 est défini." >&2
            echo "   Installer une release non vérifiée exécute du code" >&2
            echo "   arbitraire à chaque ouverture de shell." >&2
            local reply
            read -r "reply?Installer quand même cette release NON VÉRIFIÉE ? (tape OUI) "
            if [[ "$reply" == "OUI" ]]; then
                echo "$temp_dir"
                return 0
            fi
        fi
        rm -rf "$temp_dir"
        return 1
    fi

    echo "✅ Signature verified" >&2
    echo "$temp_dir"
}

# Install release from archive
_nivuus_install_release() {
    local version=$1
    local temp_dir=$2

    echo "📦 Installing Nivuus Shell v${version}..."

    # Extract archive to temp location
    local extract_dir="$temp_dir/extract"
    mkdir -p "$extract_dir"

    if ! tar -xzf "$temp_dir/nivuus-shell.tar.gz" -C "$extract_dir"; then
        echo "❌ Failed to extract release archive"
        return 1
    fi

    # Preserve user configuration
    local user_config=""
    if [[ -f "$NIVUUS_SHELL_DIR/.zsh_local" ]]; then
        user_config=$(cat "$NIVUUS_SHELL_DIR/.zsh_local")
    fi

    # Remove old installation (except user files)
    local files_to_preserve=(".zsh_local" ".version")
    local temp_preserve="$temp_dir/preserve"
    mkdir -p "$temp_preserve"

    for file in "${files_to_preserve[@]}"; do
        [[ -f "$NIVUUS_SHELL_DIR/$file" ]] && \
            cp "$NIVUUS_SHELL_DIR/$file" "$temp_preserve/"
    done

    # Refuse to wipe a git checkout, whatever the caller did.
    if _nivuus_is_dev_checkout; then
        echo "❌ Refusing to overwrite a git checkout at $NIVUUS_SHELL_DIR"
        return 1
    fi

    # Install new version. Remove old contents explicitly (never via a glob,
    # which would honour GLOB_DOTS and could match .git / dotfiles) while
    # always preserving VCS metadata and user files.
    find "$NIVUUS_SHELL_DIR" -mindepth 1 -maxdepth 1 \
        ! -name '.git' ! -name '.zsh_local' ! -name '.version' \
        -exec rm -rf {} + 2>/dev/null
    cp -r "$extract_dir"/. "$NIVUUS_SHELL_DIR/"

    # Restore preserved files
    for file in "${files_to_preserve[@]}"; do
        [[ -f "$temp_preserve/$file" ]] && \
            cp "$temp_preserve/$file" "$NIVUUS_SHELL_DIR/"
    done

    # Update version file
    echo "$version" > "$NIVUUS_VERSION_FILE"

    # Make bin scripts executable
    if [[ -d "$NIVUUS_SHELL_DIR/bin" ]]; then
        chmod +x "$NIVUUS_SHELL_DIR/bin"/*
    fi

    # Recompile all .zsh files
    for file in "$NIVUUS_SHELL_DIR"/**/*.zsh(N); do
        zcompile "$file" 2>/dev/null
    done

    echo "🔨 Recompiled configuration files"
    echo "✅ Installation complete!"

    return 0
}

# Perform the actual update
_nivuus_perform_update() {
    local target_version=${1:-$(_nivuus_latest_version)}
    # Drapeau propagé tel quel : c'est son ABSENCE sur le chemin
    # automatique qui rend l'échappatoire inatteignable en arrière-plan.
    local interactive=${2:-}

    if [[ -z "$target_version" ]]; then
        echo "❌ Could not determine target version"
        return 1
    fi

    # Vérifier d'abord : une release refusée ne doit rien coûter et ne
    # rien laisser derrière elle. La sauvegarde ne protège que de
    # l'INSTALLATION, pas du téléchargement — la créer avant de savoir si
    # la release est seulement acceptable, c'était recopier toute
    # l'installation (~50 Mo) à chaque tentative refusée, sur toutes les
    # machines, une fois par semaine.
    local temp_dir=$(_nivuus_download_release "$target_version" "$interactive")

    if [[ -z "$temp_dir" ]] || [[ ! -d "$temp_dir" ]]; then
        echo "❌ Download failed"
        return 1
    fi

    # Create backup
    local backup_dir=$(_nivuus_create_update_backup)
    echo "📦 Backup created: $backup_dir"

    # Install release
    if _nivuus_install_release "$target_version" "$temp_dir"; then
        echo "♻️  Restart your shell to apply changes: exec zsh"
        rm -rf "$temp_dir"
        return 0
    else
        echo "❌ Installation failed! Restoring from backup..."

        # Restore from backup
        if [[ -d "$backup_dir/nivuus-shell" ]]; then
            rm -rf "$NIVUUS_SHELL_DIR"
            cp -r "$backup_dir/nivuus-shell" "$NIVUUS_SHELL_DIR"
            echo "✅ Restored from backup"
        fi

        rm -rf "$temp_dir"
        return 1
    fi
}

# Background update check (async, no performance impact)
_nivuus_check_update_async() {
    local log_file
    log_file=$(mktemp "${TMPDIR:-/tmp}/nivuus-update.XXXXXX") || return
    (
        # Update timestamp
        _nivuus_update_check_timestamp

        # Check if update is available
        if _nivuus_update_available; then
            # Auto-install the update
            _nivuus_perform_update > "$log_file" 2>&1
        fi
    ) &!
}

# ============================================================================
# Main Auto-Update Logic
# ============================================================================

# Only run if enabled — never against a git checkout (dev mode), where a
# destructive release install would delete .git and any uncommitted work,
# and never against a package install, where it would rewrite files owned
# by dpkg / pacman / brew (spec § 1.1). La règle du mode paquet l'emporte
# délibérément sur ENABLE_AUTOUPDATE=true : il n'existe aucune façon
# d'honorer ce réglage qui ne produise pas un système incohérent.
if [[ "$ENABLE_AUTOUPDATE" == "true" ]] \
   && ! _nivuus_is_dev_checkout \
   && ! _nivuus_is_package_install; then
    # Check if it's time for an update check
    days_since_check=$(_nivuus_days_since_check)

    if (( days_since_check >= AUTOUPDATE_CHECK_FREQUENCY_DAYS )); then
        _nivuus_check_update_async
    fi
    unset days_since_check
fi

# ============================================================================
# Manual Update Command
# ============================================================================

nivuus-update() {
    # Never run the destructive release updater on a git checkout.
    if _nivuus_is_dev_checkout; then
        # Deux situations très différentes derrière un même .git, et le
        # message générique envoyait la mauvaise dans une impasse : le
        # dépôt que l'installeur de la v3.0.0 créait ici n'est PAS un
        # checkout de développement, et « git pull » n'y donne rien
        # d'utile. lib/migrate.sh sait les distinguer ; on ne la source
        # qu'ici, jamais au démarrage -- le budget de démarrage est intact.
        local _nivuus_git_kind=""
        if [[ -r "$NIVUUS_SHELL_DIR/lib/migrate.sh" ]]; then
            source "$NIVUUS_SHELL_DIR/lib/migrate.sh" 2>/dev/null
            _nivuus_git_kind="$(nivuus_git_state "$NIVUUS_SHELL_DIR" 2>/dev/null)"
        fi
        if [[ "$_nivuus_git_kind" == "legacy" ]]; then
            echo "⚠️  Un dépôt git hérité de la v3.0.0 se trouve dans $NIVUUS_SHELL_DIR."
            echo "   C'est lui qui bloque tes mises à jour depuis l'installation."
            echo "   Lance « nivuus migrate » pour le mettre de côté (il est déplacé,"
            echo "   pas supprimé), puis relance « nivuus-update »."
        else
            echo "ℹ️  Development checkout detected at $NIVUUS_SHELL_DIR"
            echo "   Use 'git pull' here instead of the release updater."
        fi
        return 0
    fi

    echo "🔍 Checking for updates..."

    # Update check timestamp
    _nivuus_update_check_timestamp

    # Check versions
    local current=$(_nivuus_current_version)
    local latest=$(_nivuus_latest_version)

    if [[ -z "$latest" ]]; then
        echo "❌ Could not fetch latest version from GitHub"
        echo "   Please check your internet connection"
        return 1
    fi

    echo "📍 Current version: v${current}"
    echo "📍 Latest version:  v${latest}"

    if _nivuus_update_available; then
        echo ""
        echo "🆕 Update available!"
        echo ""
        _nivuus_perform_update "$latest" interactive
    else
        echo ""
        echo "✅ Already up to date!"
    fi
}

# Command to check current version
nivuus-version() {
    local version=$(_nivuus_current_version)
    echo "Nivuus Shell v${version}"

    if [[ "$1" == "--check" ]] || [[ "$1" == "-c" ]]; then
        local latest=$(_nivuus_latest_version)
        if [[ -n "$latest" ]]; then
            echo "Latest release: v${latest}"

            if _nivuus_update_available; then
                echo "⚠️  Update available! Run 'nivuus-update' to upgrade"
            else
                echo "✅ You're running the latest version"
            fi
        fi
    fi
}
