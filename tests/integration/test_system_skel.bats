#!/usr/bin/env bats
#
# /etc/skel ne rattrape PAS les comptes existants. C'est le mode d'échec
# historique de cette fonctionnalité : un administrateur convaincu d'avoir
# déployé pour tout le monde alors qu'il n'a rien fait pour les quatorze
# comptes déjà là. Le message doit le dire, et le test doit le prouver.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/etc/skel"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local" NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_UID=0 NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1 NIVUUS_SYSTEM_PROBE_USER=''
    # Quatorze comptes humains, comme dans l'exemple de la spec.
    : > "$TMP/passwd"
    i=1000; while [ "$i" -lt 1014 ]; do
        printf 'u%s:x:%s:%s::/home/u%s:/bin/bash\n' "$i" "$i" "$i" "$i" >> "$TMP/passwd"
        i=$((i + 1))
    done
    printf 'daemon:x:2:2::/:/usr/sbin/nologin\n' >> "$TMP/passwd"
    export NIVUUS_PASSWD_FILE="$TMP/passwd"
}

teardown() { rm -rf "$TMP"; }

@test "sans --skel, /etc/skel/.zshrc n'est PAS écrit" {
    "$ROOT/bin/nivuus" install --system --yes
    [ ! -f "$TMP/etc/skel/.zshrc" ]
}

@test "--skel écrit /etc/skel/.zshrc avec le bloc gardé" {
    "$ROOT/bin/nivuus" install --system --skel --yes
    [ -f "$TMP/etc/skel/.zshrc" ]
    grep -q ">>> nivuus shell >>>" "$TMP/etc/skel/.zshrc"
    grep -q "$TMP/usr/local/share/nivuus-shell" "$TMP/etc/skel/.zshrc"
    # La garde du chantier packaging : le shell ne casse pas si l'arbre part.
    grep -q '\[ -r ' "$TMP/etc/skel/.zshrc"
}

@test "le message NOMME la limite et donne le nombre de comptes non couverts" {
    run "$ROOT/bin/nivuus" install --system --skel --yes
    [[ "$output" == *"COMPTES CRÉÉS APRÈS"* ]]
    [[ "$output" == *"14"* ]]
    [[ "$output" == *"nivuus enable"* ]]
}

@test "le comptage lit /etc/passwd et ne parcourt JAMAIS /home" {
    # Un stat sur un $HOME NFS déclenche l'automonteur : lire n'est pas neutre.
    run grep -rnE 'ls .*/home|find .*/home' "$ROOT/bin/nivuus" "$ROOT/lib/system.sh"
    [ "$status" -ne 0 ]
}

@test "un /etc/skel/.zshrc préexistant est sauvegardé, puis restauré à l'octet près" {
    printf 'export SKEL_MAISON=1\n# fin\n' > "$TMP/etc/skel/.zshrc"
    fs_fingerprint "$TMP/etc" > "$TMP/avant"
    "$ROOT/bin/nivuus" install --system --skel --yes
    grep -q "SKEL_MAISON" "$TMP/etc/skel/.zshrc"      # le contenu d'origine survit
    grep -q "nivuus shell" "$TMP/etc/skel/.zshrc"     # et le bloc s'ajoute
    "$ROOT/bin/nivuus" uninstall --system --yes --purge
    fs_fingerprint "$TMP/etc" > "$TMP/apres"
    diff "$TMP/avant" "$TMP/apres"
}

@test "un /etc/skel/.zshrc créé par Nivuus disparaît au retrait" {
    "$ROOT/bin/nivuus" install --system --skel --yes
    "$ROOT/bin/nivuus" uninstall --system --yes --purge
    [ ! -f "$TMP/etc/skel/.zshrc" ]
}

@test "sans /etc/skel (macOS), --skel est REFUSÉ, pas ignoré" {
    rm -rf "$TMP/etc/skel"
    run "$ROOT/bin/nivuus" install --system --skel --yes
    [ "$status" -ne 0 ]
    [[ "$output" == *"/etc/skel"* ]] || [[ "$output" == *"skel"* ]]
    [[ "$output" == *"n'existe pas"* ]]
    [ ! -d "$TMP/usr/local/share/nivuus-shell" ]     # refus AVANT écriture
}

@test "--skel n'écrit toujours dans AUCUN \$HOME" {
    fs_fingerprint "$HOME" > "$TMP/h.avant"
    "$ROOT/bin/nivuus" install --system --skel --yes
    fs_fingerprint "$HOME" > "$TMP/h.apres"
    diff "$TMP/h.avant" "$TMP/h.apres"
}
