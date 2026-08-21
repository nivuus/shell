#!/usr/bin/env bats
#
# Le silence au démarrage se paie par un diagnostic à la demande. doctor
# est le seul endroit où les trois silences délibérés du mode système (bloc
# gardé, /home non parcouru, conffile modifié) redeviennent visibles.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/etc/zsh"
    printf '# rc global\n' > "$TMP/etc/zsh/zshrc"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local" NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_UID=0 NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1 NIVUUS_SYSTEM_PROBE_USER=''
    export NIVUUS_SYSTEM_PROBE_RC="$TMP/etc/zsh/zshrc"
    export NIVUUS_PASSWD_FILE="$TMP/passwd"
    printf 'alice:x:1000:1000::%s/alice:/bin/zsh\n' "$TMP" > "$TMP/passwd"
    printf 'bob:x:1001:1001::%s/bob:/bin/zsh\n' "$TMP" >> "$TMP/passwd"
    mkdir -p "$TMP/alice" "$TMP/bob"
    TREE="$TMP/usr/local/share/nivuus-shell"
}

teardown() { rm -rf "$TMP"; }

@test "doctor nomme l'origine système et l'arbre" {
    "$ROOT/bin/nivuus" install --system --yes >/dev/null
    run env NIVUUS_SHELL_DIR="$TREE" "$ROOT/bin/nivuus" doctor
    [[ "$output" == *"système"* ]]
    [[ "$output" == *"$TREE"* ]]
    [[ "$output" == *"sudo nivuus update"* ]]
}

@test "double installation : doctor nomme les deux et dit lequel est actif" {
    "$ROOT/bin/nivuus" install --system --yes >/dev/null
    NIVUUS_UID=1000 "$ROOT/bin/nivuus" install --yes --prefix "$HOME/.nivuus-shell" >/dev/null
    run env NIVUUS_SHELL_DIR="$HOME/.nivuus-shell" "$ROOT/bin/nivuus" doctor
    [[ "$output" == *"$HOME/.nivuus-shell"* ]]
    [[ "$output" == *"$TREE"* ]]
    [[ "$output" == *"Actif"* ]] || [[ "$output" == *"actif"* ]]
}

@test "doctor ne convertit rien : aucune commande n'est exécutée à notre place" {
    "$ROOT/bin/nivuus" install --system --yes >/dev/null
    NIVUUS_UID=1000 "$ROOT/bin/nivuus" install --yes --prefix "$HOME/.nivuus-shell" >/dev/null
    env NIVUUS_SHELL_DIR="$HOME/.nivuus-shell" "$ROOT/bin/nivuus" doctor >/dev/null
    [ -d "$TREE" ]                       # l'arbre système est toujours là
    [ -d "$HOME/.nivuus-shell" ]         # et l'arbre utilisateur aussi
}

@test "bloc présent, arbre absent : doctor le dit et donne la réparation" {
    "$ROOT/bin/nivuus" install --system --yes >/dev/null
    NIVUUS_UID=1000 NIVUUS_SHELL_DIR="$TREE" "$ROOT/bin/nivuus" enable --yes >/dev/null
    rm -rf "$TREE"
    run env NIVUUS_SHELL_DIR="$TREE" "$ROOT/bin/nivuus" doctor
    [[ "$output" == *"absent"* ]]
    [[ "$output" == *"nivuus disable"* ]]
}

@test "l'héritage /etc/nivuus-shell est nommé, jamais supprimé" {
    mkdir -p "$TMP/etc/nivuus-shell/config"
    printf 'echo legacy\n' > "$TMP/etc/nivuus-shell/config/00-core.zsh"
    run "$ROOT/bin/nivuus" doctor
    [[ "$output" == *"/etc/nivuus-shell"* ]]
    [ -f "$TMP/etc/nivuus-shell/config/00-core.zsh" ]
}

@test "le conffile modifié par Nivuus est signalé par avance" {
    "$ROOT/bin/nivuus" install --system --activate-all --yes >/dev/null 2>&1 || skip "activation machine indisponible ici"
    run "$ROOT/bin/nivuus" doctor
    [[ "$output" == *"$TMP/etc/zsh/zshrc"* ]]
    [[ "$output" == *"dpkg"* ]] || [[ "$output" == *"conffile"* ]]
}

@test "INVARIANT: doctor ne lit AUCUN \$HOME d'autrui sans --scan-users" {
    "$ROOT/bin/nivuus" install --system --yes >/dev/null
    printf '# >>> nivuus shell >>>\n# <<< nivuus shell <<<\n' > "$TMP/alice/.zshrc"
    run env NIVUUS_SHELL_DIR="$TREE" "$ROOT/bin/nivuus" doctor
    [[ "$output" != *"$TMP/alice"* ]]
    [[ "$output" != *"alice"* ]]
}

@test "--scan-users liste les comptes activés, en lecture seule" {
    "$ROOT/bin/nivuus" install --system --yes >/dev/null
    printf '# >>> nivuus shell >>>\n# <<< nivuus shell <<<\n' > "$TMP/alice/.zshrc"
    printf 'export RIEN=1\n' > "$TMP/bob/.zshrc"
    cp "$TMP/alice/.zshrc" "$TMP/alice/.zshrc.temoin"
    run env NIVUUS_SHELL_DIR="$TREE" "$ROOT/bin/nivuus" doctor --system --scan-users
    [[ "$output" == *"alice"* ]]
    [[ "$output" != *"bob"* ]]
    diff "$TMP/alice/.zshrc.temoin" "$TMP/alice/.zshrc"     # lecture seule
}

@test "--scan-users dit pourquoi il n'est pas automatique" {
    "$ROOT/bin/nivuus" install --system --yes >/dev/null
    run env NIVUUS_SHELL_DIR="$TREE" "$ROOT/bin/nivuus" doctor --system --scan-users
    [[ "$output" == *"NFS"* ]] || [[ "$output" == *"automonteur"* ]]
}
