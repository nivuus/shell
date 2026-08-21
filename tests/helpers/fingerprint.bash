# tests/helpers/fingerprint.bash
# Empreinte reproductible d'une arborescence : chemin, permissions,
# propriétaire, contenu — et les liens symboliques, cible comprise.
#
# Pourquoi uid/gid : le mode système écrit en root dans /etc et /usr/local.
# Un chown qui survit à la désinstallation est une trace, et sans ces deux
# colonnes il serait strictement invisible.
# Pourquoi les liens : /usr/local/bin/nivuus EST un lien. Sans -type l, un
# lien mort laissé derrière ne ferait échouer aucun test.
#
# Non capturés, et c'est délibéré : les attributs étendus, les ACL, les
# contextes SELinux (restorecon est best-effort) et les mtimes (la promesse
# porte sur le contenu, les chemins et les droits).
# Les MODES d'un lien symbolique ne sont pas capturés : ils ne sont pas
# portables (Linux les ignore, BSD non). Ce qu'un lien porte réellement,
# c'est sa cible et son propriétaire.

fs_hash() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

fs_perms() {
    # -c GNU, -f BSD/macOS
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

# uid:gid NUMÉRIQUES : un nom d'utilisateur dépend de /etc/passwd, qui
# diffère d'un conteneur à l'autre ; un uid ne dépend de rien.
# Ni `stat -c` (GNU) ni `stat -f` (BSD) ne suivent un lien symbolique par
# défaut -- c'est exactement ce qu'on veut ici.
fs_owner() {
    stat -c '%u:%g' "$1" 2>/dev/null || stat -f '%u:%g' "$1"
}

fs_fingerprint() {
    local root="$1"
    { find "$root" -type d | while IFS= read -r d; do
          printf 'DIR\t%s\t%s\t%s\n' "${d#$root}" "$(fs_perms "$d")" "$(fs_owner "$d")"
      done
      find "$root" -type f | while IFS= read -r f; do
          printf 'FILE\t%s\t%s\t%s\t%s\n' "${f#$root}" "$(fs_perms "$f")" "$(fs_owner "$f")" "$(fs_hash "$f")"
      done
      find "$root" -type l | while IFS= read -r l; do
          # La cible fait office de « contenu » : c'est tout ce qu'un lien
          # transporte. readlink (sans -f) ne résout PAS la chaîne : on veut
          # ce que le lien dit, pas où il finit.
          printf 'LINK\t%s\t%s\t%s\n' "${l#$root}" "$(fs_owner "$l")" "$(readlink "$l")"
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
