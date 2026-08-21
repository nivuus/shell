#!/usr/bin/env bats
#
# Un /etc modifié sans effet est pire qu'un refus : il fait croire que
# c'est fait. Cette suite exige la PREUVE, et l'annulation en son absence.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    command -v zsh >/dev/null 2>&1 || skip "zsh indisponible"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/etc/zsh"
    printf '# rc global de la distribution\n' > "$TMP/etc/zsh/zshrc"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local" NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_UID=0 NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1 NIVUUS_SYSTEM_PROBE_USER=''
    # La sonde d'activation doit lire NOTRE rc global, pas celui de la
    # machine hôte : ZDOTDIR ne suffit pas, on la redirige.
    export NIVUUS_SYSTEM_PROBE_RC="$TMP/etc/zsh/zshrc"
}

teardown() { rm -rf "$TMP"; }

@test "sans --activate-all, ni drop-in ni ligne dans le rc global" {
    "$ROOT/bin/nivuus" install --system --yes
    [ ! -f "$TMP/etc/zsh/zshrc.d/10-nivuus.zsh" ]
    run grep -c nivuus "$TMP/etc/zsh/zshrc"
    [ "$output" = "0" ]
}

@test "--activate-all pose le drop-in et UNE ligne dans le rc global" {
    "$ROOT/bin/nivuus" install --system --activate-all --yes
    [ -f "$TMP/etc/zsh/zshrc.d/10-nivuus.zsh" ]
    n="$(grep -c '10-nivuus.zsh' "$TMP/etc/zsh/zshrc")"
    [ "$n" -eq 1 ]
    grep -q "rc global de la distribution" "$TMP/etc/zsh/zshrc"   # le contenu d'origine reste
}

@test "une seconde activation n'ajoute pas une seconde ligne" {
    "$ROOT/bin/nivuus" install --system --activate-all --yes
    "$ROOT/bin/nivuus" install --system --activate-all --yes
    n="$(grep -c '10-nivuus.zsh' "$TMP/etc/zsh/zshrc")"
    [ "$n" -eq 1 ]
}

@test "la confirmation NOMME le conffile de la distribution" {
    run "$ROOT/bin/nivuus" install --system --activate-all --yes
    [[ "$output" == *"$TMP/etc/zsh/zshrc"* ]]
    [[ "$output" == *"conffile"* ]] || [[ "$output" == *"dpkg"* ]]
}

@test "l'activation est VÉRIFIÉE : le marqueur doit être posé pour de vrai" {
    run "$ROOT/bin/nivuus" install --system --activate-all --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"vérifi"* ]]
}

@test "sans preuve, l'activation est ANNULÉE et le rc global est rendu intact" {
    fs_fingerprint "$TMP/etc" > "$TMP/etc.avant"
    # On sabote la sonde : le drop-in ne sera jamais lu.
    run env NIVUUS_SYSTEM_PROBE_RC=/dev/null \
        "$ROOT/bin/nivuus" install --system --activate-all --yes
    [ "$status" -ne 0 ]
    [[ "$output" == *"à la main"* ]]
    fs_fingerprint "$TMP/etc" > "$TMP/etc.apres"
    diff "$TMP/etc.avant" "$TMP/etc.apres"
}

@test "enable --all --print n'écrit RIEN et sort en 0" {
    "$ROOT/bin/nivuus" install --system --yes
    fs_fingerprint "$TMP/etc" > "$TMP/avant"
    run "$ROOT/bin/nivuus" enable --all --print
    [ "$status" -eq 0 ]
    [[ "$output" == *"10-nivuus.zsh"* ]]
    [[ "$output" == *"$TMP/etc/zsh/zshrc"* ]]
    fs_fingerprint "$TMP/etc" > "$TMP/apres"
    diff "$TMP/avant" "$TMP/apres"
}

@test "enable --all fonctionne sur un arbre posé par un PAQUET" {
    # Le point qui fait de --system le porteur unique de l'activation
    # machine pour les quatre canaux.
    mkdir -p "$TMP/usr/share/nivuus-shell"
    cp -r "$ROOT/config" "$ROOT/.zshrc" "$TMP/usr/share/nivuus-shell/"
    printf 'origin=package\nchannel=deb\n' > "$TMP/usr/share/nivuus-shell/.nivuus-origin"
    run env NIVUUS_SHELL_DIR="$TMP/usr/share/nivuus-shell" "$ROOT/bin/nivuus" enable --all --print
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TMP/usr/share/nivuus-shell"* ]]
}

@test "enable --all écrit réellement, et disable --all défait à l'octet près" {
    "$ROOT/bin/nivuus" install --system --yes
    fs_fingerprint "$TMP/etc" > "$TMP/avant"
    "$ROOT/bin/nivuus" enable --all --yes
    [ -f "$TMP/etc/zsh/zshrc.d/10-nivuus.zsh" ]
    "$ROOT/bin/nivuus" disable --all --yes
    fs_fingerprint "$TMP/etc" > "$TMP/apres"
    diff "$TMP/avant" "$TMP/apres"
}

@test "disable --all retire la ligne et le drop-in, à l'octet près" {
    fs_fingerprint "$TMP/etc" > "$TMP/avant"
    "$ROOT/bin/nivuus" install --system --activate-all --yes
    "$ROOT/bin/nivuus" disable --all --yes
    fs_fingerprint "$TMP/etc" > "$TMP/apres"
    diff "$TMP/avant" "$TMP/apres"
}

@test "disable --all ne touche PAS à /etc/skel" {
    mkdir -p "$TMP/etc/skel"
    "$ROOT/bin/nivuus" install --system --skel --activate-all --yes
    [ -f "$TMP/etc/skel/.zshrc" ]
    "$ROOT/bin/nivuus" disable --all --yes
    [ -f "$TMP/etc/skel/.zshrc" ]        # l'activation machine n'est pas /etc/skel
    [ ! -f "$TMP/etc/zsh/zshrc.d/10-nivuus.zsh" ]
}

@test "uninstall --system rend le rc global bit-identique" {
    fs_fingerprint "$TMP/etc" > "$TMP/avant"
    "$ROOT/bin/nivuus" install --system --activate-all --yes
    "$ROOT/bin/nivuus" uninstall --system --yes --purge
    fs_fingerprint "$TMP/etc" > "$TMP/apres"
    diff "$TMP/avant" "$TMP/apres"
}

@test "sans root, --activate-all refuse avant d'écrire dans /etc" {
    NIVUUS_UID=1000 run "$ROOT/bin/nivuus" install --system --activate-all --yes
    [ "$status" -ne 0 ]
    [ ! -f "$TMP/etc/zsh/zshrc.d/10-nivuus.zsh" ]
}
