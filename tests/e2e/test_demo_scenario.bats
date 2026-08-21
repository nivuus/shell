#!/usr/bin/env bats
#
# Une démo périmée est pire qu'aucune démo : elle montre un produit qui
# n'existe plus, à quelqu'un qui n'a aucun moyen de le savoir. Quatre gardes,
# du moins cher au plus cher (spec § 3.4). Celui-ci est le premier :
# instantané, sur chaque PR.

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    DEMO="$ROOT/tools/demo"
    SCENARIO="$DEMO/scenario.txt"
    ASSETS="$ROOT/docs/assets"
}

# Les lignes utiles du scénario : « delai<TAB>genre<TAB>commande ».
scenario_lines() {
    grep -vE '^[[:space:]]*(#|$)' "$SCENARIO"
}

field() { printf '%s' "$1" | cut -f"$2"; }

@test "le scénario existe et déclare son en-tête" {
    [ -f "$SCENARIO" ]
    grep -q '^# meta: cols=' "$SCENARIO"
    grep -q '^# meta: ai-stub=' "$SCENARIO"
}

@test "le stub IA déclaré dans l'en-tête existe vraiment" {
    # Un stub déclaré mais absent, c'est une déclaration décorative.
    stub="$(sed -n 's/^# meta: ai-stub=\([^ ]*\).*/\1/p' "$SCENARIO" | head -n1)"
    [ -n "$stub" ]
    [ -x "$ROOT/$stub" ]
}

@test "chaque ligne du scénario a trois champs et un genre connu" {
    fautes=""
    while IFS= read -r l; do
        n="$(printf '%s' "$l" | awk -F'\t' '{print NF}')"
        [ "$n" -eq 3 ] || { fautes="$fautes
  champs=$n: $l"; continue; }
        case "$(field "$l" 2)" in
            run|unknown|type) ;;
            *) fautes="$fautes
  genre inconnu: $l" ;;
        esac
        printf '%s' "$(field "$l" 1)" | grep -qE '^[0-9]+$' \
            || fautes="$fautes
  délai non numérique: $l"
    done <<EOF
$(scenario_lines)
EOF
    [ -z "$fautes" ] || { echo "scénario malformé :$fautes"; false; }
}

@test "GARDE 1: toute commande « run » du scénario existe dans le produit" {
    rm -f "$ROOT"/config/*.zwc
    aide="$("$ROOT/bin/nivuus" help)"
    externes="curl wget sh zsh bash exec cd echo export print diff sudo"
    inconnues=""
    while IFS= read -r l; do
        [ "$(field "$l" 2)" = "run" ] || continue
        cmd="$(field "$l" 3 | awk '{print $1}')"
        case " $externes " in *" $cmd "*) continue ;; esac
        # sous-commande de nivuus
        if [ "$cmd" = "nivuus" ]; then
            sub="$(field "$l" 3 | awk '{print $2}')"
            printf '%s\n' "$aide" | grep -qE "nivuus +$sub" \
                || inconnues="$inconnues nivuus:$sub"
            continue
        fi
        # outil fourni par la démo elle-même
        [ -x "$DEMO/bin/$cmd" ] && continue
        [ -x "$ROOT/bin/$cmd" ] && continue
        grep -qhE "^[[:space:]]*(function[[:space:]]+)?${cmd}\(\)" "$ROOT"/config/*.zsh && continue
        grep -qhF -e "alias '${cmd}'=" -e "alias ${cmd}=" "$ROOT"/config/*.zsh && continue
        inconnues="$inconnues $cmd"
    done <<EOF
$(scenario_lines)
EOF
    [ -z "$inconnues" ] || {
        echo "la démo montre des commandes qui n'existent plus :$inconnues"; false; }
}

@test "GARDE 1: toute commande « unknown » est réellement introuvable" {
    # Le plan du command-not-found repose sur une commande ABSENTE. Le jour
    # où quelqu'un l'ajoute au produit ou aux prérequis, la démo montre un
    # « command not found » qui n'arrive plus : c'est ce test qui le dit.
    encore_la=""
    while IFS= read -r l; do
        [ "$(field "$l" 2)" = "unknown" ] || continue
        cmd="$(field "$l" 3 | awk '{print $1}')"
        grep -qhE "^[[:space:]]*(function[[:space:]]+)?${cmd}\(\)" "$ROOT"/config/*.zsh \
            && encore_la="$encore_la $cmd"
        grep -qhF -e "alias '${cmd}'=" -e "alias ${cmd}=" "$ROOT"/config/*.zsh \
            && encore_la="$encore_la $cmd"
        [ -x "$ROOT/bin/$cmd" ] && encore_la="$encore_la $cmd"
    done <<EOF
$(scenario_lines)
EOF
    [ -z "$encore_la" ] || {
        echo "la démo prétend que ces commandes n'existent pas :$encore_la"; false; }
}

@test "le dernier plan du scénario est la désinstallation, puis un diff" {
    # Le point de la démo. S'il fallait couper, on couperait tout le reste
    # avant lui -- donc il ne peut pas glisser au milieu par inadvertance.
    dernieres="$(scenario_lines | tail -n 3 | cut -f3)"
    printf '%s' "$dernieres" | grep -q 'nivuus uninstall'
    printf '%s' "$dernieres" | grep -q '^diff '
}

@test "le scénario tient dans le budget de 35 secondes" {
    total="$(scenario_lines | cut -f1 | awk '{s += $1} END {print s + 0}')"
    [ "$total" -le 35000 ] || { echo "scénario de ${total}ms (budget: 35000)"; false; }
    [ "$total" -ge 20000 ] || { echo "scénario de ${total}ms : trop court pour être lisible"; false; }
}
