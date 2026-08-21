#!/usr/bin/env bats
# La racine de bin/nivuus doit survivre à un lien symbolique : c'est le mode
# d'installation par défaut d'un PKGBUILD (ln -s) et de bin.install_symlink.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

# Imprime la racine que bin/nivuus calcule pour lui-même, sans exécuter
# la moindre sous-commande : on injecte une sortie juste après le calcul.
root_seen_from() {
    NIVUUS_PRINT_SRC_ROOT=1 "$1" help >/dev/null 2>&1
    NIVUUS_PRINT_SRC_ROOT=1 "$1" __srcroot 2>/dev/null
}

@test "direct invocation yields the repository root" {
    run root_seen_from "$ROOT/bin/nivuus"
    [ "$status" -eq 0 ]
    [ "$output" = "$ROOT" ]
}

@test "an absolute symlink yields the real root, not the symlink's parent" {
    mkdir -p "$TMP/usr/bin"
    ln -s "$ROOT/bin/nivuus" "$TMP/usr/bin/nivuus"
    run root_seen_from "$TMP/usr/bin/nivuus"
    [ "$status" -eq 0 ]
    [ "$output" = "$ROOT" ]
}

@test "a symlink to a symlink still yields the real root" {
    mkdir -p "$TMP/a" "$TMP/b"
    ln -s "$ROOT/bin/nivuus" "$TMP/a/nivuus"
    ln -s "$TMP/a/nivuus" "$TMP/b/nivuus"
    run root_seen_from "$TMP/b/nivuus"
    [ "$status" -eq 0 ]
    [ "$output" = "$ROOT" ]
}

@test "a RELATIVE symlink is resolved against the link's own directory" {
    # Le cas que readlink naïf rate : le lien pointe « ../real/bin/nivuus »,
    # ce qui n'a de sens que relativement au répertoire du lien.
    mkdir -p "$TMP/real/bin" "$TMP/real/lib" "$TMP/usr/bin"
    cp "$ROOT/bin/nivuus" "$TMP/real/bin/nivuus"
    cp "$ROOT"/lib/*.sh "$TMP/real/lib/"
    ln -s "../../real/bin/nivuus" "$TMP/usr/bin/nivuus"
    run root_seen_from "$TMP/usr/bin/nivuus"
    [ "$status" -eq 0 ]
    [ "$output" = "$TMP/real" ]
}

@test "a symlinked nivuus can actually source its libraries and run help" {
    # La preuve fonctionnelle, pas seulement le chemin : c'est ce qui casse
    # aujourd'hui (« . /usr/lib/log.sh: No such file or directory »).
    mkdir -p "$TMP/usr/bin"
    ln -s "$ROOT/bin/nivuus" "$TMP/usr/bin/nivuus"
    run "$TMP/usr/bin/nivuus" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"nivuus"* ]]
}

@test "a symlink loop is bounded and does not hang" {
    mkdir -p "$TMP/loop"
    ln -s "$TMP/loop/b" "$TMP/loop/a"
    ln -s "$TMP/loop/a" "$TMP/loop/b"
    run timeout 10 env NIVUUS_PRINT_SRC_ROOT=1 "$TMP/loop/a" __srcroot
    # Peu importe le code de retour : ce qui compte est que ça TERMINE.
    [ "$status" -ne 124 ]
}
