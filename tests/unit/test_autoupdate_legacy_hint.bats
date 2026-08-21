#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    ZSH_BIN="$(command -v zsh)"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    rm -f "$ROOT"/config/*.zwc
    command -v git >/dev/null 2>&1 || skip "git indisponible"
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

    DIR="$TMP/install"; mkdir -p "$DIR/lib" "$DIR/config"
    cp "$ROOT/lib/log.sh" "$ROOT/lib/migrate.sh" "$DIR/lib/"
    printf '9.9.9\n' > "$DIR/.version"
    printf 'contenu\n' > "$DIR/config/00-core.zsh"
}

teardown() { rm -rf "$TMP"; }

legacy_git() {
    ( cd "$DIR"
      git -c init.defaultBranch=master init -q .
      git remote add origin "git@github.com:maximeallanic/nivuus-shell.git"
      git add -A . >/dev/null
      git commit -q -m "Initial Nivuus Shell installation"
      git branch -M master ) >/dev/null 2>&1
}

# API injoignable volontairement : aucun test de ce dépôt ne touche au
# réseau réel, y compris sur le chemin de mise à jour « normal ».
update() {
    run env ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$DIR" HOME="$HOME" \
        NIVUUS_GITHUB_API="file://$TMP/api-absente" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; nivuus-update" < /dev/null
}

@test "dépôt parasite : le message nomme nivuus migrate" {
    legacy_git
    update
    [[ "$output" == *"nivuus migrate"* ]]
    [[ "$output" != *"git pull"* ]]
}

@test "dépôt parasite : nivuus-update ne le déplace PAS tout seul" {
    legacy_git
    update
    [ -d "$DIR/.git" ]
}

@test "vrai checkout de développement : le message « git pull » est conservé" {
    legacy_git
    ( cd "$DIR" && printf 'wip\n' > wip && git add wip && git commit -q -m "mon travail" ) >/dev/null
    update
    [[ "$output" == *"git pull"* ]]
    [[ "$output" != *"nivuus migrate"* ]]
}

@test "aucun .git : le chemin de mise à jour normal n'est pas modifié" {
    update
    [[ "$output" != *"nivuus migrate"* ]]
    [[ "$output" != *"Development checkout"* ]]
}

@test "lib/migrate.sh n'est PAS sourcée au chargement du module" {
    # Le module doit se charger sans lib/migrate.sh sur le disque : la
    # dépendance est paresseuse, donc le budget de démarrage est intact.
    rm -f "$DIR/lib/migrate.sh"
    run env ENABLE_AUTOUPDATE=false NIVUUS_SHELL_DIR="$DIR" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; echo CHARGE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CHARGE"* ]]
}

@test "le chemin asynchrone ne parle jamais de migration" {
    legacy_git
    run env NIVUUS_SHELL_DIR="$DIR" HOME="$HOME" \
        NIVUUS_GITHUB_API="file://$TMP/api-absente" \
        "$ZSH_BIN" -c "source '$ROOT/config/20-autoupdate.zsh'; _nivuus_check_update_async; wait" < /dev/null
    [[ "$output" != *"nivuus migrate"* ]]
    [ -d "$DIR/.git" ]
}
