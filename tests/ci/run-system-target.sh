#!/bin/sh
# =============================================================================
# La séquence « preuve » du mode système : deux utilisateurs réels.
# =============================================================================
# Exécuté à l'identique par .github/workflows/matrix.yml et par un rejeu
# local « docker run … ./tests/ci/run-system-target.sh ». Aucune logique de
# preuve ne vit dans le YAML : c'est ce qui rend la matrice testable avant
# tout push.
#
# EXIGE root et un conteneur JETABLE : ce script crée des comptes et écrit
# dans /etc et /usr/local. Il n'a rien à faire sur un runner ni sur un poste.
set -eu

. ./tests/helpers/users.bash
. ./tests/helpers/fingerprint.bash

users_require_root || exit 1
if [ ! -f /.dockerenv ] && [ -z "${NIVUUS_ALLOW_UNSAFE_SYSTEM_TEST:-}" ]; then
    printf '%s\n' "Refus : ce script écrit dans /etc et /usr/local. Lance-le dans un conteneur." >&2
    exit 1
fi

SRC="$(pwd)"
WORK="$(mktemp -d)"
TREE=/usr/local/share/nivuus-shell
# ~/.zcompdump est exclu de l'empreinte, et c'est une exception MESURÉE,
# pas un confort :
#   - fedora:41  : « useradd -m -s /bin/zsh carol && su -l carol -c
#     'zsh -i -c true' » crée /home/carol/.zcompdump SANS la moindre trace de
#     Nivuus -- c'est le compinit du /etc/skel/.zshrc de la distribution.
#   - ubuntu:24.04 : un zsh interactif dont on a DÉPLACÉ le ~/.zshrc (donc
#     sans Nivuus du tout) SUPPRIME un ~/.zcompdump existant -- c'est le
#     compinit global de /etc/zsh/zshrc (lignes 106-112).
# Ce chemin appartient donc au zsh de la distribution, son cycle de vie
# n'est pas stable d'un démarrage à l'autre, et aucun test ne peut lui
# attribuer un responsable. L'imputer à Nivuus rendrait cette preuve rouge
# sur deux cibles pour une raison qui n'a rien à voir avec elle.
fp() { fs_fingerprint "$1" | grep -v '/\.zcompdump' > "$WORK/$2"; }

# /etc porte les bases de comptes, et c'est le HARNAIS qui les modifie --
# « mk_user carol » à l'étape 10, « rm_user » à la fin -- jamais Nivuus, qui
# n'y écrit pas une ligne : aucun chsh n'est fait en mode système, et un
# INVARIANT de tests/integration/test_install_system.bats interdit qu'une
# entrée CHSH apparaisse dans un manifeste système. Les exclure, c'est
# mesurer Nivuus plutôt que le harnais ; les garder ferait échouer l'étape
# 13 pour un compte que le test a créé lui-même.
fp_etc() {
    fs_fingerprint /etc | awk -F"$(printf '\t')" '
        $2 ~ /^\/(passwd|group|shadow|gshadow|subuid|subgid)-?$/ { next }
        $2 ~ /\.zcompdump/ { next }
        { print }
    ' > "$WORK/$1"
}
same() {
    if diff -u "$WORK/$1" "$WORK/$2" > "$WORK/diff.$1.$2"; then return 0; fi
    printf '%s\n' "DIVERGENCE entre $1 et $2 :" >&2
    cat "$WORK/diff.$1.$2" >&2
    exit 1
}
die() { printf '%s\n' "$*" >&2; exit 1; }

echo "== Étape 1 : deux utilisateurs réels et les empreintes de référence =="
mk_user alice
mk_user bob
ALICE="$(user_home alice)"; BOB="$(user_home bob)"
fp_etc etc.0
fp /usr/local      local.0
fp /var/lib        var.0
fp "$ALICE"        alice.0
fp "$BOB"          bob.0

echo "== Étape 2 : installation système sous un umask hostile =="
# umask 077 : le cas qui produit un arbre que PERSONNE ne peut lire. Les
# modes doivent être imposés, pas hérités.
( umask 077; "$SRC/bin/nivuus" install --system --yes )
[ -d "$TREE" ] || die "arbre absent"
[ -L /usr/local/bin/nivuus ] || die "lien absent"
[ "$(fs_owner "$TREE")" = "0:0" ] || die "arbre non root:root"
[ "$(fs_perms "$TREE")" = "755" ] || die "arbre non 0755 (umask hérité)"
[ "$(fs_perms "$TREE/config/00-core.zsh")" = "644" ] || die "fichier non 0644"
[ "$(fs_perms "$TREE/bin/nivuus")" = "755" ] || die "exécutable non 0755"
[ "$(fs_perms /var/lib/nivuus/backups)" = "700" ] || die "backups trop ouverts"

echo "== Étape 3 : INVARIANT n° 1 -- l'installation machine ne touche AUCUN \$HOME =="
# C'est le point que l'ancien --system violait : il écrasait le ~/.zshrc de
# $SUDO_USER, sans sauvegarde.
fp "$ALICE" alice.1; same alice.0 alice.1
fp "$BOB"   bob.1;   same bob.0   bob.1

echo "== Étape 4 : alice active, et son shell démarre en silence =="
as_user alice "nivuus enable --yes"
as_user alice "zsh -i -c 'echo SHELL_ALICE_OK'" > "$WORK/alice.out" 2> "$WORK/alice.err"
grep -q SHELL_ALICE_OK "$WORK/alice.out"
if [ -s "$WORK/alice.err" ]; then
    printf '%s\n' "stderr non vide :" >&2; cat "$WORK/alice.err" >&2; exit 1
fi
as_user alice "zsh -i -c 'print -r -- \$NIVUUS_SHELL_DIR'" | grep -qx "$TREE"

echo "== Étape 5 : INVARIANT n° 2 -- l'activation d'alice n'active pas bob =="
fp "$BOB" bob.2; same bob.0 bob.2

echo "== Étape 6 : « nivuus update » chez alice explique, et sort en 0 =="
as_user alice "nivuus update" > "$WORK/upd.out" 2>&1
grep -q "sudo nivuus update" "$WORK/upd.out"

echo "== Étape 7 : aucun updater ne s'est lancé dans les shells d'alice =="
as_user alice "zsh -i -c true"; as_user alice "zsh -i -c true"; as_user alice "zsh -i -c true"
if [ -f "$ALICE/.nivuus-shell-last-update-check" ]; then
    die "l'updater s'est exécuté sur un arbre système"
fi

echo "== Étape 8 : un shell ROOT ne compile aucun .zwc dans l'arbre partagé =="
# Le cas où l'écriture RÉUSSIRAIT : root peut écrire dans /usr/local. Des
# .zwc orphelins seraient une trace qu'aucune désinstallation ne connaît.
# On CHARGE réellement l'arbre en root : un « zsh -i -c true » ne lirait que
# le ~/.zshrc de root, qui n'a pas de bloc, et ne prouverait rien.
NIVUUS_SHELL_DIR="$TREE" zsh -i -c 'source "$NIVUUS_SHELL_DIR/.zshrc"' >/dev/null 2>&1 || true
sleep 2      # la compilation de config/99-cleanup.zsh est en arrière-plan (&!)
found="$(find "$TREE" -name '*.zwc' | head -n5)"
if [ -n "$found" ]; then
    die "des .zwc ont été écrits dans l'arbre système : $found"
fi

echo "== Étape 9 : alice se désactive, son \$HOME redevient bit-identique =="
as_user alice "nivuus disable --yes --purge"
fp "$ALICE" alice.9; same alice.0 alice.9

# /etc/skel n'existe PAS partout : alpine:3.20 n'en a aucun (BusyBox
# adduser ne s'en sert pas), et macOS non plus. Mesuré, pas supposé. Les
# deux branches sont des preuves, pas un contournement : là où le
# répertoire existe, --skel active les comptes créés ensuite ; là où il
# n'existe pas, --skel REFUSE au lieu d'être ignoré en silence -- ce qui
# est exactement la promesse de la décision « opt-in, jamais muet ».
if [ -d /etc/skel ]; then
    echo "== Étape 10 : /etc/skel n'active QUE les comptes créés après =="
    "$SRC/bin/nivuus" install --system --skel --yes
    mk_user carol
    CAROL="$(user_home carol)"
    grep -q "nivuus shell" "$CAROL/.zshrc" || die "carol n'a pas hérité de /etc/skel"
    as_user carol "zsh -i -c 'print -r -- \$NIVUUS_SHELL_DIR'" | grep -qx "$TREE"
else
    echo "== Étape 10 : pas de /etc/skel ici -- --skel doit REFUSER, pas ignorer =="
    if "$SRC/bin/nivuus" install --system --skel --yes > "$WORK/skel.out" 2>&1; then
        die "--skel aurait dû être refusé en l'absence de /etc/skel"
    fi
    grep -q "n'existe pas" "$WORK/skel.out" || die "le refus de --skel ne nomme pas la cause"
    [ -d "$TREE" ] || die "le refus de --skel a emporté l'installation existante"
fi
# Et bob, qui existait AVANT, n'a toujours rien : c'est la limite, et on
# ne prétend pas le contraire.
fp "$BOB" bob.10; same bob.0 bob.10

echo "== Étape 11 : activation machine -- bob est activé sans avoir rien fait =="
"$SRC/bin/nivuus" install --system --activate-all --yes
as_user bob "zsh -i -c 'print -r -- \$NIVUUS_SHELL_DIR'" | grep -qx "$TREE"
# La sonde qui a servi est bien celle-là : le marqueur le prouve.
as_user bob "zsh -i -c 'print -r -- \$NIVUUS_ACTIVATED_BY'" | grep -qx system
# L'activation machine reste EN PLACE : c'est « uninstall --system » qui doit
# la défaire à l'étape 13, conffile de la distribution compris. La retirer
# ici affaiblirait l'invariant n° 4 en lui épargnant le cas le plus dur.

echo "== Étape 12 : INVARIANT n° 3 -- installation utilisateur par-dessus, un seul source =="
# Release servie par file:// : la preuve ne dépend d'aucun réseau.
. ./tests/helpers/release.bash
make_release "$SRC" "$WORK/rel" 9.9.9
make_release_api "$WORK/api" fake/nivuus 9.9.9
chmod -R a+rX "$WORK"
as_user bob "NIVUUS_RELEASE_BASE_URL=file://$WORK/rel NIVUUS_GITHUB_API=file://$WORK/api \
             NIVUUS_VERSION=9.9.9 sh $SRC/install.sh --non-interactive"
as_user bob "zsh -i -c 'print -r -- \$NIVUUS_SHELL_DIR'" | grep -q "$BOB/.nivuus-shell"
# Le compteur de réentrance : un seul chargement, malgré le drop-in machine.
as_user bob "zsh -i -c 'print -r -- \$_nivuus_load_count'" | grep -qx 1
# Et bob redevient bit-identique : son installation personnelle se retire.
as_user bob "\$HOME/.nivuus-shell/bin/nivuus uninstall --yes --purge"

echo "== Étape 13 : INVARIANT n° 4 -- retrait bit-exact de /etc, /usr/local et /var/lib =="
as_user alice "nivuus enable --yes"      # une activation SURVIT au retrait : c'est voulu
fp "$ALICE" alice.pre13
fp "$BOB"   bob.pre13
"$SRC/bin/nivuus" uninstall --system --yes --purge
fp_etc etc.13;   same etc.0   etc.13
fp /usr/local local.13; same local.0 local.13
fp /var/lib   var.13;   same var.0   var.13
# Et la commande n'a modifié aucun $HOME -- ni celui d'alice, encore activée.
fp "$ALICE" alice.13; same alice.pre13 alice.13
fp "$BOB"   bob.13;   same bob.pre13   bob.13

echo "== Étape 14 : le shell d'alice ne casse pas, alors que l'arbre a disparu =="
# C'est ce qui PAIE la garde « [ -r … ] && source » du bloc, et la
# contrepartie exacte de « on ne touche pas aux \$HOME ».
as_user alice "zsh -i -c 'echo APRES_RETRAIT_OK'" > "$WORK/a14.out" 2> "$WORK/a14.err"
grep -q APRES_RETRAIT_OK "$WORK/a14.out"
if [ -s "$WORK/a14.err" ]; then
    printf '%s\n' "stderr non vide après retrait :" >&2; cat "$WORK/a14.err" >&2; exit 1
fi

echo "== Étape 15 : doctor nomme « bloc présent, arbre absent » et donne la sortie =="
as_user alice "$SRC/bin/nivuus doctor" > "$WORK/doc.out" 2>&1 || true
grep -qi "arbre\|tree" "$WORK/doc.out"
grep -q "nivuus disable" "$WORK/doc.out"

rm -rf "$WORK"
rm_user alice; rm_user bob; rm_user carol
echo "== Cible système OK =="
