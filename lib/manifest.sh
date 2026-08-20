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
