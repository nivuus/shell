#!/usr/bin/env bats
#
# /usr/local/bin/nivuus est un lien. C'est la première mutation de type
# « lien » du projet : sans journalisation, uninstall ne le retirerait
# jamais, et l'empreinte (depuis la Task 1) le VERRAIT rester.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export NIVUUS_STATE_DIR="$TMP/state"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/manifest.sh"
    mkdir -p "$TMP/tree/bin"; printf '#!/bin/sh\n' > "$TMP/tree/bin/nivuus"
    nivuus_manifest_begin system "$TMP/tree"
}

teardown() { rm -rf "$TMP"; }

@test "le lien est créé et journalisé avec sa cible" {
    nivuus_install_symlink "$TMP/tree/bin/nivuus" "$TMP/usr/bin/nivuus"
    [ -L "$TMP/usr/bin/nivuus" ]
    [ "$(readlink "$TMP/usr/bin/nivuus")" = "$TMP/tree/bin/nivuus" ]
    grep -q "SYMLINK" "$NIVUUS_MANIFEST_TMP"
}

@test "la restauration retire un lien intact" {
    nivuus_install_symlink "$TMP/tree/bin/nivuus" "$TMP/usr/bin/nivuus"
    nivuus_restore_entry SYMLINK "$TMP/usr/bin/nivuus" "$TMP/tree/bin/nivuus" '-'
    [ ! -e "$TMP/usr/bin/nivuus" ]
    [ ! -L "$TMP/usr/bin/nivuus" ]
}

@test "un lien DÉTOURNÉ vers autre chose survit et est signalé" {
    nivuus_install_symlink "$TMP/tree/bin/nivuus" "$TMP/usr/bin/nivuus"
    ln -sf /bin/sh "$TMP/usr/bin/nivuus"
    NIVUUS_ROLLBACK_SURVIVORS="$TMP/survivants"
    run nivuus_restore_entry SYMLINK "$TMP/usr/bin/nivuus" "$TMP/tree/bin/nivuus" '-'
    [ -L "$TMP/usr/bin/nivuus" ]
    [ "$(readlink "$TMP/usr/bin/nivuus")" = "/bin/sh" ]
    grep -q "SYMLINK" "$TMP/survivants"
}

@test "un lien déjà absent ne fait pas échouer la restauration" {
    run nivuus_restore_entry SYMLINK "$TMP/usr/bin/nivuus" "$TMP/tree/bin/nivuus" '-'
    [ "$status" -eq 0 ]
}

@test "un fichier ordinaire déjà en place est sauvegardé, pas écrasé en silence" {
    mkdir -p "$TMP/usr/bin"
    printf 'script maison\n' > "$TMP/usr/bin/nivuus"
    nivuus_install_symlink "$TMP/tree/bin/nivuus" "$TMP/usr/bin/nivuus"
    [ -L "$TMP/usr/bin/nivuus" ]
    grep -q "MODIFY" "$NIVUUS_MANIFEST_TMP"
    # La sauvegarde existe et contient le script d'origine.
    ref="$(awk -F'\t' '$1=="MODIFY"{print $4; exit}' "$NIVUUS_MANIFEST_TMP")"
    grep -q "script maison" "$NIVUUS_BACKUP_DIR/$ref"
}

@test "en --dry-run, aucun lien n'est créé" {
    NIVUUS_DRY_RUN=1 nivuus_install_symlink "$TMP/tree/bin/nivuus" "$TMP/usr/bin/nivuus"
    [ ! -e "$TMP/usr/bin/nivuus" ]
}

@test "le lien réapparaît dans l'empreinte, et disparaît après restauration" {
    mkdir -p "$TMP/usr/bin"
    fs_fingerprint "$TMP/usr" > "$TMP/avant"
    nivuus_install_symlink "$TMP/tree/bin/nivuus" "$TMP/usr/bin/nivuus"
    fs_fingerprint "$TMP/usr" > "$TMP/pendant"
    ! diff -q "$TMP/avant" "$TMP/pendant"
    nivuus_restore_entry SYMLINK "$TMP/usr/bin/nivuus" "$TMP/tree/bin/nivuus" '-'
    fs_fingerprint "$TMP/usr" > "$TMP/apres"
    diff "$TMP/avant" "$TMP/apres"
}
