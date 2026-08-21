#!/usr/bin/env bats
#
# lib/system.sh décide où vont les fichiers du domaine root. Chaque chemin
# est un crochet : c'est ce qui permet à toute cette couche d'être prouvée
# sur une PR, sans conteneur, sans root et sans toucher au vrai /etc.

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_ETC_DIR="$TMP/etc"
    # shellcheck source=/dev/null
    . "$ROOT/lib/log.sh"; . "$ROOT/lib/detect.sh"; . "$ROOT/lib/system.sh"
}

teardown() { rm -rf "$TMP"; }

@test "les trois chemins du préfixe bougent ensemble" {
    [ "$(nivuus_system_tree)" = "$TMP/usr/local/share/nivuus-shell" ]
    [ "$(nivuus_system_bin)"  = "$TMP/usr/local/bin/nivuus" ]
    [ "$(nivuus_system_man)"  = "$TMP/usr/local/share/man/man1/nivuus.1" ]
}

@test "l'état système vit dans /var/lib/nivuus, pas dans l'arbre qu'il décrit" {
    [ "$(nivuus_system_state_dir)" = "$TMP/var/lib/nivuus" ]
    case "$(nivuus_system_state_dir)" in
        "$(nivuus_system_tree)"*) false ;;   # le journal ne vit jamais dans ce qu'il doit pouvoir supprimer
        *) true ;;
    esac
}

@test "les défauts sont ceux de la spec quand aucun crochet n'est posé" {
    ( unset NIVUUS_SYSTEM_PREFIX NIVUUS_SYSTEM_STATE_DIR NIVUUS_ETC_DIR
      . "$ROOT/lib/log.sh"; . "$ROOT/lib/detect.sh"; . "$ROOT/lib/system.sh"
      [ "$(nivuus_system_tree)" = "/usr/local/share/nivuus-shell" ]
      [ "$(nivuus_system_bin)" = "/usr/local/bin/nivuus" ]
      [ "$(nivuus_system_state_dir)" = "/var/lib/nivuus" ]
      [ "$(nivuus_system_skel)" = "/etc/skel/.zshrc" ]
      [ "$(nivuus_system_dropin)" = "/etc/zsh/zshrc.d/10-nivuus.zsh" ] )
}

@test "le rc global est /etc/zsh/zshrc quand /etc/zsh existe (Debian, Arch)" {
    mkdir -p "$TMP/etc/zsh"
    [ "$(nivuus_system_global_rc)" = "$TMP/etc/zsh/zshrc" ]
}

@test "le rc global est /etc/zshrc sinon (Fedora, RHEL, macOS)" {
    mkdir -p "$TMP/etc"
    [ "$(nivuus_system_global_rc)" = "$TMP/etc/zshrc" ]
}

@test "l'arbre hérité /etc/nivuus-shell est détecté, jamais supprimé" {
    mkdir -p "$TMP/etc/nivuus-shell/config"
    printf 'echo core\n' > "$TMP/etc/nivuus-shell/config/00-core.zsh"
    run nivuus_system_legacy_tree
    [ "$status" -eq 0 ]
    [ "$output" = "$TMP/etc/nivuus-shell" ]
    # Aucune suppression : on ne restaure pas ce qu'on n'a pas sauvegardé.
    [ -f "$TMP/etc/nivuus-shell/config/00-core.zsh" ]
}

@test "un /etc/nivuus-shell vide ou absent n'est pas un arbre hérité" {
    run nivuus_system_legacy_tree
    [ "$status" -ne 0 ]
    mkdir -p "$TMP/etc/nivuus-shell"
    run nivuus_system_legacy_tree
    [ "$status" -ne 0 ]
}

@test "le canal deb est annoncé sur Debian et Ubuntu" {
    printf 'ID=ubuntu\nID_LIKE=debian\n' > "$TMP/os-release"
    NIVUUS_OS_RELEASE="$TMP/os-release" run nivuus_system_package_channel
    [ "$status" -eq 0 ]
    [ "$output" = "deb" ]
}

@test "aucun canal n'est annoncé sur Fedora ou Alpine (le coeur du périmètre)" {
    printf 'ID=fedora\n' > "$TMP/os-release"
    NIVUUS_OS_RELEASE="$TMP/os-release" run nivuus_system_package_channel
    [ -z "$output" ]
    printf 'ID=alpine\n' > "$TMP/os-release"
    NIVUUS_OS_RELEASE="$TMP/os-release" run nivuus_system_package_channel
    [ -z "$output" ]
}

@test "lib/system.sh n'écrit rien : aucune mutation hors lib/manifest.sh" {
    run grep -nE '^[[:space:]]*(mv|rm|cp|mkdir|chmod|chown|ln|touch|tee)[[:space:]]' "$ROOT/lib/system.sh"
    [ "$status" -ne 0 ]
}

@test "lib/system.sh reste POSIX (bashismes interdits)" {
    run grep -nE 'BASH_SOURCE|\[\[|\+=|<<<|declare -|mapfile|\$\{[A-Za-z_]+\^\^' "$ROOT/lib/system.sh"
    [ "$status" -ne 0 ]
}
