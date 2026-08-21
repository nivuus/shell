#!/usr/bin/env bats
# « disable » ne rejoue QUE la part activation du manifeste (le bloc .zshrc
# et le chsh), jamais les fichiers de l'arbre.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$HOME/.local/state/nivuus"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/zshrc.sh"; . "$ROOT/lib/manifest.sh"
    NIVUUS_ROLLBACK_SURVIVORS="$(mktemp)"
    NIVUUS_KEPT_BACKUP_REFS="$(mktemp)"
}

teardown() { rm -rf "$TMP"; rm -f "$NIVUUS_ROLLBACK_SURVIVORS" "$NIVUUS_KEPT_BACKUP_REFS"; }

@test "activation rollback restores .zshrc and leaves tree files alone" {
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    mkdir -p "$HOME/tree"
    printf 'shared\n' > "$HOME/tree/file"

    nivuus_manifest_begin user "$HOME/tree"
    printf '%s\n' "$(nivuus_zshrc_block "$HOME/tree")" > "$TMP/block"
    { cat "$TMP/block"; cat "$HOME/.zshrc"; } | nivuus_write_file "$HOME/.zshrc"
    nivuus_manifest_record CREATE "$HOME/tree/file" "$(nivuus_hash_file "$HOME/tree/file")" '-'
    nivuus_manifest_commit

    nivuus_manifest_rollback_activation

    run cat "$HOME/.zshrc"
    [ "$output" = "export MINE=1" ]
    # L'arbre n'a PAS été touché : c'est la propriété centrale de disable.
    [ -f "$HOME/tree/file" ]
}

@test "activation rollback drops the replayed entries from the manifest" {
    printf 'export MINE=1\n' > "$HOME/.zshrc"
    mkdir -p "$HOME/tree"; printf 'shared\n' > "$HOME/tree/file"
    nivuus_manifest_begin user "$HOME/tree"
    { nivuus_zshrc_block "$HOME/tree"; cat "$HOME/.zshrc"; } | nivuus_write_file "$HOME/.zshrc"
    nivuus_manifest_record CREATE "$HOME/tree/file" "$(nivuus_hash_file "$HOME/tree/file")" '-'
    nivuus_manifest_commit

    nivuus_manifest_rollback_activation

    run grep -c 'MODIFY' "$NIVUUS_MANIFEST"
    [ "$status" -ne 0 ]
    run grep -c 'CREATE' "$NIVUUS_MANIFEST"
    [ "$output" = "1" ]
}

@test "activation rollback on an empty manifest is a no-op, not an error" {
    run nivuus_manifest_rollback_activation
    [ "$status" -eq 0 ]
}

@test "a .zshrc CREATED by the activation is replayed, the tree is not" {
    # Sur un HOME sans ~/.zshrc, l'activation CRÉE ce fichier : sans rejeu de
    # cette entrée, « disable » laisserait une trace et la réversibilité
    # bit-exacte tomberait.
    mkdir -p "$HOME/tree"; printf 'shared\n' > "$HOME/tree/file"
    nivuus_manifest_begin user "$HOME/tree"
    nivuus_zshrc_block "$HOME/tree" | nivuus_write_file "$HOME/.zshrc"
    nivuus_manifest_record CREATE "$HOME/tree/file" "$(nivuus_hash_file "$HOME/tree/file")" '-'
    nivuus_manifest_commit
    [ -f "$HOME/.zshrc" ]

    nivuus_manifest_rollback_activation

    [ ! -f "$HOME/.zshrc" ]
    [ -f "$HOME/tree/file" ]
}
