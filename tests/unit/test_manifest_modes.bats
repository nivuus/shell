#!/usr/bin/env bats
#
# Une installation « réussie » que personne ne peut lire est un échec plus
# coûteux qu'un refus : elle casse tous les shells de la machine, et elle
# le fait après avoir dit « OK ». L'umask de l'administrateur ne décide de
# rien ; les modes finaux sont imposés.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export NIVUUS_STATE_DIR="$TMP/state"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/manifest.sh"
    printf 'contenu\n' > "$TMP/src"
    printf '#!/bin/sh\n' > "$TMP/exec"; chmod 700 "$TMP/exec"
    nivuus_manifest_begin system "$TMP/tree"
}

teardown() { rm -rf "$TMP"; }

@test "sans les crochets, rien ne change (le mode utilisateur est intact)" {
    umask 077
    nivuus_install_file "$TMP/src" "$TMP/tree/fichier"
    # cp -p a préservé le mode de la source : comportement historique.
    [ "$(fs_perms "$TMP/tree/fichier")" = "$(fs_perms "$TMP/src")" ]
}

@test "NIVUUS_INSTALL_FILE_MODE impose le mode, quel que soit l'umask" {
    umask 077
    # Source volontairement restrictive : sans imposition, « cp -p » la
    # recopierait telle quelle et l'arbre serait illisible pour les autres.
    chmod 600 "$TMP/src"
    NIVUUS_INSTALL_FILE_MODE=644 NIVUUS_INSTALL_DIR_MODE=755 \
        nivuus_install_file "$TMP/src" "$TMP/tree/fichier"
    [ "$(fs_perms "$TMP/tree/fichier")" = "644" ]
}

@test "un exécutable reste exécutable, et lisible par tous" {
    umask 077
    NIVUUS_INSTALL_FILE_MODE=644 NIVUUS_INSTALL_DIR_MODE=755 \
        nivuus_install_file "$TMP/exec" "$TMP/tree/bin/nivuus"
    [ "$(fs_perms "$TMP/tree/bin/nivuus")" = "755" ]
}

@test "les répertoires créés en chemin reçoivent le mode imposé" {
    umask 077
    NIVUUS_INSTALL_FILE_MODE=644 NIVUUS_INSTALL_DIR_MODE=755 \
        nivuus_install_file "$TMP/src" "$TMP/tree/a/b/fichier"
    [ "$(fs_perms "$TMP/tree/a")" = "755" ]
    [ "$(fs_perms "$TMP/tree/a/b")" = "755" ]
}

@test "nivuus_mkdir_p honore le mode imposé" {
    umask 077
    NIVUUS_INSTALL_DIR_MODE=755 nivuus_mkdir_p "$TMP/tree/x/y"
    [ "$(fs_perms "$TMP/tree/x/y")" = "755" ]
}

@test "nivuus_write_file honore le mode imposé" {
    umask 077
    printf 'bloc\n' | NIVUUS_INSTALL_FILE_MODE=644 NIVUUS_INSTALL_DIR_MODE=755 \
        nivuus_write_file "$TMP/tree/etc/skel-zshrc"
    [ "$(fs_perms "$TMP/tree/etc/skel-zshrc")" = "644" ]
}

@test "en --dry-run, aucun mode n'est appliqué parce que rien n'est écrit" {
    NIVUUS_DRY_RUN=1 NIVUUS_INSTALL_FILE_MODE=644 \
        nivuus_install_file "$TMP/src" "$TMP/tree/rien"
    [ ! -e "$TMP/tree/rien" ]
}

@test "NIVUUS_INSTALL_OWNER échoue en silence quand on n'est pas root" {
    # Un test unitaire tourne sans privilège : chown DOIT être non fatal,
    # sinon toute la couche PR devient inexécutable. Le vrai chown est
    # prouvé par tests/ci/run-system-target.sh, en root, dans un conteneur.
    run env NIVUUS_INSTALL_OWNER=root:root NIVUUS_INSTALL_FILE_MODE=644 \
        bash -c ". '$ROOT/lib/log.sh'; . '$ROOT/lib/manifest.sh'
                 NIVUUS_STATE_DIR='$TMP/state2' nivuus_manifest_begin system '$TMP/t2'
                 nivuus_install_file '$TMP/src' '$TMP/t2/f'"
    [ "$status" -eq 0 ]
    [ -f "$TMP/t2/f" ]
}
