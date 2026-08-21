#!/usr/bin/env bats
# La documentation du mode paquet doit exister, être exacte, et ne rien
# promettre qui n'existe pas encore.

setup() { ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"; }

@test "doc/PACKAGING.md documents the two-domain rule" {
    grep -qi 'manifeste' "$ROOT/doc/PACKAGING.md"
    grep -qi 'gestionnaire' "$ROOT/doc/PACKAGING.md"
}

@test "doc/PACKAGING.md documents the .nivuus-origin format exactly" {
    grep -q 'origin=package' "$ROOT/doc/PACKAGING.md"
    grep -q 'channel=' "$ROOT/doc/PACKAGING.md"
    grep -qi "absence" "$ROOT/doc/PACKAGING.md"
}

@test "doc/PACKAGING.md contains the channel abandonment policy" {
    # Écrite AVANT le premier abandon : c'est la mitigation du risque le
    # plus grave du chantier.
    grep -qi 'abandon' "$ROOT/doc/PACKAGING.md"
    grep -qi 'deux releases' "$ROOT/doc/PACKAGING.md"
}

@test "doc/INSTALL.md explains nivuus enable for package installs" {
    grep -q 'nivuus enable' "$ROOT/doc/INSTALL.md"
}

@test "SECURITY.md says a third-party channel INCREASES the attack surface" {
    # Le dire plutôt que de laisser croire que trois canaux valent mieux
    # qu'un du point de vue de la sécurité.
    grep -qi 'surface' "$ROOT/SECURITY.md"
}

@test "no channel install command is promised before the channel exists" {
    # Tant que le tap et l'AUR ne sont pas publiés, aucune commande
    # d'installation par canal ne doit figurer dans la documentation.
    run grep -rn 'brew install .*nivuus\|yay -S nivuus\|apt install nivuus' \
        "$ROOT/README.md" "$ROOT/doc/INSTALL.md"
    [ "$status" -ne 0 ]
}

@test "the guarded block is documented as guarded" {
    run grep -rn 'source "\$NIVUUS_SHELL_DIR/.zshrc"' "$ROOT/doc" "$ROOT/README.md"
    # Toute occurrence documentée doit montrer la garde.
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [[ "$line" == *'[ -r'* ]]
    done <<< "$output"
}
