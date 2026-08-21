#!/usr/bin/env bats
#
# L'installation système en entier, SANS root et SANS conteneur : les
# crochets de lib/system.sh déplacent /usr/local, /etc et /var/lib dans un
# répertoire temporaire. Ce qui exige vraiment root (chown, useradd, su)
# est prouvé ailleurs, par tests/ci/run-system-target.sh.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_UID=0            # « comme si » root : on ne l'est pas
    export NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1   # neutralise la reco .deb (Task 8)
    export NIVUUS_SYSTEM_PROBE_USER=''         # sonde en tant que soi-même (Task 11)
    mkdir -p "$TMP/etc"
}

teardown() { rm -rf "$TMP"; }

install_system() { "$ROOT/bin/nivuus" install --system --yes "$@"; }

@test "l'arbre est posé sous /usr/local/share/nivuus-shell" {
    run install_system
    [ "$status" -eq 0 ]
    [ -f "$TMP/usr/local/share/nivuus-shell/config/00-core.zsh" ]
    [ -f "$TMP/usr/local/share/nivuus-shell/.zshrc" ]
    [ -x "$TMP/usr/local/share/nivuus-shell/bin/nivuus" ]
}

@test "INVARIANT: une installation pour la machine ne touche AUCUN \$HOME" {
    fs_fingerprint "$HOME" > "$TMP/avant"
    install_system
    fs_fingerprint "$HOME" > "$TMP/apres"
    diff "$TMP/avant" "$TMP/apres"
    [ ! -f "$HOME/.zshrc" ]
    [ ! -d "$HOME/.local/state/nivuus" ]
}

@test "/usr/local/bin/nivuus est un lien vers l'arbre, et il fonctionne" {
    install_system
    [ -L "$TMP/usr/local/bin/nivuus" ]
    # Le cas que corrige la résolution de lien de bin/nivuus : derrière un
    # lien, NIVUUS_SRC_ROOT doit valoir l'arbre, pas /usr/local.
    run "$TMP/usr/local/bin/nivuus" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"nivuus"* ]]
}

@test "le manifeste système vit dans /var/lib/nivuus et porte mode=system" {
    install_system
    [ -f "$TMP/var/lib/nivuus/manifest.tsv" ]
    run head -n1 "$TMP/var/lib/nivuus/manifest.tsv"
    [[ "$output" == *"mode=system"* ]]
    [[ "$output" == *"dir=$TMP/usr/local/share/nivuus-shell"* ]]
}

@test "le manifeste est lisible par tous, les sauvegardes ne le sont pas" {
    install_system
    [ "$(fs_perms "$TMP/var/lib/nivuus/manifest.tsv")" = "644" ]
    [ "$(fs_perms "$TMP/var/lib/nivuus/backups")" = "700" ]
}

@test "l'arbre est en 0755/0644 quel que soit l'umask du sudo" {
    ( umask 077; install_system )
    [ "$(fs_perms "$TMP/usr/local/share/nivuus-shell")" = "755" ]
    [ "$(fs_perms "$TMP/usr/local/share/nivuus-shell/config/00-core.zsh")" = "644" ]
    [ "$(fs_perms "$TMP/usr/local/share/nivuus-shell/bin/nivuus")" = "755" ]
}

@test ".nivuus-origin déclare origin=system et channel=selfhosted" {
    install_system
    run cat "$TMP/usr/local/share/nivuus-shell/.nivuus-origin"
    [[ "$output" == *"origin=system"* ]]
    [[ "$output" == *"channel=selfhosted"* ]]
    [[ "$output" == *"prefix=$TMP/usr/local/share/nivuus-shell"* ]]
}

@test "INVARIANT: aucune ligne CHSH ne peut apparaître dans un manifeste système" {
    install_system
    run grep -c CHSH "$TMP/var/lib/nivuus/manifest.tsv"
    [ "$output" = "0" ]
}

@test "aucune entrée du manifeste système ne vise un \$HOME" {
    install_system
    run awk -F'\t' -v h="$HOME" 'NR>1 && index($2, h) == 1 { print; n++ } END { exit n>0 }' \
        "$TMP/var/lib/nivuus/manifest.tsv"
    [ "$status" -eq 0 ]
}

@test "la page de manuel est installée si elle existe dans les sources" {
    if [ ! -f "$ROOT/doc/nivuus.1" ]; then
        skip "doc/nivuus.1 arrive avec le chantier packaging"
    fi
    install_system
    [ -f "$TMP/usr/local/share/man/man1/nivuus.1" ]
}

@test "une seconde installation est idempotente et n'ajoute pas de doublon" {
    install_system
    n1="$(wc -l < "$TMP/var/lib/nivuus/manifest.tsv")"
    fs_fingerprint "$TMP/usr/local" > "$TMP/un"
    install_system
    fs_fingerprint "$TMP/usr/local" > "$TMP/deux"
    diff "$TMP/un" "$TMP/deux"
    n2="$(wc -l < "$TMP/var/lib/nivuus/manifest.tsv")"
    [ "$n2" -le "$((n1 * 2))" ]     # l'héritage recopie, il ne multiplie pas
}

@test "un arbre hérité /etc/nivuus-shell bloque l'installation, sans rien supprimer" {
    mkdir -p "$TMP/etc/nivuus-shell/config"
    printf 'echo legacy\n' > "$TMP/etc/nivuus-shell/config/00-core.zsh"
    run install_system
    [ "$status" -ne 0 ]
    [[ "$output" == *"/etc/nivuus-shell"* ]]
    [ -f "$TMP/etc/nivuus-shell/config/00-core.zsh" ]   # jamais supprimé
    [ ! -d "$TMP/usr/local/share/nivuus-shell" ]        # rien écrit
}

@test "sans root, le refus arrive avant toute écriture" {
    NIVUUS_UID=1000 run install_system
    [ "$status" -ne 0 ]
    [[ "$output" == *"sudo nivuus install --system"* ]]
    [ ! -e "$TMP/usr/local/share/nivuus-shell" ]
    [ ! -e "$TMP/var/lib/nivuus" ]
}
