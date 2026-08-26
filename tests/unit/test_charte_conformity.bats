#!/usr/bin/env bats

# bats-core ne fournit pas fail() : on la definit.
fail() { printf '%s\n' "$1" >&2; return 1; }

setup() {
    ROOT="${BATS_TEST_DIRNAME}/../.."
    CHARTE="$ROOT/lib/charte.sh"
    DESIGN="${NIVUUS_DESIGN_DIR:-$ROOT/../../design}"
    TOKENS="$DESIGN/assets/tokens.css"
}

# Valeur d'un token dans un bloc de tokens.css.
# $1 = role (danger|warn|ok|busy), $2 = ligne d'ouverture du bloc.
token_of() {
    awk -v role="--$1:" -v start="$2" '
        index($0, start) == 1 { inblock = 1; next }
        inblock && /^}/       { exit }
        inblock && index($0, role) {
            gsub(/[^#0-9A-Fa-f]/, "", $2); print toupper($2); exit
        }
    ' "$TOKENS"
}

# Valeur RGB que lib/charte.sh emet pour un role, dans une branche donnee.
# Les deux paires portent les memes noms de variables : on decoupe d'abord
# le fichier par branche, sinon on lirait toujours la premiere.
# $1 = ROLE en majuscules, $2 = light|dark
rgb_of() {
    local from to
    if [ "$2" = light ]; then
        from='charte_mode" = light'; to='            else'
    else
        from='            else'; to='            fi'
    fi
    sed -n "/$from/,/$to/p" "$CHARTE" |
        grep -m1 "NIVUUS_C_$1=" |
        sed -n 's/.*38;2;\([0-9;]*\)m.*/\1/p'
}

hex_to_rgb() {
    local h="${1#\#}"
    printf '%d;%d;%d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}

@test "les quatre semantiques sombres valent celles de tokens.css" {
    [ -f "$TOKENS" ] || skip "depot design absent ($TOKENS) — poser NIVUUS_DESIGN_DIR"
    for role in danger warn ok busy; do
        hex="$(token_of "$role" '[data-mode="dark"]')"
        [ -n "$hex" ] || fail "role --$role introuvable dans le bloc sombre"
        expected="$(hex_to_rgb "$hex")"
        actual="$(rgb_of "$(printf '%s' "$role" | tr 'a-z' 'A-Z')" dark)"
        [ "$actual" = "$expected" ] ||
            fail "--$role sombre : charte.sh dit '$actual', tokens.css dit '$expected' ($hex)"
    done
}

@test "les quatre semantiques claires valent celles de tokens.css" {
    [ -f "$TOKENS" ] || skip "depot design absent ($TOKENS) — poser NIVUUS_DESIGN_DIR"
    for role in danger warn ok busy; do
        hex="$(token_of "$role" ':root,')"
        [ -n "$hex" ] || fail "role --$role introuvable dans le bloc :root"
        expected="$(hex_to_rgb "$hex")"
        actual="$(rgb_of "$(printf '%s' "$role" | tr 'a-z' 'A-Z')" light)"
        [ "$actual" = "$expected" ] ||
            fail "--$role clair : charte.sh dit '$actual', tokens.css dit '$expected' ($hex)"
    done
}

@test "le test passe en skip si le depot design est absent" {
    # Relance imbriquee de bats sur ce meme fichier, filtree pour ne
    # selectionner que les deux tests de conformite ci-dessus : sans ce
    # filtre, ce test se re-selectionnerait lui-meme et recurserait a
    # l'infini. NIVUUS_DESIGN_DIR pointe vers un chemin inexistant pour
    # forcer le skip.
    run env NIVUUS_DESIGN_DIR="$BATS_TEST_TMPDIR/depot-design-absent" \
        bats --filter 'semantiques' "$BATS_TEST_FILENAME"
    [ "$status" -eq 0 ] || fail "bats imbrique a echoue : $output"
    skipped_count="$(printf '%s\n' "$output" | grep -c '# skip')"
    [ "$skipped_count" -eq 2 ] ||
        fail "attendu 2 tests skipped quand le depot design est absent, obtenu $skipped_count : $output"
}
