#!/usr/bin/env bats
#
# Une documentation d'installation qui décrit un comportement que le
# binaire n'a pas est pire que pas de documentation : elle fait perdre du
# temps AVANT la première ligne de code exécutée. Ce test la confronte au
# binaire.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    README="$ROOT/README.md"
    INSTALL_DOC="$ROOT/doc/INSTALL.md"
    REPO="$(sed -n 's#.*github.com/\([^"]*\)\.git.*#\1#p' "$ROOT/package.json" | head -n1)"
}

@test "doc/INSTALL.md existe" {
    [ -f "$INSTALL_DOC" ]
}

@test "le README ne recommande plus un git clone dans /tmp" {
    run grep -n 'clone.*\/tmp' "$README"
    [ "$status" -ne 0 ]
}

@test "le README porte le vrai one-liner, avec le bon dépôt" {
    run grep -F 'raw.githubusercontent.com' "$README"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$REPO"* ]]
    [[ "$output" == *"install.sh"* ]]
}

@test "README et doc/INSTALL.md donnent le MÊME one-liner" {
    a="$(grep -F 'raw.githubusercontent.com' "$README" | head -n1 | tr -d ' ')"
    b="$(grep -F 'raw.githubusercontent.com' "$INSTALL_DOC" | head -n1 | tr -d ' ')"
    [ -n "$a" ]
    [ "$a" = "$b" ]
}

@test "la désinstallation est documentée dans le README, pas seulement en annexe" {
    run grep -n 'nivuus uninstall' "$README"
    [ "$status" -eq 0 ]
}

@test "la désinstallation a son propre titre de section dans le README" {
    run grep -nE '^#{2,3} .*(Uninstall|Désinstall)' "$README"
    [ "$status" -eq 0 ]
}

@test "aucune documentation ne recommande sudo ./install.sh --system" {
    run grep -rn 'sudo ./install.sh --system' "$README" "$INSTALL_DOC" "$ROOT/doc/CLAUDE.md"
    [ "$status" -ne 0 ]
}

@test "toutes les sous-commandes nivuus citées dans doc/INSTALL.md existent" {
    aide="$("$ROOT/bin/nivuus" help)"
    for sub in $(grep -oE '\bnivuus [a-z-]+' "$INSTALL_DOC" | awk '{print $2}' | sort -u); do
        case "$sub" in
            shell) continue ;;   # « nivuus shell » dans une phrase, pas une commande
        esac
        printf '%s\n' "$aide" | grep -qE "nivuus +$sub" || {
            printf 'sous-commande documentée mais absente de « nivuus help » : %s\n' "$sub"
            return 1
        }
    done
}

@test "toutes les plateformes du spec sont couvertes par doc/INSTALL.md" {
    for p in Ubuntu Debian Arch Fedora Alpine macOS WSL; do
        grep -qi "$p" "$INSTALL_DOC" || { printf 'plateforme absente : %s\n' "$p"; return 1; }
    done
}

@test "doc/INSTALL.md est explicite sur ce que le one-liner ne garantit PAS" {
    run grep -niE 'amor|bootstrap|même origine|same origin' "$INSTALL_DOC"
    [ "$status" -eq 0 ]
    run grep -F -- '--verify-key' "$INSTALL_DOC"
    [ "$status" -eq 0 ]
}

@test "doc/INSTALL.md documente l'installation sans git" {
    run grep -niE 'sans git|no git|git n.est pas' "$INSTALL_DOC"
    [ "$status" -eq 0 ]
}

@test "la version épinglée d'install.sh est celle de .version" {
    pinned="$(sed -n 's/^NIVUUS_PINNED_VERSION="\(.*\)"/\1/p' "$ROOT/install.sh" | head -n1)"
    [ -n "$pinned" ]
    [ "$pinned" = "$(cat "$ROOT/.version")" ]
}
