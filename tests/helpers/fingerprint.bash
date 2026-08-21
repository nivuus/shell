# tests/helpers/fingerprint.bash
# Empreinte reproductible d'une arborescence : chemin, permissions, contenu.
#
# LIMITE CONNUE : les liens symboliques sont invisibles ici. `find -type d` et
# `-type f` ne matchent pas un lien (son type est `l`), donc un lien laissé
# derrière ou mal restauré ne ferait PAS échouer le test. Inerte aujourd'hui —
# rien dans bin/nivuus ni lib/ ne crée de lien — mais si cela change, ajouter
# `-type l` ici AVANT de se fier au vert de ce test.
# Non capturés non plus : attributs étendus, ACL, et mtimes (ces derniers
# volontairement : la promesse porte sur le contenu, les chemins et les droits).

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

# Shell de connexion. Le spec exige qu'il fasse partie de l'empreinte de
# réversibilité : un chsh non restauré est une trace laissée derrière.
# $NIVUUS_LOGIN_SHELL_FILE fait autorité quand il est défini -- c'est le
# crochet que les tests utilisent pour ne jamais toucher au vrai système.
fs_login_shell() {
    if [ -n "${NIVUUS_LOGIN_SHELL_FILE:-}" ] && [ -f "$NIVUUS_LOGIN_SHELL_FILE" ]; then
        head -n1 "$NIVUUS_LOGIN_SHELL_FILE"
    else
        printf '%s\n' "${SHELL:-}"
    fi
}
