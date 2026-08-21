#!/usr/bin/env bats
#
# La propriété centrale du projet, vue depuis le domaine root : ce que
# l'installation a écrit est rendu à l'octet près, et RIEN d'autre n'est
# touché -- surtout pas les $HOME, qui appartiennent à d'autres.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/etc" "$TMP/usr/local/bin"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_UID=0 NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1 NIVUUS_SYSTEM_PROBE_USER=''
}

teardown() { rm -rf "$TMP"; }

@test "INVARIANT: retrait bit-exact de /usr/local, /etc et /var/lib" {
    # Des fichiers préexistants dans les trois arbres : ils doivent survivre
    # exactement, y compris leurs modes et leurs propriétaires.
    printf 'script maison\n' > "$TMP/usr/local/bin/outil"; chmod 755 "$TMP/usr/local/bin/outil"
    printf 'zsh global\n' > "$TMP/etc/zshrc"
    mkdir -p "$TMP/var/lib/autre"; printf 'x\n' > "$TMP/var/lib/autre/etat"
    fs_fingerprint "$TMP/usr/local" > "$TMP/local.avant"
    fs_fingerprint "$TMP/etc"       > "$TMP/etc.avant"
    fs_fingerprint "$TMP/var/lib"   > "$TMP/var.avant"

    "$ROOT/bin/nivuus" install   --system --yes
    "$ROOT/bin/nivuus" uninstall --system --yes --purge

    fs_fingerprint "$TMP/usr/local" > "$TMP/local.apres"
    fs_fingerprint "$TMP/etc"       > "$TMP/etc.apres"
    fs_fingerprint "$TMP/var/lib"   > "$TMP/var.apres"
    diff "$TMP/local.avant" "$TMP/local.apres"
    diff "$TMP/etc.avant"   "$TMP/etc.apres"
    diff "$TMP/var.avant"   "$TMP/var.apres"
}

@test "INVARIANT: la désinstallation système ne touche AUCUN \$HOME" {
    printf 'export PERSO=1\n' > "$HOME/.zshrc"
    "$ROOT/bin/nivuus" install --system --yes
    fs_fingerprint "$HOME" > "$TMP/home.avant"
    "$ROOT/bin/nivuus" uninstall --system --yes --purge
    fs_fingerprint "$HOME" > "$TMP/home.apres"
    diff "$TMP/home.avant" "$TMP/home.apres"
    grep -q "PERSO" "$HOME/.zshrc"
}

@test "le lien /usr/local/bin/nivuus disparaît (et l'empreinte le voit)" {
    "$ROOT/bin/nivuus" install --system --yes
    [ -L "$TMP/usr/local/bin/nivuus" ]
    "$ROOT/bin/nivuus" uninstall --system --yes
    [ ! -L "$TMP/usr/local/bin/nivuus" ]
    [ ! -e "$TMP/usr/local/bin/nivuus" ]
}

@test "le message dit ce qui reste, sans compter ni scanner les comptes" {
    "$ROOT/bin/nivuus" install --system --yes
    run "$ROOT/bin/nivuus" uninstall --system --yes
    [[ "$output" == *"nivuus disable"* ]]
    [[ "$output" == *"appartiennent"* ]]
    # Aucun nombre de comptes : le compter supposerait de les lire.
    [[ "$output" != *"comptes activés"* ]]
}

@test "un manifeste système qui décrit un \$HOME est REFUSÉ en bloc" {
    "$ROOT/bin/nivuus" install --system --yes
    printf 'MODIFY\t%s/.zshrc\t-\t-\n' "$HOME" >> "$TMP/var/lib/nivuus/manifest.tsv"
    printf 'garde-moi\n' > "$HOME/.zshrc"
    run "$ROOT/bin/nivuus" uninstall --system --yes
    [ "$status" -ne 0 ]
    [[ "$output" == *"corrompu"* ]] || [[ "$output" == *"refus"* ]]
    grep -q "garde-moi" "$HOME/.zshrc"
    [ -d "$TMP/usr/local/share/nivuus-shell" ]     # rien n'a été défait non plus
}

@test "sans root, le refus arrive avant toute suppression" {
    "$ROOT/bin/nivuus" install --system --yes
    NIVUUS_UID=1000 run "$ROOT/bin/nivuus" uninstall --system --yes
    [ "$status" -ne 0 ]
    [ -d "$TMP/usr/local/share/nivuus-shell" ]
}

@test "--dry-run --system n'exige rien et ne défait rien" {
    "$ROOT/bin/nivuus" install --system --yes
    fs_fingerprint "$TMP/usr/local" > "$TMP/avant"
    NIVUUS_UID=1000 run "$ROOT/bin/nivuus" uninstall --system --dry-run --yes
    [ "$status" -eq 0 ]
    fs_fingerprint "$TMP/usr/local" > "$TMP/apres"
    diff "$TMP/avant" "$TMP/apres"
}

@test "un fichier système DIVERGÉ survit et est signalé" {
    "$ROOT/bin/nivuus" install --system --yes
    printf 'modifié par l administrateur\n' >> "$TMP/usr/local/share/nivuus-shell/config/00-core.zsh"
    run "$ROOT/bin/nivuus" uninstall --system --yes
    [ -f "$TMP/usr/local/share/nivuus-shell/config/00-core.zsh" ]
    grep -q "administrateur" "$TMP/usr/local/share/nivuus-shell/config/00-core.zsh"
}

@test "sans manifeste système, la commande le dit et ne fait rien" {
    run "$ROOT/bin/nivuus" uninstall --system --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"rien à faire"* ]] || [[ "$output" == *"Aucune"* ]]
}
