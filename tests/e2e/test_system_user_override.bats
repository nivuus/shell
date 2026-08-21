#!/usr/bin/env bats
#
# L'utilisateur gagne, toujours -- et il gagne UNE FOIS. Deux mécanismes
# sont en jeu : le grep du drop-in CHOISIT, la garde de réentrance PROTÈGE.
# Le second existe parce que le premier ne peut pas tout voir : le drop-in
# est lu AVANT ~/.zshrc.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    command -v zsh >/dev/null 2>&1 || skip "zsh indisponible"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/etc/zsh/zshrc.d"
    export NIVUUS_SYSTEM_PREFIX="$TMP/usr/local" NIVUUS_ETC_DIR="$TMP/etc"
    export NIVUUS_SYSTEM_STATE_DIR="$TMP/var/lib/nivuus"
    export NIVUUS_UID=0 NIVUUS_SYSTEM_ASSUME_NO_PACKAGE=1 NIVUUS_SYSTEM_PROBE_USER=''
    rm -f "$ROOT"/config/*.zwc "$ROOT/.zshrc.zwc"
    "$ROOT/bin/nivuus" install --system --yes >/dev/null
    # Drop-in simulé : on le source à la main, exactement comme le rc global
    # le ferait. La ligne 1 de « enable --all --print » est le commentaire de
    # chemin ; le corps commence à la 2.
    "$ROOT/bin/nivuus" enable --all --print | sed -n '2,$p' > "$TMP/dropin.zsh"
}

teardown() { rm -rf "$TMP"; }

# Charge le drop-in puis ~/.zshrc, dans l'ordre réel d'un shell interactif.
shell_like() {
    zsh -i -c "source '$TMP/dropin.zsh' >/dev/null 2>&1
               [ -f \"\$HOME/.zshrc\" ] && source \"\$HOME/.zshrc\" >/dev/null 2>&1
               print -r -- \"\$NIVUUS_SHELL_DIR|\$_nivuus_load_count|\$NIVUUS_ACTIVATED_BY\""
}

@test "système + activation machine, utilisateur sans bloc : l'arbre système, une fois" {
    run shell_like
    [[ "${lines[-1]}" == "$TMP/usr/local/share/nivuus-shell|1|system" ]]
}

@test "système + activation machine + installation utilisateur : l'utilisateur gagne" {
    NIVUUS_UID=1000 "$ROOT/bin/nivuus" install --yes --prefix "$HOME/.nivuus-shell" >/dev/null
    run shell_like
    [[ "${lines[-1]}" == "$HOME/.nivuus-shell|1|"* ]]
}

@test "INVARIANT: jamais de double source, quelle que soit la combinaison" {
    NIVUUS_UID=1000 "$ROOT/bin/nivuus" install --yes --prefix "$HOME/.nivuus-shell" >/dev/null
    run shell_like
    count="$(printf '%s' "${lines[-1]}" | cut -d'|' -f2)"
    [ "$count" = "1" ]
}

@test "une installation utilisateur REMPLACE le bloc, elle n'en ajoute pas un second" {
    NIVUUS_UID=1000 "$ROOT/bin/nivuus" install --yes --prefix "$HOME/.nivuus-shell" >/dev/null
    NIVUUS_UID=1000 "$ROOT/bin/nivuus" install --yes --prefix "$HOME/.nivuus-shell" >/dev/null
    n="$(grep -c '>>> nivuus shell >>>' "$HOME/.zshrc")"
    [ "$n" -eq 1 ]
}

@test "même en sourçant Nivuus deux fois à la main, un seul chargement" {
    # Le cas que le grep du drop-in ne peut PAS voir : un source direct,
    # hors bloc délimité. C'est ce qui justifie la garde de réentrance.
    printf 'source "%s/.zshrc"\n' "$TMP/usr/local/share/nivuus-shell" > "$HOME/.zshrc"
    run shell_like
    count="$(printf '%s' "${lines[-1]}" | cut -d'|' -f2)"
    [ "$count" = "1" ]
}
