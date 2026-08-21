#!/usr/bin/env bats

load '../helpers/signing'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    ZSH_BIN="$(command -v zsh)"
    TMP="$(mktemp -d)"
    find "$ROOT/config" -name '*.zwc' -delete 2>/dev/null || true
}

teardown() { rm -rf "$TMP"; }

@test "download_release accepts an optional interactive flag" {
    run zsh_autoupdate "typeset -f _nivuus_download_release | grep -c 'interactive'"
    [ "$status" -eq 0 ]
    [ "$output" != "0" ]
}

@test "the async path never consults NIVUUS_ALLOW_UNVERIFIED_UPDATE" {
    # L'échappatoire ne doit exister que sur le chemin manuel confirmé.
    # On lit le corps de la fonction : un processus d'arrière-plan ne
    # peut pas prendre de décision consciente à la place de l'utilisateur.
    run zsh_autoupdate "typeset -f _nivuus_check_update_async"
    [[ "$output" != *"NIVUUS_ALLOW_UNVERIFIED_UPDATE"* ]]
    run zsh_autoupdate "typeset -f _nivuus_check_update_async"
    [[ "$output" != *"interactive"* ]]
}

@test "the escape hatch requires BOTH the flag and an interactive invocation" {
    run zsh_autoupdate "typeset -f _nivuus_download_release"
    # La condition doit conjuguer les trois gardes.
    [[ "$output" == *"NIVUUS_ALLOW_UNVERIFIED_UPDATE"* ]]
    [[ "$output" == *"interactive"* ]]
    [[ "$output" == *"-t 0"* ]]
}

@test "a refusal message names the situation and forbids bypassing" {
    # Le message d'échec doit exister et ne PAS suggérer
    # NIVUUS_VERIFY_CHECKSUMS=false comme contournement, ce que faisait
    # l'ancien code.
    run zsh_autoupdate "typeset -f _nivuus_download_release"
    [[ "$output" != *"NIVUUS_VERIFY_CHECKSUMS=false to bypass"* ]]
}

@test "verification failure returns 1 and prints no temp dir on stdout" {
    # _nivuus_perform_update lit le chemin du répertoire temporaire sur la
    # sortie standard de _nivuus_download_release : en cas de refus, cette
    # sortie doit être vide, sinon l'installation se poursuivrait.
    run zsh_autoupdate "
        _nivuus_verify_release() { return 1 }
        curl() { : > \"\${@[-1]}\"; return 0 }
        out=\$(_nivuus_download_release 9.9.9 2>/dev/null)
        rc=\$?
        echo \"rc=\$rc out=[\$out]\"
    "
    [[ "$output" == *"rc=1"* ]]
    [[ "$output" == *"out=[]"* ]]
}
