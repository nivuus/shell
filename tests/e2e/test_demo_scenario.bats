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

@test "le conteneur de tournage est décrit et reproductible" {
    [ -f "$DEMO/Dockerfile" ]
    # Base épinglée : une démo tournée sur « latest » n'est pas reproductible.
    grep -qE '^FROM [a-z]+:[0-9]' "$DEMO/Dockerfile"
    # Le nom d'hôte est fixé : sinon chaque enregistrement diffère du
    # précédent par le prompt, et le .cast n'est plus diffable.
    grep -qF 'demo' "$DEMO/Dockerfile"
}

@test "le conteneur n'embarque jamais de clé réelle" {
    # Le risque de fuite est faible mais réel : on le ferme par construction.
    run grep -nE '(API_KEY|GOOGLE_API_KEY|sk-[A-Za-z0-9]{8})' "$DEMO/Dockerfile"
    [ "$status" -ne 0 ] || { echo "clé dans le Dockerfile : $output"; false; }
    grep -qF 'GEMINI_AUTH_MODE=cli' "$DEMO/Dockerfile"
    grep -qF 'AGY_DAEMON_ENABLED=false' "$DEMO/Dockerfile"
}

@test "replay-check.sh existe, est exécutable et POSIX" {
    [ -x "$DEMO/replay-check.sh" ]
    run sh -n "$DEMO/replay-check.sh"
    [ "$status" -eq 0 ]
}

# bats test_tags=docker
@test "GARDE 2: le scénario rejoué dans le conteneur passe de bout en bout" {
    command -v docker >/dev/null 2>&1 || skip "docker indisponible"
    run "$DEMO/replay-check.sh"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [[ "$output" == *"HOME is byte-identical"* ]]
}

# bats test_tags=docker
@test "GARDE 2: une commande supprimée du produit fait échouer le rejeu" {
    # Garde-fou du garde-fou : on prouve que le rejeu SAIT échouer, sinon
    # il ne serait qu'un job vert décoratif.
    command -v docker >/dev/null 2>&1 || skip "docker indisponible"
    tmp="$BATS_TEST_TMPDIR/scenario.txt"
    cp "$SCENARIO" "$tmp"
    printf '500\trun\tnivuus-cette-commande-nexiste-pas\n' >> "$tmp"
    run env NIVUUS_DEMO_SCENARIO="$tmp" "$DEMO/replay-check.sh"
    [ "$status" -ne 0 ]
}

sha() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

stamp_field() { sed -n "s/^$1=//p" "$ASSETS/demo.stamp" | head -n1; }

# La démo est un artefact MANUEL : elle exige un vrai terminal et une
# relecture humaine (spec § 3.3). Tant qu'aucun enregistrement n'a été
# produit, les gardes 3 et 4 n'ont rien à comparer -- mais elles ne doivent
# pas devenir muettes pour autant : le test « tout ou rien » ci-dessous
# interdit l'état intermédiaire, et « le README n'affiche pas d'artefact
# absent » interdit de promettre une image qui n'existe pas.
demo_recorded() { [ -f "$ASSETS/demo.stamp" ]; }

@test "la démo est enregistrée en entier, ou pas du tout" {
    n=0
    for f in "$ASSETS/demo.stamp" "$ASSETS/demo.cast"; do
        [ -f "$f" ] && n=$((n + 1))
    done
    [ "$n" -eq 0 ] || [ "$n" -eq 2 ] \
        || { echo "enregistrement à moitié présent : $n/2 fichiers"; false; }
}

@test "le README n'affiche jamais un artefact de démo absent" {
    # Le pire état possible : une image cassée en tête de page d'accueil.
    for a in demo.svg demo.gif; do
        if grep -qF "docs/assets/$a" "$ROOT/README.md"; then
            [ -f "$ASSETS/$a" ] || { echo "le README affiche $a, qui n'existe pas"; false; }
        fi
    done
}

@test "les trois outils de la démo existent et sont exécutables" {
    for f in record.sh render.sh; do
        [ -x "$DEMO/$f" ] || { echo "$f manquant ou non exécutable"; false; }
        run sh -n "$DEMO/$f"
        [ "$status" -eq 0 ]
    done
    [ -f "$DEMO/play.exp" ]
}

@test "GARDE 3: le tampon existe et porte ses champs" {
    demo_recorded || skip "aucun enregistrement : tools/demo/record.sh"
    [ -f "$ASSETS/demo.stamp" ]
    for k in scenario_sha256 cast_sha256 artefact artefact_sha256 version format; do
        [ -n "$(stamp_field "$k")" ] || { echo "champ absent du tampon : $k"; false; }
    done
}

@test "GARDE 3: le tampon correspond au scénario présent" {
    demo_recorded || skip "aucun enregistrement : tools/demo/record.sh"
    # Modifier scenario.txt sans réenregistrer : le mode de défaillance
    # n° 1 d'une démo versionnée.
    [ "$(stamp_field scenario_sha256)" = "$(sha "$SCENARIO")" ] \
        || { echo "scenario.txt a changé sans réenregistrement (tools/demo/record.sh)"; false; }
}

@test "GARDE 3: le tampon correspond au .cast présent" {
    demo_recorded || skip "aucun enregistrement : tools/demo/record.sh"
    [ -f "$ASSETS/demo.cast" ]
    [ "$(stamp_field cast_sha256)" = "$(sha "$ASSETS/demo.cast")" ] \
        || { echo "demo.cast ne correspond pas au tampon"; false; }
}

@test "GARDE 3: l'artefact affiché dérive bien du .cast présent" {
    demo_recorded || skip "aucun enregistrement : tools/demo/record.sh"
    a="$(stamp_field artefact)"
    [ -f "$ROOT/$a" ]
    [ "$(stamp_field artefact_sha256)" = "$(sha "$ROOT/$a")" ] \
        || { echo "$a ne dérive pas du demo.cast présent (tools/demo/render.sh)"; false; }
}

@test "l'artefact respecte le budget de poids de son format" {
    demo_recorded || skip "aucun enregistrement : tools/demo/record.sh"
    # 250 Ko pour un SVG ; 2 Mo pour le repli GIF (spec § 3.1). Le budget
    # suit le format déclaré, pas l'inverse : c'est ce qui rend le repli
    # exécutable sans replanifier.
    a="$(stamp_field artefact)"
    n="$(wc -c < "$ROOT/$a")"
    case "$(stamp_field format)" in
        svg) max=256000 ;;
        gif) max=2097152 ;;
        *)   echo "format inconnu dans le tampon"; false ;;
    esac
    [ "$n" -le "$max" ] || { echo "$a pèse $n octets (budget: $max)"; false; }
}

@test "le .cast est du TEXTE, donc auditable en revue" {
    demo_recorded || skip "aucun enregistrement : tools/demo/record.sh"
    # C'est l'argument décisif contre le GIF comme source (spec § 3.1) : une
    # PR qui modifie la démo doit être LISIBLE. Si le .cast devient binaire,
    # cette propriété est perdue en silence.
    run file "$ASSETS/demo.cast"
    [[ "$output" == *"text"* ]] || [[ "$output" == *"JSON"* ]]
    head -n1 "$ASSETS/demo.cast" | grep -q '"version"'
}

@test "aucune clé ni chemin personnel ne s'est glissé dans le .cast" {
    demo_recorded || skip "aucun enregistrement : tools/demo/record.sh"
    # Le .cast est du texte : on peut le fouiller, et donc on le fouille.
    run grep -nE 'sk-[A-Za-z0-9]{16}|AIza[A-Za-z0-9_-]{16}|/home/[a-z]+' "$ASSETS/demo.cast"
    if [ "$status" -eq 0 ]; then
        # Seul /home/demo est permis : c'est le HOME du conteneur de tournage.
        illegitimes="$(printf '%s\n' "$output" | grep -vE '/home/demo(/|[^a-z]|$)' || true)"
        [ -z "$illegitimes" ] || { echo "donnée suspecte dans le cast : $illegitimes"; false; }
    fi
}
