#!/usr/bin/env bats
#
# L'empreinte est le seul instrument de mesure de la promesse centrale du
# projet (« aucune trace après désinstallation »). Un instrument qui ne
# mesure pas ce qu'on croit est pire qu'aucun instrument : il transforme une
# absence de preuve en preuve. Ces tests décrivent ce qu'il DOIT voir.

load '../helpers/fingerprint'

setup() {
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/arbre/sous"
    printf 'contenu\n' > "$TMP/arbre/fichier"
}

teardown() { rm -rf "$TMP"; }

@test "l'empreinte capture uid et gid des fichiers et des répertoires" {
    run fs_fingerprint "$TMP/arbre"
    [ "$status" -eq 0 ]
    ids="$(id -u):$(id -g)"
    [[ "$output" == *"$ids"* ]]
    # Une ligne FILE porte : type, chemin, mode, uid:gid, sha256 -> 5 colonnes.
    n="$(printf '%s\n' "$output" | awk -F'\t' '$1=="FILE"{print NF; exit}')"
    [ "$n" -eq 5 ]
    # Une ligne DIR porte : type, chemin, mode, uid:gid -> 4 colonnes.
    n="$(printf '%s\n' "$output" | awk -F'\t' '$1=="DIR"{print NF; exit}')"
    [ "$n" -eq 4 ]
}

@test "un lien symbolique apparaît, avec sa cible" {
    ln -s fichier "$TMP/arbre/lien"
    run fs_fingerprint "$TMP/arbre"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LINK"* ]]
    [[ "$output" == *"/lien"* ]]
    printf '%s\n' "$output" | awk -F'\t' '$1=="LINK" && $NF=="fichier"{ok=1} END{exit !ok}'
}

@test "un lien mort apparaît aussi (il ne se cache pas derrière sa cible absente)" {
    ln -s /nulle/part "$TMP/arbre/mort"
    run fs_fingerprint "$TMP/arbre"
    [[ "$output" == *"/mort"* ]]
    # Et il n'est PAS compté comme un fichier : find -type f ne le voit pas,
    # find -type l si. Un lien mort laissé derrière est une trace.
    printf '%s\n' "$output" | awk -F'\t' '$2=="/mort" && $1=="LINK"{ok=1} END{exit !ok}'
}

@test "remplacer un fichier par un lien vers un contenu identique CHANGE l'empreinte" {
    # Le mode d'échec que l'ancienne empreinte laissait passer : le sha256
    # de la cible est le même, donc rien ne bougeait.
    fs_fingerprint "$TMP/arbre" > "$TMP/avant"
    printf 'contenu\n' > "$TMP/ailleurs"
    rm "$TMP/arbre/fichier"
    ln -s "$TMP/ailleurs" "$TMP/arbre/fichier"
    fs_fingerprint "$TMP/arbre" > "$TMP/apres"
    run diff "$TMP/avant" "$TMP/apres"
    [ "$status" -ne 0 ]
}

@test "la cible d'un lien est lue SANS être suivie" {
    ln -s /etc "$TMP/arbre/vers_etc"
    run fs_fingerprint "$TMP/arbre"
    [ "$status" -eq 0 ]
    # Si le lien était suivi, l'empreinte contiendrait le contenu de /etc.
    [[ "$output" != *"/vers_etc/"* ]]
}

@test "deux empreintes consécutives d'un arbre inchangé sont identiques" {
    # LA non-régression des six suites qui comparent before/after : si une
    # colonne était instable, tests/e2e/test_reversibility.bats deviendrait
    # rouge de façon intermittente, ce qui est pire qu'un échec franc.
    ln -s fichier "$TMP/arbre/lien"
    fs_fingerprint "$TMP/arbre" > "$TMP/un"
    fs_fingerprint "$TMP/arbre" > "$TMP/deux"
    run diff "$TMP/un" "$TMP/deux"
    [ "$status" -eq 0 ]
}

@test "fs_owner ne suit pas le lien" {
    ln -s fichier "$TMP/arbre/lien"
    run fs_owner "$TMP/arbre/lien"
    [ "$status" -eq 0 ]
    [ "$output" = "$(id -u):$(id -g)" ]
}

@test "la sortie reste triée et stable (LC_ALL=C)" {
    mkdir -p "$TMP/arbre/Z" "$TMP/arbre/a"
    run fs_fingerprint "$TMP/arbre"
    [ "$status" -eq 0 ]
    trie="$(printf '%s\n' "$output" | LC_ALL=C sort)"
    [ "$output" = "$trie" ]
}
