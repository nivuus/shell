#!/usr/bin/env bats
#
# Le test que la section 7 « Risques » du spec exige nommément :
# « installation v3.0.0 en place -> nouvelle installation par-dessus ->
# tout fonctionne », complété par la désinstallation propre.

load '../helpers/fingerprint'
load '../helpers/legacy'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    PREFIX="$HOME/.nivuus-shell"
    export NIVUUS_SHELL_DIR="$PREFIX"
    legacy_install "$HOME" "$PREFIX" "$ROOT"
}

teardown() { rm -rf "$TMP"; }

@test "l'état de départ est bien celui de la v3.0.0" {
    [ -d "$PREFIX/.git" ]
    [ "$(cat "$PREFIX/.version")" = "3.0.0" ]
    run cat "$HOME/.zshrc"
    [[ "$output" == *"# Nivuus Shell Configuration"* ]]
    [[ "$output" != *">>> nivuus shell >>>"* ]]
    run bash -c ". '$ROOT/lib/log.sh'; . '$ROOT/lib/migrate.sh'; nivuus_git_state '$PREFIX'"
    [ "$output" = "legacy" ]
}

@test "installer HEAD par-dessus v3.0.0 réussit" {
    run "$NIVUUS" install --yes --prefix "$PREFIX"
    [ "$status" -eq 0 ]
    [ -f "$PREFIX/bin/nivuus" ]
    [ -f "$PREFIX/lib/manifest.sh" ]
}

@test "INVARIANT: après la mise à jour, ~/.zshrc ne source Nivuus qu'UNE fois" {
    "$NIVUUS" install --yes --prefix "$PREFIX" >/dev/null
    run grep -c 'NIVUUS_SHELL_DIR/.zshrc' "$HOME/.zshrc"
    [ "$output" = "1" ]
    run grep -c '>>> nivuus shell >>>' "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "après la mise à jour, le shell démarre et charge Nivuus" {
    "$NIVUUS" install --yes --prefix "$PREFIX" >/dev/null
    run env HOME="$HOME" zsh -ic 'echo VERSION=$NIVUUS_SHELL_DIR'
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PREFIX"* ]]
}

@test "après la mise à jour, migrate débloque les mises à jour" {
    "$NIVUUS" install --yes --prefix "$PREFIX" >/dev/null
    [ -d "$PREFIX/.git" ]            # l'installation ne migre pas d'elle-même
    run "$NIVUUS" migrate --yes
    [ "$status" -eq 0 ]
    [ ! -e "$PREFIX/.git" ]
}

@test "INVARIANT: migrate puis install puis uninstall rend le HOME de départ" {
    # L'empreinte est prise APRÈS migrate : le déplacement du .git est
    # justement le changement voulu, et il n'a pas à être défait par la
    # désinstallation.
    "$NIVUUS" migrate --yes >/dev/null
    fs_fingerprint "$HOME" > "$TMP/before"
    "$NIVUUS" install --yes --prefix "$PREFIX" >/dev/null
    "$NIVUUS" uninstall --yes >/dev/null
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}

@test "deux installations successives de HEAD sont idempotentes" {
    "$NIVUUS" install --yes --prefix "$PREFIX" >/dev/null
    fs_fingerprint "$HOME" > "$TMP/une"
    "$NIVUUS" install --yes --prefix "$PREFIX" >/dev/null
    fs_fingerprint "$HOME" > "$TMP/deux"
    run diff "$TMP/une" "$TMP/deux"
    [ "$status" -eq 0 ]
    run grep -c '>>> nivuus shell >>>' "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "les personnalisations de l'utilisateur survivent à la mise à jour" {
    printf 'export MA_VARIABLE=42\n' >> "$HOME/.zsh_local"
    printf '\nalias mien="echo mien"\n' >> "$HOME/.zshrc"
    "$NIVUUS" install --yes --prefix "$PREFIX" >/dev/null
    run grep -q 'MA_VARIABLE=42' "$HOME/.zsh_local"
    [ "$status" -eq 0 ]
    run grep -q 'alias mien' "$HOME/.zshrc"
    [ "$status" -eq 0 ]
}
