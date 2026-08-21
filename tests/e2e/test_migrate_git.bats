#!/usr/bin/env bats
#
# Le cas d'usage réel : une installation issue du one-liner historique,
# dont l'auto-update est désactivé depuis v3.0.0 parce que init_git_repo()
# y a laissé un dépôt git.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
    command -v git >/dev/null 2>&1 || skip "git indisponible"
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    PREFIX="$HOME/.nivuus-shell"
    # Explicite : l'environnement d'exécution (et la CI) exportent
    # NIVUUS_SHELL_DIR vers le checkout, que ce test ne doit jamais viser.
    export NIVUUS_SHELL_DIR="$PREFIX"
    "$NIVUUS" install --yes --prefix "$PREFIX" >/dev/null
}

teardown() { rm -rf "$TMP"; }

legacy_git() {
    ( cd "$PREFIX"
      git -c init.defaultBranch=master init -q .
      git remote add origin "git@github.com:maximeallanic/nivuus-shell.git"
      git add -A . >/dev/null
      git commit -q -m "Initial Nivuus Shell installation"
      git branch -M master ) >/dev/null 2>&1
}

@test "migrate déplace le .git parasite et dit où" {
    legacy_git
    run "$NIVUUS" migrate --yes
    [ "$status" -eq 0 ]
    [ ! -e "$PREFIX/.git" ]
    [[ "$output" == *"migration"* ]]
    run find "$NIVUUS_STATE_DIR/migration" -maxdepth 3 -name HEAD
    [ -n "$output" ]
}

@test "migrate ne supprime rien : le dépôt reste ouvrable" {
    legacy_git
    "$NIVUUS" migrate --yes >/dev/null
    moved="$(find "$NIVUUS_STATE_DIR/migration" -maxdepth 2 -type d -name git | head -n1)"
    [ -n "$moved" ]
    run git --git-dir="$moved" log -1 --format=%s
    [ "$status" -eq 0 ]
    [ "$output" = "Initial Nivuus Shell installation" ]
}

@test "après migrate, l'installation charge toujours" {
    legacy_git
    "$NIVUUS" migrate --yes >/dev/null
    run env HOME="$HOME" zsh -ic 'echo NIVUUS_OK'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NIVUUS_OK"* ]]
}

@test "INVARIANT: migrate ne touche PAS un vrai dépôt de développement" {
    legacy_git
    ( cd "$PREFIX" && printf 'mon travail\n' > TRAVAIL && git add TRAVAIL \
      && git commit -q -m "mon travail en cours" ) >/dev/null
    fs_fingerprint "$PREFIX" > "$TMP/before"
    run "$NIVUUS" migrate --yes
    [ "$status" -eq 0 ]
    [ -d "$PREFIX/.git" ]
    fs_fingerprint "$PREFIX" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "migrate sur une installation saine : ne fait rien, sort en 0" {
    run "$NIVUUS" migrate --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"ien à migrer"* ]]
}

@test "migrate --dry-run ne déplace rien" {
    legacy_git
    run "$NIVUUS" migrate --yes --dry-run
    [ "$status" -eq 0 ]
    [ -d "$PREFIX/.git" ]
    [ ! -e "$NIVUUS_STATE_DIR/migration" ]
}

@test "migrate hors TTY et sans --yes : explique, n'agit pas" {
    legacy_git
    run "$NIVUUS" migrate < /dev/null
    [ "$status" -eq 0 ]
    [ -d "$PREFIX/.git" ]
    [[ "$output" == *"--yes"* ]]
}

@test "update refuse et renvoie vers migrate quand le .git est parasite" {
    legacy_git
    run env NIVUUS_SHELL_DIR="$PREFIX" "$NIVUUS" update
    [ "$status" -ne 0 ]
    [[ "$output" == *"nivuus migrate"* ]]
}

@test "doctor signale le .git parasite sans y toucher" {
    legacy_git
    run env NIVUUS_SHELL_DIR="$PREFIX" "$NIVUUS" doctor
    [[ "$output" == *"migrate"* ]]
    [ -d "$PREFIX/.git" ]
}
