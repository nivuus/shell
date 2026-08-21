#!/usr/bin/env bats
#
# Une documentation d'administration qui ment coûte plus cher qu'une
# documentation absente : elle produit des commandes qui échouent en root.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    INSTALL_DOC="$ROOT/doc/INSTALL.md"
    TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

@test "doc/INSTALL.md a une section d'administration" {
    run grep -nE '^#{2,3} .*(Administration|machine|system-wide)' "$INSTALL_DOC"
    [ "$status" -eq 0 ]
}

@test "la doc recommande le .deb EN PREMIER sur Debian et Ubuntu" {
    grep -q "apt install" "$INSTALL_DOC"
    # La recommandation précède la commande --system dans le fichier.
    deb="$(grep -n 'apt install' "$INSTALL_DOC" | head -1 | cut -d: -f1)"
    sys="$(grep -n 'nivuus install --system' "$INSTALL_DOC" | head -1 | cut -d: -f1)"
    [ "$deb" -lt "$sys" ]
}

@test "la limite de /etc/skel est écrite noir sur blanc" {
    grep -qi "créés après" "$INSTALL_DOC"
}

@test "la doc dit que uninstall --system ne touche à aucun HOME" {
    grep -qi "aucun .*HOME" "$INSTALL_DOC" || grep -qi "n'écrit dans aucun" "$INSTALL_DOC"
    grep -q "nivuus disable" "$INSTALL_DOC"
}

@test "la procédure de l'héritage /etc/nivuus-shell donne le retour en arrière" {
    grep -q "/etc/nivuus-shell" "$INSTALL_DOC"
    grep -qi "revenir en arrière" "$INSTALL_DOC" || grep -qi "restaurer" "$INSTALL_DOC"
}

@test "aucun ordonnanceur n'est promis" {
    run grep -nE 'systemd.timer|crontab -e.*nivuus' "$INSTALL_DOC"
    [ "$status" -ne 0 ]
    grep -q "sudo nivuus update" "$INSTALL_DOC"
}

@test "toutes les options système citées existent réellement dans l'aide" {
    aide="$("$ROOT/bin/nivuus" help)"
    for opt in --system --skel --activate-all --scan-users; do
        grep -q -- "$opt" "$INSTALL_DOC" || { echo "option non documentée: $opt"; false; }
        printf '%s' "$aide" | grep -q -- "$opt" || { echo "option non offerte: $opt"; false; }
    done
}

@test "l'extrait Dockerfile de la doc est exécutable en --dry-run" {
    # Un exemple faux est pire que pas d'exemple. On extrait la ligne
    # nivuus du bloc Dockerfile et on l'exécute en mode audit.
    line="$(grep -oE 'nivuus install --system[^"]*' "$INSTALL_DOC" | head -1)"
    [ -n "$line" ]
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local" NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus" NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1
    mkdir -p "$TMP/etc/skel"
    run env NIVUUS_UID=1000 sh -c "$ROOT/bin/${line} --dry-run --yes"
    [ "$status" -eq 0 ]
}

@test "doc/FEATURES.md ne publie plus « curl … | sudo bash »" {
    run grep -n 'sudo bash' "$ROOT/doc/FEATURES.md"
    [ "$status" -ne 0 ]
}

@test "doc/CLAUDE.md décrit le modèle réel, pas /etc/nivuus-shell" {
    run grep -n "temporairement indisponible\|Temporarily unavailable" "$ROOT/doc/CLAUDE.md"
    [ "$status" -ne 0 ]
    grep -q "/usr/local/share/nivuus-shell" "$ROOT/doc/CLAUDE.md"
}

@test "doc/CLAUDE.md ne présente plus ~/.config/nivuus-shell-backup comme le dossier de sauvegarde" {
    # Le vrai chemin depuis le chantier « manifeste » est
    # ~/.local/state/nivuus/backups/. L'ancien existe encore ailleurs
    # (config/13-system.zsh) : il ne doit simplement plus être présenté
    # comme celui de l'installation.
    run grep -nE 'Always backs up to .*nivuus-shell-backup' "$ROOT/doc/CLAUDE.md"
    [ "$status" -ne 0 ]
    grep -q '.local/state/nivuus/backups' "$ROOT/doc/CLAUDE.md"
}

@test "aucune doc ne mentionne un test_system_install qui n'a jamais existé" {
    run grep -rn "test_system_install" "$ROOT/doc/"
    [ "$status" -ne 0 ]
}
