#!/usr/bin/env bats

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"
    mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
}

teardown() { rm -rf "$TMP"; }

@test "nivuus is executable" {
    [ -x "$NIVUUS" ]
}

@test "help exits 0 and lists the subcommands" {
    run "$NIVUUS" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"install"* ]]
    [[ "$output" == *"uninstall"* ]]
}

@test "an unknown subcommand exits non-zero" {
    run "$NIVUUS" bogus
    [ "$status" -ne 0 ]
}

@test "install --dry-run touches nothing" {
    run "$NIVUUS" install --dry-run --yes --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ ! -e "$TMP/target" ]
    [ ! -e "$TMP/state" ]
    [ ! -e "$HOME/.zshrc" ]
}

@test "install --dry-run reports what it would do" {
    run "$NIVUUS" install --dry-run --yes --prefix "$TMP/target"
    [[ "$output" == *"dry-run"* ]]
}

@test "install creates the target and a zshrc block" {
    run "$NIVUUS" install --yes --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    [ -f "$TMP/target/config/00-core.zsh" ]
    [ -f "$TMP/target/.zshrc" ]
    run grep -c ">>> nivuus shell >>>" "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "install never creates a git repo in the target" {
    "$NIVUUS" install --yes --prefix "$TMP/target"
    [ ! -e "$TMP/target/.git" ]
}

@test "the installed CLI (not the repo checkout) works standalone" {
    "$NIVUUS" install --yes --prefix "$TMP/target"
    run "$TMP/target/bin/nivuus" uninstall --dry-run
    [ "$status" -eq 0 ]
    run "$TMP/target/bin/nivuus" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"install"* ]]
    [[ "$output" == *"uninstall"* ]]
}

@test "install twice is idempotent" {
    "$NIVUUS" install --yes --prefix "$TMP/target"
    cp "$HOME/.zshrc" "$TMP/zshrc.first"
    run "$NIVUUS" install --yes --prefix "$TMP/target"
    [ "$status" -eq 0 ]
    run diff "$TMP/zshrc.first" "$HOME/.zshrc"
    [ "$status" -eq 0 ]
}

@test "install preserves a pre-existing zshrc" {
    printf 'export MINE=42\n' > "$HOME/.zshrc"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    run grep -c "export MINE=42" "$HOME/.zshrc"
    [ "$output" = "1" ]
}

@test "uninstall removes the install dir and restores the zshrc" {
    printf 'export MINE=42\n' > "$HOME/.zshrc"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    run "$NIVUUS" uninstall --yes
    [ "$status" -eq 0 ]
    [ ! -d "$TMP/target" ]
    [ "$(cat "$HOME/.zshrc")" = "export MINE=42" ]
}

@test "uninstall never deletes zsh_history" {
    printf 'precious\n' > "$HOME/.zsh_history"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    "$NIVUUS" uninstall --yes --purge
    [ -f "$HOME/.zsh_history" ]
    [ "$(cat "$HOME/.zsh_history")" = "precious" ]
}

@test "uninstall --dry-run changes nothing" {
    "$NIVUUS" install --yes --prefix "$TMP/target"
    run "$NIVUUS" uninstall --dry-run --yes
    [ "$status" -eq 0 ]
    [ -d "$TMP/target" ]
}

@test "uninstall without a manifest exits cleanly with a message" {
    run "$NIVUUS" uninstall --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"aucune installation"* ]] || [[ "$output" == *"Aucune installation"* ]]
}

@test "purge does not delete HOME when NIVUUS_STATE_DIR points at it" {
    printf 'precious\n' > "$HOME/.zsh_history"
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    NIVUUS_STATE_DIR="$HOME" "$NIVUUS" install --yes --prefix "$TMP/target"
    NIVUUS_STATE_DIR="$HOME" "$NIVUUS" uninstall --yes --purge
    [ -d "$HOME" ]
    [ -f "$HOME/.zsh_history" ]
    [ "$(cat "$HOME/.zsh_history")" = "precious" ]
}

@test "purge keeps a zsh_local it did not create" {
    printf 'my own settings\n' > "$HOME/.zsh_local"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    "$NIVUUS" uninstall --yes --purge
    [ -f "$HOME/.zsh_local" ]
    [ "$(cat "$HOME/.zsh_local")" = "my own settings" ]
}

@test "an install aborted by a corrupt zshrc leaves nothing behind (no rm -rf needed)" {
    printf '# >>> nivuus shell >>>\nno closing marker\n' > "$HOME/.zshrc"
    run "$NIVUUS" install --yes --prefix "$TMP/target"
    [ "$status" -ne 0 ]
    [ ! -e "$TMP/target" ]
    [ ! -e "$NIVUUS_STATE_DIR" ]
}

@test "install --prefix without a value fails with a readable message" {
    run "$NIVUUS" install --yes --prefix
    [ "$status" -ne 0 ]
    [[ "$output" == *"--prefix"* ]]
    [[ "$output" != *"unbound variable"* ]]
}

@test "purge only removes backup files named like a sha256" {
    "$NIVUUS" install --yes --prefix "$TMP/target"
    mkdir -p "$NIVUUS_STATE_DIR/backups"
    printf 'not mine\n' > "$NIVUUS_STATE_DIR/backups/readme.md"
    printf 'not mine\n' > "$NIVUUS_STATE_DIR/backups/backup.db"
    "$NIVUUS" uninstall --yes --purge
    [ -f "$NIVUUS_STATE_DIR/backups/readme.md" ]
    [ -f "$NIVUUS_STATE_DIR/backups/backup.db" ]
}

@test "a plain (non-purge) uninstall keeps the manifest when a backup went missing" {
    # A diverged .zshrc that still contains the Nivuus block is now resolved
    # by stripping the block (see the strip-related tests below), so it no
    # longer leaves an unresolved survivor. Exercise IMPORTANT 6 with a
    # genuinely unresolved case instead: the recorded backup file itself is
    # gone (e.g. the user cleaned ~/.local/state by hand), independently of
    # whether .zshrc itself diverged.
    printf 'export MINE=42\n' > "$HOME/.zshrc"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    rm -f "$NIVUUS_STATE_DIR"/backups/*
    run "$NIVUUS" uninstall --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"introuvable"* ]]
    # The journal explaining why -- and where the backup is -- must survive
    # so the uninstall can be retried; it must not be deleted just because
    # this one file could not be reverted.
    [ -f "$NIVUUS_STATE_DIR/manifest.tsv" ]
}

@test "a diverged zshrc without the Nivuus block is conserved, not stripped" {
    printf 'export MINE=42\n' > "$HOME/.zshrc"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    # The user removes the whole Nivuus block themselves: nothing left for
    # us to strip surgically, so the old conservative behaviour must apply.
    printf 'export MINE=42\nsomething else entirely\n' > "$HOME/.zshrc"
    run "$NIVUUS" uninstall --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"Conservé"* ]]
    [ "$(cat "$HOME/.zshrc")" = "$(printf 'export MINE=42\nsomething else entirely')" ]
}

@test "uninstall strips the block from a zshrc the user edited after install" {
    printf 'export MINE=42\n' > "$HOME/.zshrc"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    printf 'alias foo=bar\n' >> "$HOME/.zshrc"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    "$NIVUUS" uninstall --yes --purge
    run grep -c "nivuus" "$HOME/.zshrc"
    [ "$status" -ne 0 ]                       # plus aucun bloc
    run grep -c "export MINE=42" "$HOME/.zshrc"
    [ "$output" = "1" ]                       # la ligne d'origine survit
    run grep -c "alias foo=bar" "$HOME/.zshrc"
    [ "$output" = "1" ]                       # l'édition de l'utilisateur survit
}

@test "a shell still starts cleanly after uninstalling an edited install" {
    printf 'export MINE=42\n' > "$HOME/.zshrc"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    printf 'alias foo=bar\n' >> "$HOME/.zshrc"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    "$NIVUUS" uninstall --yes --purge
    run zsh -i -c true
    [ "$status" -eq 0 ]
    [[ "$output" != *"no such file or directory"* ]]
}

@test "an aborted reinstall leaves the previous installation intact" {
    printf 'export MINE=42\n' > "$HOME/.zshrc"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    [ -f "$TMP/target/config/00-core.zsh" ]
    # l'utilisateur casse un marqueur : la 2e install doit échouer
    grep -v '<<< nivuus shell <<<' "$HOME/.zshrc" > "$TMP/z" && mv "$TMP/z" "$HOME/.zshrc"
    run "$NIVUUS" install --yes --prefix "$TMP/target"
    [ "$status" -ne 0 ]
    [ -f "$TMP/target/config/00-core.zsh" ]      # l'install #1 survit
    run zsh -i -c true
    [ "$status" -eq 0 ]                          # et le shell démarre
}

@test "purge survives an unreadable subdirectory under the cache" {
    [ "$(id -u)" -eq 0 ] && skip "root ignore les bits de permission"
    "$NIVUUS" install --yes --prefix "$TMP/target"
    mkdir -p "$HOME/.cache/nivuus-shell/blocked"
    chmod 000 "$HOME/.cache/nivuus-shell/blocked"
    run "$NIVUUS" uninstall --yes --purge
    chmod 700 "$HOME/.cache/nivuus-shell/blocked" 2>/dev/null || true
    [ "$status" -eq 0 ]
    [[ "$output" == *"désinstallé"* ]]
}
