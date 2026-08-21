# tests/helpers/users.bash
# Comptes jetables pour la preuve du mode système.
#
# C'est la SEULE brique privilégiée du dépôt. Elle n'est appelée que par
# tests/ci/run-system-target.sh, qui ne tourne que dans un conteneur
# jetable -- jamais sur un runner, jamais sur un poste. Chaque fonction
# refuse d'agir sans root plutôt que d'échouer à moitié.
#
# POSIX sh strict : ce fichier est sourcé par un script /bin/sh (dash,
# BusyBox ash) autant que par bats.

users_require_root() {
    [ "$(id -u)" -eq 0 ] && return 0
    printf '%s\n' "Ce test exige root et un conteneur jetable (useradd/su)." >&2
    return 1
}

# useradd (shadow, GNU) OU adduser (BusyBox, Alpine) : deux syntaxes
# incompatibles, et Alpine est à la fois une cible de la matrice et l'un des
# deux cas d'usage centraux de --system. Couvrir les deux n'est pas un luxe.
mk_user() {
    _u="$1"; _sh="${2:-/bin/zsh}"
    id "$_u" >/dev/null 2>&1 && return 0     # idempotent : un script de preuve se rejoue
    if command -v useradd >/dev/null 2>&1; then
        useradd -m -s "$_sh" "$_u"
    elif command -v adduser >/dev/null 2>&1; then
        adduser -D -h "/home/$_u" -s "$_sh" "$_u"
    else
        printf '%s\n' "Ni useradd ni adduser : impossible de créer $_u." >&2
        return 1
    fi
}

# Le HOME tel que le SYSTÈME le connaît, jamais deviné à partir du nom :
# /etc/skel, useradd et adduser peuvent tous le placer ailleurs. getent
# manque sur BusyBox nu : on retombe alors sur une lecture directe de
# /etc/passwd, qui est exactement ce que getent y lirait.
user_home() {
    if command -v getent >/dev/null 2>&1; then
        getent passwd "$1" 2>/dev/null | cut -d: -f6
    else
        awk -F: -v u="$1" '$1 == u { print $6; exit }' /etc/passwd
    fi
}

# su -l, pas su -c : -l recharge HOME, USER et SHELL de la cible. Avec su -c,
# $HOME resterait /root et l'on prouverait exactement le contraire de ce
# qu'on cherche (« alice voit son propre HOME »).
as_user() {
    _u="$1"; shift
    su -l "$_u" -c "$*"
}

rm_user() {
    _u="$1"
    id "$_u" >/dev/null 2>&1 || return 0
    if command -v userdel >/dev/null 2>&1; then
        userdel -r "$_u" 2>/dev/null || userdel "$_u"
    elif command -v deluser >/dev/null 2>&1; then
        deluser --remove-home "$_u" 2>/dev/null || deluser "$_u"
    fi
}

# Comptes humains : uid >= 1000, shell non nologin/false. Lu dans
# /etc/passwd -- JAMAIS en parcourant /home, qui déclencherait l'automonteur
# sur un parc NFS et lirait des répertoires d'autrui.
count_regular_users() {
    awk -F: '$3 >= 1000 && $3 < 65534 && $7 !~ /(nologin|false)$/ { n++ } END { print n + 0 }' \
        "${NIVUUS_PASSWD_FILE:-/etc/passwd}"
}
