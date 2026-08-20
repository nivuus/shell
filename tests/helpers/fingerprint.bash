# tests/helpers/fingerprint.bash
# Empreinte reproductible d'une arborescence : chemin, permissions, contenu.

fs_hash() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

fs_perms() {
    # -c GNU, -f BSD/macOS
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

fs_fingerprint() {
    local root="$1"
    { find "$root" -type d | while IFS= read -r d; do
          printf 'DIR\t%s\t%s\n' "${d#$root}" "$(fs_perms "$d")"
      done
      find "$root" -type f | while IFS= read -r f; do
          printf 'FILE\t%s\t%s\t%s\n' "${f#$root}" "$(fs_perms "$f")" "$(fs_hash "$f")"
      done
    } | LC_ALL=C sort
}
