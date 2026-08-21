#!/usr/bin/env bats
#
# Le one-liner ne clone plus rien : une machine sans git doit pouvoir
# installer, charger le shell, et désinstaller. Ce test le prouve en
# retirant git du PATH, pas en le supposant.

load '../helpers/fingerprint'

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    NIVUUS="$ROOT/bin/nivuus"
    TMP="$(mktemp -d)"
    export HOME="$TMP/home"; mkdir -p "$HOME"
    export NIVUUS_STATE_DIR="$TMP/state"
    # Un PATH sans git, mais avec tout le reste : on ne teste pas un
    # système amputé, on teste l'absence d'UN outil.
    NOGIT="$TMP/nogit"; mkdir -p "$NOGIT"
    for d in /usr/local/bin /usr/bin /bin /usr/sbin /sbin /opt/homebrew/bin; do
        [ -d "$d" ] || continue
        for f in "$d"/*; do
            [ -x "$f" ] || continue
            b="${f##*/}"
            [ "$b" = "git" ] && continue
            [ -e "$NOGIT/$b" ] || ln -sf "$f" "$NOGIT/$b"
        done
    done
}

teardown() { rm -rf "$TMP"; }

@test "installation complète sans git dans le PATH" {
    run env PATH="$NOGIT" "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    [ "$status" -eq 0 ]
    [ -f "$HOME/.nivuus-shell/config/00-core.zsh" ]
    [ -f "$HOME/.zshrc" ]
}

@test "le shell charge sans git" {
    env PATH="$NOGIT" "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    run env PATH="$NOGIT" HOME="$HOME" zsh -ic 'echo NIVUUS_OK'
    [ "$status" -eq 0 ]
    [[ "$output" == *"NIVUUS_OK"* ]]
}

@test "install puis uninstall sans git laisse HOME bit-identique" {
    fs_fingerprint "$HOME" > "$TMP/before"
    env PATH="$NOGIT" "$NIVUUS" install --yes --prefix "$HOME/.nivuus-shell"
    env PATH="$NOGIT" "$NIVUUS" uninstall --yes --purge
    fs_fingerprint "$HOME" > "$TMP/after"
    run diff "$TMP/before" "$TMP/after"
    [ "$status" -eq 0 ]
}
