# lib/system.sh
# Domaine root : où vont les fichiers, et qui a le droit de les y mettre.
#
# Ce module DÉCIDE et CONSTATE. Il n'écrit rien : toute mutation, y compris
# dans /etc, passe par lib/manifest.sh -- c'est ce qui rend le mode système
# réversible à l'octet près, et un test l'interdit mécaniquement.
#
# Tous les chemins sont paramétrables, non par goût de la configuration mais
# parce que c'est la seule façon de prouver cette couche sur une PR, sans
# conteneur et sans root.
#
# POSIX strict (BusyBox ash, bash 3.2).

: "${NIVUUS_SYSTEM_PREFIX:=/usr/local}"
: "${NIVUUS_SYSTEM_STATE_DIR:=/var/lib/nivuus}"
: "${NIVUUS_ETC_DIR:=/etc}"

# Le préfixe porte la RACINE FHS, pas l'arbre : les trois chemins qui en
# dérivent doivent bouger ensemble. Un test qui déplacerait l'arbre sans
# déplacer le lien prouverait une configuration qui n'existe pas.
nivuus_system_tree()      { printf '%s\n' "$NIVUUS_SYSTEM_PREFIX/share/nivuus-shell"; }
nivuus_system_bin()       { printf '%s\n' "$NIVUUS_SYSTEM_PREFIX/bin/nivuus"; }
nivuus_system_man()       { printf '%s\n' "$NIVUUS_SYSTEM_PREFIX/share/man/man1/nivuus.1"; }

# /var/lib et non /etc/nivuus-shell : même raison qu'au chantier 1 pour
# ~/.local/state -- le journal ne doit pas vivre dans ce qu'il doit pouvoir
# supprimer, sinon une installation cassée est irréparable.
nivuus_system_state_dir() { printf '%s\n' "$NIVUUS_SYSTEM_STATE_DIR"; }

nivuus_system_skel()      { printf '%s\n' "$NIVUUS_ETC_DIR/skel/.zshrc"; }
nivuus_system_dropin()    { printf '%s\n' "$NIVUUS_ETC_DIR/zsh/zshrc.d/10-nivuus.zsh"; }

# Il n'existe PAS de zshrc.d standard, et le fichier lu par tout zsh
# interactif dépend du --enable-etcdir de compilation : /etc/zsh/zshrc
# (Debian, Ubuntu, Arch) ou /etc/zshrc (Fedora, RHEL, macOS). On choisit
# sur l'existence du répertoire -- et l'activation machine ne CROIT pas ce
# choix : elle le vérifie en lançant un vrai zsh interactif.
nivuus_system_global_rc() {
    if [ -d "$NIVUUS_ETC_DIR/zsh" ]; then
        printf '%s\n' "$NIVUUS_ETC_DIR/zsh/zshrc"
    else
        printf '%s\n' "$NIVUUS_ETC_DIR/zshrc"
    fi
}

# $NIVUUS_UID : le crochet qui rend le refus de privilège testable sans
# privilège. En production il n'est jamais posé et `id -u` fait foi.
nivuus_system_is_root() {
    [ "${NIVUUS_UID:-$(id -u)}" -eq 0 ]
}

# EXIGER du root n'est pas EN ACQUÉRIR. Aucune ré-exécution privilégiée ici,
# ni nulle part : on refuse, on donne la commande, l'humain décide.
nivuus_system_require_root() {
    nivuus_system_is_root && return 0
    log_error "L'opération « ${1:-cette opération} » écrit dans $NIVUUS_SYSTEM_PREFIX et $NIVUUS_ETC_DIR : elle exige root."
    log_error "Rien n'a été écrit. Relance :"
    log_error "  sudo nivuus install --system"
    log_error "Pour auditer d'abord, sans aucun privilège :"
    log_error "  nivuus install --system --dry-run"
    return 1
}

# Une installation faite par l'ancien --system a laissé un arbre complet
# dans /etc/nivuus-shell, SANS manifeste, donc sans réversibilité possible.
# On le NOMME. On ne le supprime jamais : on ne restaure pas ce qu'on n'a
# pas sauvegardé.
nivuus_system_legacy_tree() {
    _legacy="$NIVUUS_ETC_DIR/nivuus-shell"
    [ -d "$_legacy" ] || return 1
    # Un répertoire vide (ou la future configuration de site) n'est pas un
    # arbre hérité : la signature, c'est config/00-core.zsh.
    [ -f "$_legacy/config/00-core.zsh" ] || return 1
    printf '%s\n' "$_legacy"
}

# Sur Debian et Ubuntu, « apt install ./nivuus-shell_*.deb » couvre 90 % de
# ce que --system apporte, et le couvre MIEUX (inventaire dpkg, dpkg -V,
# purge transactionnelle). On le dit avant d'écrire. Ailleurs -- Fedora,
# RHEL, openSUSE, Alpine, conteneurs -- il n'y a rien à recommander : c'est
# exactement la raison d'être de ce mode.
# Sur Debian et Ubuntu, « apt install ./nivuus-shell_*.deb » couvre 90 % de
# ce que --system apporte, et le couvre MIEUX (inventaire dpkg, dpkg -V,
# purge transactionnelle). On le dit -- une fois, avant toute écriture.
#
# Ce n'est PAS un refus : un administrateur peut légitimement préférer un
# arbre sous /usr/local qu'aucune mise à jour de distribution ne touchera.
# Là où aucun canal n'existe (Fedora, RHEL, openSUSE, Alpine, images de
# base), on se tait : c'est le périmètre propre de ce mode.
#
# Sort en 0 quand il y a quelque chose à dire, en 1 sinon -- l'appelant en
# fait une question.
nivuus_system_package_notice() {
    [ -n "${NIVUUS_SYSTEM_ASSUME_NO_PACKAGE:-}" ] && return 1
    _chan="$(nivuus_system_package_channel)"
    [ -n "$_chan" ] || return 1
    case "$_chan" in
        deb)
            log_info "Nivuus est disponible en paquet sur cette distribution :"
            log_info "    apt install ./nivuus-shell_<version>_all.deb      (release GitHub)"
            log_info "Le paquet est inventorié par dpkg -- vérifiable par « dpkg -V », retiré par"
            log_info "« apt purge » -- ce que --system doit refaire lui-même dans /var/lib/nivuus."
            log_info "--system garde deux avantages : un arbre sous /usr/local qu'aucune mise à jour"
            log_info "de distribution ne touche, et les activations machine (--skel, --activate-all)."
            return 0
            ;;
    esac
    return 1
}

# Un manifeste système qui décrit un $HOME est corrompu ou fabriqué :
# install --system n'en écrit JAMAIS (un test l'interdit). Plutôt que de
# faire confiance à cette propriété au moment le plus dangereux -- un rejeu
# en root -- on la vérifie. Quelques lignes d'awk contre la classe entière
# des scénarios « manifeste trafiqué » et « bug d'une version future ».
#
# Trois racines : /home et /Users, les deux conventions, et $HOME lui-même,
# qui couvre /root, les comptes hors convention et les arbres de test. Ce
# n'est PAS une lecture d'un $HOME : c'est une comparaison de chaînes.
nivuus_system_manifest_has_home() {
    _m="$1"
    [ -f "$_m" ] || return 1
    awk -F"$NIVUUS_TAB" -v h="${HOME:-}" '
        NR > 1 && ($2 ~ /^\/home\// || $2 ~ /^\/Users\//) { found = 1 }
        NR > 1 && h != "" && h != "/" && index($2, h "/") == 1 { found = 1 }
        END { exit !found }
    ' "$_m"
}

# Charge RÉELLEMENT l'arbre, depuis un environnement vierge et non
# privilégié. Trois façons d'obtenir un arbre en place que les shells ne
# peuvent pas charger -- umask restrictif sous sudo, SELinux sans
# restorecon, /usr/local monté noexec -- et toutes les trois passent
# inaperçues d'un installeur qui ne lit que des codes de retour.
#
# Root peut lire un arbre 0700 : sonder en root prouverait exactement ce
# qu'on ne cherche pas. On sonde donc en tant que « nobody » quand il
# existe (toutes les cibles de la matrice l'ont), et on le dit sinon.
nivuus_system_probe_tree() {
    _tree="$1"
    command -v zsh >/dev/null 2>&1 || { log_warn "zsh absent : arbre non sondé."; return 0; }
    _probe_home="$(mktemp -d)" || return 1
    _as="${NIVUUS_SYSTEM_PROBE_USER-nobody}"
    if [ -n "$_as" ] && ! id "$_as" >/dev/null 2>&1; then _as=''; fi
    # « nobody » EXISTE partout, mais il n'est pas partout UTILISABLE : sur
    # Arch Linux son compte est expiré et su refuse (« User account has
    # expired »). Mesuré dans un conteneur archlinux:latest, pas supposé.
    # Sans cette vérification, la sonde échouait et ANNULAIT une
    # installation parfaitement saine -- le pire des faux négatifs, puisque
    # le garde-fou censé protéger l'administrateur lui interdisait
    # d'installer.
    if [ -n "$_as" ] && nivuus_system_is_root \
        && ! su -s /bin/sh "$_as" -c 'exit 0' >/dev/null 2>&1; then
        log_warn "Le compte de sonde « $_as » est inutilisable ici (expiré ou verrouillé) :"
        log_warn "la sonde tourne en root, elle est donc moins probante."
        _as=''
    fi
    if [ -z "$_as" ] && nivuus_system_is_root; then
        log_warn "Aucun compte non privilégié pour la sonde : elle est moins probante en root."
    fi

    _cmd="env -i HOME=$_probe_home PATH=$PATH TERM=dumb ZDOTDIR=$_probe_home \
          zsh -ic 'source $_tree/.zshrc >/dev/null 2>&1; print -r -- \${NIVUUS_SHELL_LOADED:-none}'"
    if [ -n "$_as" ] && nivuus_system_is_root; then
        chmod 0755 "$_probe_home" 2>/dev/null || :
        _out="$(su -s /bin/sh "$_as" -c "$_cmd" 2>/dev/null | tail -n1)"
    else
        _out="$(sh -c "$_cmd" 2>/dev/null | tail -n1)"
    fi
    rm -rf "$_probe_home"

    if [ "$_out" = "1" ] || [ "$_out" = "true" ]; then
        return 0
    fi
    log_error "L'arbre $_tree est en place mais AUCUN shell ne peut le charger."
    log_error "Causes usuelles : umask restrictif sous sudo, SELinux sans restorecon,"
    log_error "ou $NIVUUS_SYSTEM_PREFIX monté noexec. Vérifie :  ls -ld $_tree"
    return 1
}

# SELinux : rétablit l'étiquette que la politique prescrit DÉJÀ pour ces
# chemins. Ne crée ni ne supprime rien, donc rien à journaliser -- le
# retrait du fichier emporte son étiquette. Son absence est signalée, jamais
# fatale : la majorité des cibles n'a pas SELinux du tout.
nivuus_system_restorecon() {
    if ! command -v restorecon >/dev/null 2>&1; then
        [ -d /sys/fs/selinux ] && log_warn "SELinux est actif mais restorecon est absent : étiquettes non rétablies."
        return 0
    fi
    for _p in "$@"; do
        [ -e "$_p" ] || continue
        restorecon -F -R "$_p" >/dev/null 2>&1 || log_warn "restorecon a échoué sur $_p (non fatal)."
    done
    return 0
}

nivuus_system_package_channel() {
    _id="$(nivuus_detect_distro)"
    _like="$(nivuus_detect_distro_like)"
    case "$_id" in
        debian|ubuntu|raspbian|linuxmint|pop) printf 'deb\n'; return 0 ;;
    esac
    case " $_like " in
        *" debian "*|*" ubuntu "*) printf 'deb\n'; return 0 ;;
    esac
    return 0
}
