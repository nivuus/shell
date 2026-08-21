#!/usr/bin/env bats
# La sortie de la phase 0 : un arbre posé À LA MAIN sous un préfixe partagé,
# avec un .nivuus-origin, se comporte déjà comme un paquet -- sans dpkg, sans
# pacman, sans brew. Les deux INVARIANT: ci-dessous sont les propriétés
# centrales du chantier ; tests.yml vérifie par grep qu'ils n'ont pas disparu.

load '../helpers/fingerprint'

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    command -v zsh >/dev/null || skip "zsh absent"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"
    SHARED="$TMP/usr/share/nivuus-shell"
    mkdir -p "$SHARED"
    # Copie bit-pour-bit de l'arbre de release : aucune disposition
    # spécifique à un canal (spec § 3.3).
    cp -a "$ROOT"/config "$ROOT"/themes "$ROOT"/lib "$ROOT"/bin "$ROOT"/keys "$SHARED"/ 2>/dev/null || true
    cp -a "$ROOT"/doc "$SHARED"/ 2>/dev/null || true
    cp "$ROOT"/.zshrc "$SHARED"/
    printf '3.2.0\n' > "$SHARED/.version"
    rm -f "$SHARED"/config/*.zwc
    printf 'origin=package\nchannel=deb\npackage=nivuus-shell\nversion=3.2.0\n' \
        > "$SHARED/.nivuus-origin"
    # Le lien symbolique que pose un PKGBUILD : il doit fonctionner.
    mkdir -p "$TMP/usr/bin"
    ln -s "$SHARED/bin/nivuus" "$TMP/usr/bin/nivuus"
    NIVUUS="$TMP/usr/bin/nivuus"
}

teardown() { rm -rf "$TMP"; }

# Ouvre un vrai shell interactif zsh lisant le ~/.zshrc de ce HOME.
interactive_shell() {
    env HOME="$HOME" NIVUUS_SHELL_DIR="$SHARED" \
        zsh -i -c 'print -r -- OK' 2>"$1"
}

@test "the symlinked nivuus works (PKGBUILD-style ln -s)" {
    run env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" help
    [ "$status" -eq 0 ]
}

@test "doctor reports origin package and the deb channel" {
    run env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" doctor
    [[ "$output" == *"package"* ]]
    [[ "$output" == *"deb"* ]]
}

@test "nivuus update prints the manager command, exits 0, downloads nothing" {
    run env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" update
    [ "$status" -eq 0 ]
    [[ "$output" == *"apt"* ]]
    [ ! -d "$HOME/.nivuus-backups" ]
}

@test "INVARIANT: three interactive shells leave no update-check timestamp" {
    # Preuve observable que _nivuus_check_update_async ne s'est JAMAIS
    # exécuté sur une installation par paquet. Si ce fichier apparaît,
    # l'updater destructif a pu partir contre un arbre appartenant à
    # dpkg / pacman / brew : la base du gestionnaire devient fausse et la
    # mise à jour système suivante écrase Nivuus sans prévenir.
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    local i
    for i in 1 2 3; do interactive_shell "$TMP/err$i" >/dev/null || true; done
    sleep 2   # laisse une éventuelle tâche &! le temps d'écrire
    [ ! -f "$HOME/.nivuus-shell-last-update-check" ]
}

@test "INVARIANT: package removed while the activation remains leaves stderr empty" {
    # Le cas NORMAL, pas le cas dégradé : « brew uninstall » / « apt purge »
    # n'ont aucun moyen de savoir qui a activé quoi. Sans la garde du bloc,
    # ce scénario casse le shell de tous les utilisateurs encore activés, à
    # chaque prompt, sans rapport visible avec l'action faite.
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    grep -q '>>> nivuus shell >>>' "$HOME/.zshrc"
    rm -rf "$TMP/usr"                       # le « paquet » est retiré
    # Écart au plan, justifié : « run cmd 2>fichier » ne capture RIEN --
    # bats détourne déjà stderr vers $output avant que la redirection ne
    # s'applique, et le test passerait même sans la garde du bloc (vérifié).
    # On appelle donc le shell directement, comme interactive_shell.
    local rc=0
    env HOME="$HOME" zsh -i -c 'print -r -- OK' >/dev/null 2>"$TMP/err" || rc=$?
    [ "$rc" -eq 0 ]
    run cat "$TMP/err"
    [ -z "$output" ]
}

@test "an interactive shell on a healthy package install has empty stderr too" {
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    interactive_shell "$TMP/err" >/dev/null
    run cat "$TMP/err"
    [ -z "$output" ]
}

@test "no .zwc is written into the shared tree by an interactive shell" {
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    interactive_shell "$TMP/err" >/dev/null
    sleep 2
    run find "$SHARED" -name '*.zwc'
    [ -z "$output" ]
}

@test "enable then disable leaves HOME bit-identical" {
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    fs_fingerprint "$HOME" > "$TMP/before"
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" disable --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "the manifest holds no CREATE entry inside the shared tree in package mode" {
    # La sûreté vient de l'ABSENCE d'entrées, pas d'une exception : la règle
    # « CREATE : suppression seulement si le hash correspond » n'a même pas
    # l'occasion de s'exécuter sur un fichier du gestionnaire.
    # Écart au plan, justifié : le seul CREATE possible est ~/.zshrc quand il
    # n'existait pas — c'est lui qui rend « disable » réversible.
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    run awk -F'\t' '$1=="CREATE" { print $2 }' "$NIVUUS_STATE_DIR/manifest.tsv"
    for path in $output; do
        [[ "$path" != "$SHARED"* ]]
    done
}

@test "the shared tree is never modified by enable/disable/update/doctor" {
    fs_fingerprint "$SHARED" > "$TMP/tree_before"
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" enable --yes
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" update >/dev/null
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" doctor >/dev/null 2>&1 || true
    env NIVUUS_SHELL_DIR="$SHARED" "$NIVUUS" disable --yes
    fs_fingerprint "$SHARED" > "$TMP/tree_after"
    run diff "$TMP/tree_before" "$TMP/tree_after"
    [ "$status" -eq 0 ]
}
