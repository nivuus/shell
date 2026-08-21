#!/usr/bin/env bats
#
# La mise à jour d'un arbre système passe par l'installeur, donc par le
# manifeste. Le chemin destructif de l'auto-update (rm -rf + cp -r) est
# interdit ici : il écrirait hors inventaire, en root.

load '../helpers/release'
load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/etc"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local" NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_UID=0 NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1 NIVUUS_SYSTEM_PROBE_USER=''
    TREE="$TMP/usr/local/share/nivuus-shell"

    # Une « nouvelle version » : le dépôt, avec une marque reconnaissable.
    cp -r "$ROOT" "$TMP/src"; rm -rf "$TMP/src/.git"
    printf '9.9.9\n' > "$TMP/src/.version"
    printf '# marque de la v9.9.9\n' >> "$TMP/src/config/00-core.zsh"
    make_release "$TMP/src" "$TMP/rel" 9.9.9
    make_release_api "$TMP/api" fake/nivuus 9.9.9
    export NIVUUS_RELEASE_BASE_URL="file://$TMP/rel" NIVUUS_GITHUB_API="file://$TMP/api"
    export NIVUUS_VERSION=9.9.9

    "$ROOT/bin/nivuus" install --system --yes >/dev/null
}

teardown() { rm -rf "$TMP"; }

@test "sudo nivuus update remplace l'arbre par la nouvelle version" {
    run env NIVUUS_SHELL_DIR="$TREE" "$TREE/bin/nivuus" update
    [ "$status" -eq 0 ]
    grep -q "marque de la v9.9.9" "$TREE/config/00-core.zsh"
    [ "$(cat "$TREE/.version")" = "9.9.9" ]
}

@test "le manifeste système reste valide et décrit la NOUVELLE version" {
    env NIVUUS_SHELL_DIR="$TREE" "$TREE/bin/nivuus" update >/dev/null
    head -n1 "$TMP/var/lib/nivuus/manifest.tsv" | grep -q "mode=system"
    # La DERNIÈRE entrée pour ce chemin : le manifeste hérite des
    # précédentes, et c'est la plus récente que le rejeu applique.
    hash="$(awk -F'\t' -v p="$TREE/config/00-core.zsh" '$2==p{h=$3} END{print h}' \
            "$TMP/var/lib/nivuus/manifest.tsv")"
    actual="$(fs_hash "$TREE/config/00-core.zsh")"
    [ "$hash" = "$actual" ]
}

@test "la mise à jour reste RÉVERSIBLE : uninstall rend /usr/local bit-identique" {
    env NIVUUS_SHELL_DIR="$TREE" "$TREE/bin/nivuus" update >/dev/null
    "$ROOT/bin/nivuus" uninstall --system --yes --purge
    [ ! -d "$TREE" ]
    [ ! -e "$TMP/usr/local/bin/nivuus" ]
}

@test "sans root, la mise à jour refuse avant d'écrire" {
    before="$(fs_hash "$TREE/config/00-core.zsh")"
    NIVUUS_UID=1000 run env NIVUUS_SHELL_DIR="$TREE" "$TREE/bin/nivuus" update
    [ "$status" -eq 0 ]                       # on informe, on ne crie pas
    [[ "$output" == *"sudo nivuus update"* ]]
    [ "$(fs_hash "$TREE/config/00-core.zsh")" = "$before" ]
}

@test "une archive corrompue est REFUSÉE : l'arbre n'est pas touché" {
    tamper_release "$TMP/rel" 9.9.9
    before="$(fs_hash "$TREE/config/00-core.zsh")"
    run env NIVUUS_SHELL_DIR="$TREE" "$TREE/bin/nivuus" update
    [ "$status" -ne 0 ]
    [ "$(fs_hash "$TREE/config/00-core.zsh")" = "$before" ]
}

@test "INVARIANT: la mise à jour système n'emprunte JAMAIS _nivuus_perform_update" {
    # Ce chemin fait rm -rf + cp -r dans $NIVUUS_SHELL_DIR : sur un arbre
    # système, une écriture massive hors manifeste, dans le domaine root.
    run grep -n "_nivuus_perform_update" "$ROOT/bin/nivuus"
    [ "$status" -ne 0 ]
}

@test "une activation utilisateur survit à la mise à jour système" {
    NIVUUS_UID=1000 NIVUUS_SHELL_DIR="$TREE" "$ROOT/bin/nivuus" enable --yes >/dev/null
    cp "$HOME/.zshrc" "$TMP/zshrc.avant"
    env NIVUUS_SHELL_DIR="$TREE" "$TREE/bin/nivuus" update >/dev/null
    diff "$TMP/zshrc.avant" "$HOME/.zshrc"
}
