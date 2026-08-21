# tests/helpers/portable.bash
# Édition de fichiers dans les tests, sans `sed -i` : GNU sed veut
# `sed -i 's/…/'`, BSD/macOS veut `sed -i '' 's/…/'`. Les deux formes sont
# mutuellement exclusives -- toute suite qui en utilise une échoue sur
# l'autre plateforme. On n'en utilise donc aucune.

pt_prepend_line() {
    local file="$1" text="$2" tmp
    tmp="$(mktemp)"
    { printf '%s\n' "$text"; cat "$file"; } > "$tmp"
    # cat > "$file" (et non mv) : préserve permissions et inode.
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

pt_to_crlf() {
    local file="$1" tmp
    tmp="$(mktemp)"
    awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$file" > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
}
