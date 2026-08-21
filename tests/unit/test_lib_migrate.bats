#!/usr/bin/env bats

setup() {
    LIB="${BATS_TEST_DIRNAME}/../../lib"
    source "$LIB/log.sh"; source "$LIB/migrate.sh"
    TMP="$(mktemp -d)"
    command -v git >/dev/null 2>&1 || skip "git indisponible"
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
}

teardown() { rm -rf "$TMP"; }

# Reproduit EXACTEMENT init_git_repo() de v3.0.0 (install.sh:334-346).
make_legacy() {
    d="$1"; mkdir -p "$d"; printf 'contenu\n' > "$d/fichier"
    ( cd "$d"
      git -c init.defaultBranch=master init -q .
      git remote add origin "git@github.com:maximeallanic/nivuus-shell.git"
      git add -A . >/dev/null
      git commit -q -m "Initial Nivuus Shell installation"
      git branch -M master ) >/dev/null 2>&1
}

@test "pas de .git -> none" {
    mkdir -p "$TMP/vide"
    run nivuus_git_state "$TMP/vide"
    [ "$output" = "none" ]
}

@test "le dépôt de init_git_repo() -> legacy" {
    make_legacy "$TMP/legacy"
    run nivuus_git_state "$TMP/legacy"
    [ "$output" = "legacy" ]
}

@test "des .zwc non suivis ne changent rien -> legacy" {
    make_legacy "$TMP/legacy"
    printf 'bytecode\n' > "$TMP/legacy/fichier.zwc"
    run nivuus_git_state "$TMP/legacy"
    [ "$output" = "legacy" ]
}

@test "un fichier SUIVI modifié -> dev" {
    make_legacy "$TMP/legacy"
    printf 'edite\n' > "$TMP/legacy/fichier"
    run nivuus_git_state "$TMP/legacy"
    [ "$output" = "dev" ]
}

@test "un second commit -> dev" {
    make_legacy "$TMP/legacy"
    ( cd "$TMP/legacy" && printf 'x\n' > b && git add b && git commit -q -m "mon travail" ) >/dev/null
    run nivuus_git_state "$TMP/legacy"
    [ "$output" = "dev" ]
}

@test "un message de commit différent -> dev" {
    d="$TMP/autre"; mkdir -p "$d"; printf 'x\n' > "$d/f"
    ( cd "$d"; git -c init.defaultBranch=master init -q .
      git add -A .; git commit -q -m "Initial commit" ) >/dev/null 2>&1
    run nivuus_git_state "$d"
    [ "$output" = "dev" ]
}

@test "un remote qui n'est pas l'amont -> dev" {
    make_legacy "$TMP/legacy"
    ( cd "$TMP/legacy" && git remote set-url origin "https://exemple.invalide/moi/fork.git" )
    run nivuus_git_state "$TMP/legacy"
    [ "$output" = "dev" ]
}

@test "le remote amont en HTTPS est accepté -> legacy" {
    make_legacy "$TMP/legacy"
    ( cd "$TMP/legacy" && git remote set-url origin "https://github.com/maximeallanic/nivuus-shell.git" )
    run nivuus_git_state "$TMP/legacy"
    [ "$output" = "legacy" ]
}

@test "un remote supplémentaire -> dev" {
    make_legacy "$TMP/legacy"
    ( cd "$TMP/legacy" && git remote add upstream "https://exemple.invalide/x.git" )
    run nivuus_git_state "$TMP/legacy"
    [ "$output" = "dev" ]
}

@test "une seconde branche -> dev" {
    make_legacy "$TMP/legacy"
    ( cd "$TMP/legacy" && git branch feature ) >/dev/null
    run nivuus_git_state "$TMP/legacy"
    [ "$output" = "dev" ]
}

@test "un stash -> dev" {
    make_legacy "$TMP/legacy"
    ( cd "$TMP/legacy" && printf 'wip\n' > fichier && git stash -q ) >/dev/null 2>&1
    run nivuus_git_state "$TMP/legacy"
    [ "$output" = "dev" ]
}

@test "un .git FICHIER (worktree, submodule) -> dev, jamais legacy" {
    mkdir -p "$TMP/wt"
    printf 'gitdir: /ailleurs/.git/worktrees/wt\n' > "$TMP/wt/.git"
    run nivuus_git_state "$TMP/wt"
    [ "$output" = "dev" ]
}

@test "le checkout de développement de Nivuus lui-même -> dev" {
    # Le garde-fou qui compte : ce dépôt-ci ne doit JAMAIS être vu legacy.
    run nivuus_git_state "${BATS_TEST_DIRNAME}/../.."
    [ "$output" = "dev" ]
}

@test "git absent alors qu'un .git existe -> unknown, jamais legacy" {
    make_legacy "$TMP/legacy"
    fake="$TMP/bin"; mkdir -p "$fake"
    for c in sh cat head awk sed grep; do
        p="$(command -v $c)" && ln -sf "$p" "$fake/$c"
    done
    # Chemin absolu : le PATH fabriqué ne contient volontairement pas bash.
    run env PATH="$fake" "$(command -v bash)" -c \
        ". '$LIB/log.sh'; . '$LIB/migrate.sh'; nivuus_git_state '$TMP/legacy'"
    [ "$output" = "unknown" ]
}

@test "nivuus_git_state n'écrit rien du tout" {
    make_legacy "$TMP/legacy"
    before="$(find "$TMP/legacy" | LC_ALL=C sort)"
    nivuus_git_state "$TMP/legacy" >/dev/null
    after="$(find "$TMP/legacy" | LC_ALL=C sort)"
    [ "$before" = "$after" ]
}

@test "nivuus_git_report décrit ce qu'il a constaté" {
    make_legacy "$TMP/legacy"
    run nivuus_git_report "$TMP/legacy"
    [ "$status" -eq 0 ]
    [[ "$output" == *"commit"* ]]
    [[ "$output" == *"origin"* ]]
}
